use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use imap::types::{Fetch, Flag, NameAttribute};
use imap::Session;
use lettre::address::Envelope;
use lettre::message::header::ContentType;
use lettre::message::{Attachment as SmtpAttachment, Mailbox, MultiPart, SinglePart};
use lettre::transport::smtp::authentication::Credentials;
use lettre::{Message as SmtpMessage, SmtpTransport, Transport};
use mailparse::{addrparse, parse_mail, DispositionType, MailAddr, MailHeaderMap, ParsedMail};
use native_tls::{TlsConnector, TlsStream};
use serde::{Deserialize, Serialize};
use serde_json::json;
use thiserror::Error;

type ImapSession = Session<TlsStream<std::net::TcpStream>>;

const PAGE: u32 = 50;

#[derive(Debug, Error)]
enum Error {
    #[error("{0}")]
    Msg(String),
}

impl From<imap::Error> for Error {
    fn from(value: imap::Error) -> Self {
        Error::Msg(value.to_string())
    }
}

impl From<native_tls::Error> for Error {
    fn from(value: native_tls::Error) -> Self {
        Error::Msg(value.to_string())
    }
}

impl From<mailparse::MailParseError> for Error {
    fn from(value: mailparse::MailParseError) -> Self {
        Error::Msg(value.to_string())
    }
}

impl From<io::Error> for Error {
    fn from(value: io::Error) -> Self {
        Error::Msg(value.to_string())
    }
}

#[derive(Clone, Debug, Deserialize)]
struct DiskAccount {
    id: String,
    name: String,
    #[serde(default, rename = "fromName")]
    from_name: String,
    email: String,
    #[serde(rename = "imapHost")]
    imap_host: String,
    #[serde(rename = "imapPort")]
    imap_port: String,
    #[serde(rename = "imapTls")]
    imap_tls: bool,
    #[serde(rename = "smtpHost")]
    smtp_host: String,
    #[serde(rename = "smtpPort")]
    smtp_port: String,
    #[serde(rename = "smtpTls")]
    smtp_tls: bool,
    username: String,
    #[serde(rename = "hasPassword")]
    has_password: Option<bool>,
}

#[derive(Deserialize)]
struct DiskFile {
    accounts: Vec<DiskAccount>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct MailUid {
    #[serde(default)]
    mailbox: String,
    uid: u32,
}

#[derive(Debug, Deserialize)]
struct Request {
    id: String,
    cmd: String,
    #[serde(default)]
    account: String,
    #[serde(default)]
    mailbox: String,
    #[serde(default)]
    query: String,
    #[serde(default)]
    uid: u32,
    #[serde(default)]
    uids: Vec<u32>,
    #[serde(default)]
    items: Vec<MailUid>,
    #[serde(default)]
    to: String,
    #[serde(default, rename = "toList")]
    to_list: Vec<String>,
    #[serde(default, rename = "ccList")]
    cc_list: Vec<String>,
    #[serde(default, rename = "bccList")]
    bcc_list: Vec<String>,
    #[serde(default)]
    subject: String,
    #[serde(default)]
    body: String,
    #[serde(default, rename = "inReplyTo")]
    in_reply_to: String,
    #[serde(default)]
    references: String,
    #[serde(default = "default_limit")]
    limit: u32,
    #[serde(default = "default_true", rename = "useCache")]
    use_cache: bool,
    #[serde(default)]
    unseen: bool,
    #[serde(default)]
    index: u32,
    #[serde(default)]
    action: String,
    #[serde(default)]
    files: Vec<String>,
}

fn default_limit() -> u32 {
    PAGE
}

fn default_true() -> bool {
    true
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Block {
    #[serde(rename = "type")]
    kind: String,
    text: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct MailAttachment {
    index: u32,
    name: String,
    mime: String,
    size: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Message {
    id: String,
    uid: u32,
    mailbox: String,
    from: String,
    #[serde(rename = "fromEmail")]
    from_email: String,
    mine: bool,
    when: String,
    #[serde(rename = "messageId")]
    message_id: String,
    #[serde(rename = "inReplyTo")]
    in_reply_to: String,
    references: String,
    #[serde(default)]
    to: Vec<Participant>,
    #[serde(default)]
    cc: Vec<Participant>,
    #[serde(default)]
    bcc: Vec<Participant>,
    text: String,
    blocks: Vec<Block>,
    #[serde(default)]
    attachments: Vec<MailAttachment>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Contact {
    name: String,
    email: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Participant {
    name: String,
    email: String,
    mine: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Conversation {
    id: String,
    #[serde(rename = "accountId")]
    account_id: String,
    mailbox: String,
    unread: bool,
    subject: String,
    preview: String,
    when: String,
    #[serde(skip, default)]
    when_ts: i64,
    participants: Vec<Participant>,
    #[serde(default)]
    to: Vec<Participant>,
    uids: Vec<u32>,
    #[serde(default)]
    items: Vec<MailUid>,
    #[serde(default)]
    messages: Vec<Message>,
    #[serde(default, rename = "latestMine")]
    latest_mine: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct EnvelopeCache {
    unread: u32,
    conversations: Vec<Conversation>,
    #[serde(default)]
    contacts: Vec<Contact>,
}

enum Event {
    Line(String),
    Exists,
}

struct AccountSession {
    account: DiskAccount,
    password: String,
    session: Option<ImapSession>,
}

struct State {
    config_path: String,
    accounts: Vec<DiskAccount>,
    sessions: HashMap<String, AccountSession>,
}

fn config_path() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    std::env::var("OMARCHY_MAIL_CONFIG").unwrap_or_else(|_| {
        format!("{home}/.local/state/omarchy/settings/omarchy-mail.json")
    })
}

fn cache_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(format!("{home}/.local/state/omarchy/mail/cache"))
}

fn cache_path(account_id: &str, mailbox: &str) -> PathBuf {
    cache_dir().join(account_id).join(format!("{mailbox}.json"))
}

fn load_account_cache(account_id: &str, mailbox: &str) -> Option<EnvelopeCache> {
    let path = cache_path(account_id, mailbox);
    let raw = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&raw).ok()
}

fn save_account_cache(account_id: &str, mailbox: &str, cache: &EnvelopeCache) {
    let path = cache_path(account_id, mailbox);
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(raw) = serde_json::to_string(cache) {
        let _ = std::fs::write(path, raw);
    }
}

fn load_list_cache(accounts: &[DiskAccount], mailbox: &str) -> Option<(u32, Vec<Conversation>, Vec<Contact>)> {
    let mut unread = 0u32;
    let mut conversations = Vec::new();
    let mut contacts = Vec::new();
    let mut any = false;
    for account in accounts {
        if let Some(cache) = load_account_cache(&account.id, mailbox) {
            any = true;
            unread += cache.unread;
            conversations.extend(cache.conversations);
            contacts.extend(cache.contacts);
        }
    }
    if !any {
        return None;
    }
    conversations.sort_by(|a, b| message_timestamp(&b.when).cmp(&message_timestamp(&a.when)));
    Some((unread, conversations, contacts))
}

fn save_list_cache(conversations: &[Conversation], contacts: &[Contact], unread: u32, mailbox: &str) {
    let mut by_account: HashMap<String, EnvelopeCache> = HashMap::new();
    for conv in conversations {
        let entry = by_account.entry(conv.account_id.clone()).or_insert_with(|| EnvelopeCache {
            unread: 0,
            conversations: Vec::new(),
            contacts: Vec::new(),
        });
        let mut row = conv.clone();
        row.messages.clear();
        entry.conversations.push(row);
    }
    for contact in contacts {
        if let Some(first) = by_account.values_mut().next() {
            first.contacts.push(contact.clone());
        }
    }
    if by_account.len() == 1 {
        if let Some(entry) = by_account.values_mut().next() {
            entry.unread = unread;
        }
    } else {
        for entry in by_account.values_mut() {
            entry.unread = unread;
        }
    }
    for (account_id, cache) in by_account {
        save_account_cache(&account_id, mailbox, &cache);
    }
}

fn load_accounts(path: &str) -> Result<Vec<DiskAccount>, Error> {
    let raw = std::fs::read_to_string(path)
        .map_err(|e| Error::Msg(format!("couldn't read {path}: {e}")))?;
    let file: DiskFile = serde_json::from_str(&raw)
        .map_err(|e| Error::Msg(format!("invalid config: {e}")))?;
    Ok(file.accounts)
}

fn lookup_password(account_id: &str) -> Result<String, Error> {
    let out = Command::new("secret-tool")
        .args(["lookup", "service", "omarchy-mail", "account", account_id])
        .output()
        .map_err(|e| Error::Msg(format!("secret-tool: {e}")))?;
    if !out.status.success() {
        return Err(Error::Msg("no password in keyring".into()));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn still_rfc2047(text: &str) -> bool {
    let lower = text.to_ascii_lowercase();
    let start = match lower.find("=?") {
        Some(i) => i,
        None => return false,
    };
    lower[start + 2..].contains("?q?") || lower[start + 2..].contains("?b?")
}

fn unfold_header(raw: &str) -> String {
    let s = raw.replace("\r\n", "\n").replace('\r', "\n");
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\n' {
            while matches!(chars.peek(), Some(' ' | '\t')) {
                chars.next();
            }
            continue;
        }
        out.push(ch);
    }
    out
}

fn decode_q_bytes(text: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(text.len());
    let mut i = 0;
    while i < text.len() {
        if text[i] == b'_' {
            out.push(b' ');
            i += 1;
        } else if text[i] == b'=' && i + 1 < text.len() && (text[i + 1] == b'\n' || text[i + 1] == b'\r') {
            i += 1;
            if i < text.len() && (text[i] == b'\n' || text[i] == b'\r') {
                i += 1;
            }
        } else if text[i] == b'=' && i + 2 < text.len() {
            match std::str::from_utf8(&text[i + 1..i + 3])
                .ok()
                .and_then(|hex| u8::from_str_radix(hex, 16).ok())
            {
                Some(byte) => {
                    out.push(byte);
                    i += 3;
                }
                None => {
                    i += 1;
                }
            }
        } else {
            out.push(text[i]);
            i += 1;
        }
    }
    out
}

fn decode_b64_bytes(text: &[u8]) -> Option<Vec<u8>> {
    fn val(c: u8) -> Option<u8> {
        match c {
            b'A'..=b'Z' => Some(c - b'A'),
            b'a'..=b'z' => Some(c - b'a' + 26),
            b'0'..=b'9' => Some(c - b'0' + 52),
            b'+' | b'-' => Some(62),
            b'/' | b'_' => Some(63),
            _ => None,
        }
    }
    let bytes: Vec<u8> = text
        .iter()
        .copied()
        .filter(|b| !b.is_ascii_whitespace() && *b != b'=')
        .collect();
    if bytes.is_empty() {
        return Some(Vec::new());
    }
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let a = val(bytes[i])?;
        let b = if i + 1 < bytes.len() { val(bytes[i + 1])? } else { 0 };
        out.push((a << 2) | (b >> 4));
        if i + 2 < bytes.len() {
            let c = val(bytes[i + 2]).unwrap_or(0);
            out.push((b << 4) | (c >> 2));
            if i + 3 < bytes.len() {
                let d = val(bytes[i + 3]).unwrap_or(0);
                out.push((c << 6) | d);
            }
        }
        i += 4;
    }
    Some(out)
}

fn decode_charset(label: &str, bytes: &[u8]) -> String {
    let lower = label.trim().to_ascii_lowercase();
    if lower == "utf-8" || lower == "utf8" || lower == "us-ascii" || lower == "ascii" {
        return String::from_utf8_lossy(bytes).into_owned();
    }
    if lower == "iso-8859-1" || lower == "latin1" || lower == "windows-1252" {
        return bytes.iter().map(|&b| b as char).collect();
    }
    String::from_utf8_lossy(bytes).into_owned()
}

fn parse_encoded_word(bytes: &[u8]) -> Option<(usize, String)> {
    if bytes.len() < 6 || bytes[0] != b'=' || bytes[1] != b'?' {
        return None;
    }
    let charset_end = bytes[2..].iter().position(|&b| b == b'?')? + 2;
    if charset_end + 1 >= bytes.len() {
        return None;
    }
    let enc_end = bytes[charset_end + 1..].iter().position(|&b| b == b'?')? + charset_end + 1;
    let mut k = enc_end + 1;
    while k + 1 < bytes.len() {
        if bytes[k] == b'?' && bytes[k + 1] == b'=' {
            let charset = std::str::from_utf8(&bytes[2..charset_end]).ok()?;
            let encoding = std::str::from_utf8(&bytes[charset_end + 1..enc_end]).ok()?;
            let payload = &bytes[enc_end + 1..k];
            let decoded = match encoding.to_ascii_uppercase().as_str() {
                "Q" => decode_charset(charset, &decode_q_bytes(payload)),
                "B" => decode_charset(charset, &decode_b64_bytes(payload)?),
                _ => return None,
            };
            return Some((k + 2, decoded));
        }
        k += 1;
    }
    None
}

fn decode_mime_words_fallback(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = String::new();
    let mut i = 0;
    let mut last_encoded = false;
    while i < bytes.len() {
        if last_encoded && bytes[i].is_ascii_whitespace() {
            let mut j = i;
            while j < bytes.len() && bytes[j].is_ascii_whitespace() {
                j += 1;
            }
            if parse_encoded_word(&bytes[j..]).is_some() {
                i = j;
                continue;
            }
        }
        if let Some((consumed, decoded)) = parse_encoded_word(&bytes[i..]) {
            out.push_str(&decoded);
            i += consumed;
            last_encoded = true;
            continue;
        }
        last_encoded = false;
        let rest = &input[i..];
        let ch = rest.chars().next().unwrap_or('\0');
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

fn take_decoded(text: String) -> Option<String> {
    let trimmed = text.trim().to_string();
    if trimmed.is_empty() || still_rfc2047(&trimmed) {
        None
    } else {
        Some(trimmed)
    }
}

fn decode_mime_words(raw: &str) -> String {
    let unfolded = unfold_header(raw);
    if let Some(text) = take_decoded(decode_mime_words_fallback(&unfolded)) {
        return text;
    }
    if let Ok(text) = rfc2047_decoder::Decoder::new()
        .too_long_encoded_word_strategy(rfc2047_decoder::RecoverStrategy::Decode)
        .decode(unfolded.as_bytes())
    {
        if let Some(text) = take_decoded(text) {
            return text;
        }
    }
    let header = format!("Subject: {unfolded}\r\n");
    if let Ok((parsed, _)) = mailparse::parse_header(header.as_bytes()) {
        if let Some(text) = take_decoded(parsed.get_value()) {
            return text;
        }
    }
    raw.trim().to_string()
}

fn decode_bytes(bytes: &[u8]) -> String {
    let mut raw = String::from_utf8_lossy(bytes).trim().to_string();
    if raw.len() >= 2 && raw.starts_with('"') && raw.ends_with('"') {
        raw = raw[1..raw.len() - 1].trim().to_string();
    }
    decode_mime_words(&raw)
}

fn address_parts(list: &Option<Vec<imap_proto::types::Address<'_>>>) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let Some(list) = list else { return out };
    for addr in list {
        let mailbox = addr
            .mailbox
            .as_ref()
            .map(|m| String::from_utf8_lossy(m).into_owned())
            .unwrap_or_default();
        let host = addr
            .host
            .as_ref()
            .map(|m| String::from_utf8_lossy(m).into_owned())
            .unwrap_or_default();
        let email = if mailbox.is_empty() {
            String::new()
        } else if host.is_empty() {
            mailbox
        } else {
            format!("{mailbox}@{host}")
        };
        let name = addr
            .name
            .as_ref()
            .map(|m| decode_bytes(m))
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| email.clone());
        out.push((name, email));
    }
    out
}

fn imap_quote(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn mailbox_candidates(role: &str) -> Vec<&'static str> {
    match role {
        "archive" => vec!["Archive", "Archives", "INBOX.Archive", "[Gmail]/All Mail"],
        "trash" => vec!["Trash", "Deleted Messages", "INBOX.Trash", "[Gmail]/Trash"],
        "sent" => vec![
            "INBOX.Sent Messages",
            "Sent Messages",
            "Sent Items",
            "Sent",
            "INBOX.Sent",
            "[Gmail]/Sent Mail",
        ],
        "drafts" => vec!["INBOX.Drafts", "Drafts", "Draft", "[Gmail]/Drafts"],
        "junk" => vec![
            "INBOX.Junk",
            "INBOX.spam",
            "INBOX.Spam",
            "Junk",
            "Spam",
            "Junk E-mail",
            "Junk Email",
            "Bulk Mail",
            "INBOX.Bulk Mail",
            "[Gmail]/Spam",
        ],
        _ => vec!["INBOX"],
    }
}

fn special_use_flag(role: &str) -> Option<&'static str> {
    match role {
        "sent" => Some("\\Sent"),
        "drafts" => Some("\\Drafts"),
        "trash" => Some("\\Trash"),
        "archive" => Some("\\Archive"),
        "junk" => Some("\\Junk"),
        _ => None,
    }
}

fn has_special_use(name: &imap::types::Name, flag: &str) -> bool {
    name.attributes().iter().any(|attr| match attr {
        NameAttribute::Custom(value) => value.eq_ignore_ascii_case(flag),
        _ => false,
    })
}

fn resolve_mailbox(session: &mut ImapSession, role: &str) -> Result<String, Error> {
    if role == "inbox" || role.is_empty() {
        return Ok("INBOX".into());
    }
    let listed = session.list(None, Some("*"))?;
    let mut hits: Vec<String> = Vec::new();
    if let Some(flag) = special_use_flag(role) {
        for name in listed.iter() {
            if has_special_use(name, flag) {
                let n = name.name().to_string();
                if !hits.iter().any(|h| h.eq_ignore_ascii_case(&n)) {
                    hits.push(n);
                }
            }
        }
    }
    for candidate in mailbox_candidates(role) {
        for name in listed.iter() {
            if name.name().eq_ignore_ascii_case(candidate) {
                let n = name.name().to_string();
                if !hits.iter().any(|h| h.eq_ignore_ascii_case(&n)) {
                    hits.push(n);
                }
            }
        }
    }
    if hits.is_empty() {
        return Err(Error::Msg(format!("no {role} mailbox on this account")));
    }
    if hits.len() == 1 {
        return Ok(hits.remove(0));
    }
    let mut best = hits[0].clone();
    let mut best_n = 0u32;
    for hit in hits {
        if let Ok(selected) = session.select(&hit) {
            if selected.exists >= best_n {
                best_n = selected.exists;
                best = hit;
            }
        }
    }
    Ok(best)
}

fn connect(account: &DiskAccount, password: &str) -> Result<ImapSession, Error> {
    if !account.imap_tls {
        return Err(Error::Msg("IMAP without TLS is not supported yet".into()));
    }
    let port: u16 = account
        .imap_port
        .parse()
        .map_err(|_| Error::Msg("invalid IMAP port".into()))?;
    let tls = TlsConnector::builder().build()?;
    let client = imap::connect((account.imap_host.as_str(), port), &account.imap_host, &tls)?;
    let session = client
        .login(&account.username, password)
        .map_err(|e| Error::Msg(format!("login failed: {}", e.0)))?;
    Ok(session)
}

impl State {
    fn new(config_path: String) -> Result<Self, Error> {
        let accounts = load_accounts(&config_path)?;
        Ok(Self {
            config_path,
            accounts,
            sessions: HashMap::new(),
        })
    }

    fn account(&self, id: &str) -> Result<&DiskAccount, Error> {
        self.accounts
            .iter()
            .find(|a| a.id == id)
            .ok_or_else(|| Error::Msg(format!("unknown account {id}")))
    }

    fn selected_accounts(&self, id: &str) -> Result<Vec<DiskAccount>, Error> {
        if id.is_empty() || id == "all" {
            if self.accounts.is_empty() {
                return Err(Error::Msg("no accounts".into()));
            }
            return Ok(self.accounts.clone());
        }
        Ok(vec![self.account(id)?.clone()])
    }

    fn session(&mut self, id: &str) -> Result<&mut ImapSession, Error> {
        if !self.sessions.contains_key(id) {
            let account = self.account(id)?.clone();
            let password = lookup_password(id)?;
            let session = connect(&account, &password)?;
            self.sessions.insert(
                id.to_string(),
                AccountSession {
                    account,
                    password,
                    session: Some(session),
                },
            );
        }
        let entry = self.sessions.get_mut(id).unwrap();
        if entry.session.is_none() {
            entry.session = Some(connect(&entry.account, &entry.password)?);
        }
        Ok(entry.session.as_mut().unwrap())
    }

    fn drop_session(&mut self, id: &str) {
        self.sessions.remove(id);
    }

    fn with_session<T>(
        &mut self,
        id: &str,
        f: impl FnOnce(&DiskAccount, &mut ImapSession) -> Result<T, Error>,
    ) -> Result<T, Error> {
        let account = self.account(id)?.clone();
        match {
            let session = self.session(id)?;
            f(&account, session)
        } {
            Ok(value) => Ok(value),
            Err(err) => {
                self.drop_session(id);
                Err(err)
            }
        }
    }
}

fn flags_unread(fetch: &Fetch) -> bool {
    match fetch.flags().iter().find(|f| matches!(f, Flag::Seen)) {
        Some(_) => false,
        None => true,
    }
}

fn envelope_when(fetch: &Fetch) -> String {
    fetch
        .envelope()
        .and_then(|e| e.date.as_ref())
        .map(|d| decode_bytes(d))
        .unwrap_or_default()
}

fn row_timestamp(fetch: &Fetch) -> i64 {
    if let Some(dt) = fetch.internal_date() {
        return dt.timestamp();
    }
    if let Some(env) = fetch.envelope() {
        if let Some(date) = env.date.as_ref() {
            let raw = String::from_utf8_lossy(date);
            if let Ok(dt) = chrono::DateTime::parse_from_rfc2822(raw.trim()) {
                return dt.timestamp();
            }
        }
    }
    0
}

fn envelope_subject(fetch: &Fetch) -> String {
    if let Some(bytes) = fetch.header() {
        if let Ok(parsed) = parse_mail(bytes) {
            if let Some(header) = parsed.headers.get_first_header("Subject") {
                let decoded = decode_bytes(header.get_value_raw());
                if !decoded.is_empty() {
                    return decoded;
                }
            }
        }
    }
    fetch
        .envelope()
        .and_then(|e| e.subject.as_ref())
        .map(|s| decode_bytes(s))
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "(no subject)".into())
}

fn header_map(fetch: &Fetch) -> HashMap<String, String> {
    let mut map = HashMap::new();
    if let Some(bytes) = fetch.header() {
        if let Ok(parsed) = parse_mail(bytes) {
            for key in ["Subject", "Message-ID", "References", "In-Reply-To"] {
                if let Some(value) = parsed.headers.get_first_value(key) {
                    map.insert(key.to_lowercase(), value);
                }
            }
        }
    }
    map
}

fn normalize_subject(subject: &str) -> String {
    let mut s = subject.trim().to_string();
    loop {
        let lower = s.to_lowercase();
        let stripped = if let Some(rest) = lower.strip_prefix("re:") {
            rest
        } else if let Some(rest) = lower.strip_prefix("fwd:") {
            rest
        } else if let Some(rest) = lower.strip_prefix("fw:") {
            rest
        } else {
            break;
        };
        let skip = s.len() - stripped.len();
        s = s[skip..].trim().to_string();
    }
    s.to_lowercase()
}

fn thread_key(headers: &HashMap<String, String>, subject: &str) -> String {
    if let Some(refs) = headers.get("references") {
        if let Some(first) = refs.split_whitespace().next() {
            return first.trim().to_string();
        }
    }
    if let Some(reply) = headers.get("in-reply-to") {
        let token = reply.split_whitespace().next().unwrap_or(reply).trim();
        if !token.is_empty() {
            return token.to_string();
        }
    }
    if let Some(id) = headers.get("message-id") {
        if !id.trim().is_empty() {
            return id.trim().to_string();
        }
    }
    format!("subj:{}", normalize_subject(subject))
}

#[derive(Clone)]
struct EnvelopeRow {
    account_id: String,
    mailbox: String,
    uid: u32,
    unread: bool,
    subject: String,
    when: String,
    when_ts: i64,
    from_name: String,
    from_email: String,
    account_email: String,
    to: Vec<(String, String)>,
    cc: Vec<(String, String)>,
    mine: bool,
    key: String,
    message_id: String,
    ids: Vec<String>,
}

fn fetch_to_row(account: &DiskAccount, mailbox: &str, fetch: &Fetch) -> Option<EnvelopeRow> {
    let uid = fetch.uid?;
    let subject = envelope_subject(fetch);
    let headers = header_map(fetch);
    let from = account.email.clone();
    let env = fetch.envelope();
    let people = env.map(|e| address_parts(&e.from)).unwrap_or_default();
    let to = env.map(|e| address_parts(&e.to)).unwrap_or_default();
    let cc = env.map(|e| address_parts(&e.cc)).unwrap_or_default();
    let (from_name, from_email) = people
        .first()
        .cloned()
        .unwrap_or_else(|| (String::new(), String::new()));
    let mine = !from_email.is_empty() && from_email.eq_ignore_ascii_case(&from);
    let message_id = headers
        .get("message-id")
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    let ids = header_ids(&headers);
    let key = thread_key(&headers, &subject);
    Some(EnvelopeRow {
        account_id: account.id.clone(),
        mailbox: mailbox.to_string(),
        uid,
        unread: flags_unread(fetch),
        subject,
        when: envelope_when(fetch),
        when_ts: row_timestamp(fetch),
        from_name,
        from_email,
        account_email: account.email.clone(),
        to,
        cc,
        mine,
        key,
        message_id,
        ids,
    })
}

fn looks_like_email(value: &str) -> bool {
    let value = value.trim();
    let mut parts = value.split('@');
    match (parts.next(), parts.next(), parts.next()) {
        (Some(local), Some(host), None) => {
            !local.is_empty() && host.contains('.') && !host.starts_with('.') && !host.ends_with('.')
        }
        _ => false,
    }
}

fn parse_addr_token(token: &str) -> Result<(String, String), Error> {
    let token = token.trim();
    if token.is_empty() {
        return Err(Error::Msg("empty address".into()));
    }
    if let Some(start) = token.rfind('<') {
        if let Some(end) = token.rfind('>') {
            if end > start {
                let email = token[start + 1..end].trim().to_string();
                let name = token[..start]
                    .trim()
                    .trim_matches('"')
                    .trim_matches('\'')
                    .to_string();
                if looks_like_email(&email) {
                    return Ok((name, email));
                }
            }
        }
    }
    if looks_like_email(token) {
        return Ok((String::new(), token.to_string()));
    }
    Err(Error::Msg(format!("invalid address: {token}")))
}

fn parse_recipients(list: &[String]) -> Result<Vec<(String, String)>, Error> {
    parse_recipient_list(list, true)
}

fn parse_recipient_list(list: &[String], strict: bool) -> Result<Vec<(String, String)>, Error> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();
    for raw in list {
        let mut cur = String::new();
        let mut depth = 0i32;
        for ch in raw.chars() {
            match ch {
                '<' => {
                    depth += 1;
                    cur.push(ch);
                }
                '>' => {
                    if depth > 0 {
                        depth -= 1;
                    }
                    cur.push(ch);
                }
                ',' | ';' if depth == 0 => {
                    let token = cur.trim().to_string();
                    cur.clear();
                    if !token.is_empty() {
                        push_recipient(&mut out, &mut seen, &token, strict)?;
                    }
                }
                _ => cur.push(ch),
            }
        }
        let token = cur.trim();
        if !token.is_empty() {
            push_recipient(&mut out, &mut seen, token, strict)?;
        }
    }
    if out.is_empty() && strict {
        return Err(Error::Msg("no recipients".into()));
    }
    Ok(out)
}

fn push_recipient(
    out: &mut Vec<(String, String)>,
    seen: &mut HashSet<String>,
    token: &str,
    strict: bool,
) -> Result<(), Error> {
    match parse_addr_token(token) {
        Ok((name, email)) => {
            let key = email.to_ascii_lowercase();
            if seen.insert(key) {
                out.push((name, email));
            }
            Ok(())
        }
        Err(err) if strict => Err(err),
        Err(_) => Ok(()),
    }
}

fn collect_contacts(accounts: &[DiskAccount], rows: &[EnvelopeRow]) -> Vec<Contact> {
    let mine: HashSet<String> = accounts
        .iter()
        .map(|a| a.email.to_ascii_lowercase())
        .collect();
    let mut sorted = rows.to_vec();
    sorted.sort_by(|a, b| b.when_ts.cmp(&a.when_ts));
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    let mut add = |name: &str, email: &str| {
        let email = email.trim();
        if email.is_empty() || !looks_like_email(email) {
            return;
        }
        let key = email.to_ascii_lowercase();
        if mine.contains(&key) || !seen.insert(key) {
            return;
        }
        let name = name.trim();
        let name = if name.is_empty() || name.eq_ignore_ascii_case(email) {
            email.to_string()
        } else {
            name.to_string()
        };
        out.push(Contact {
            name,
            email: email.to_string(),
        });
    };
    for row in &sorted {
        if row.mailbox == "sent" {
            for (name, email) in &row.to {
                add(name, email);
            }
            for (name, email) in &row.cc {
                add(name, email);
            }
        } else {
            add(&row.from_name, &row.from_email);
        }
    }
    out.truncate(400);
    out
}

fn header_ids(headers: &HashMap<String, String>) -> Vec<String> {
    let mut ids: Vec<String> = Vec::new();
    for key in ["message-id", "in-reply-to", "references"] {
        let Some(value) = headers.get(key) else { continue };
        for tok in value.split_whitespace() {
            let token = tok.trim();
            if token.is_empty() {
                continue;
            }
            if !ids.iter().any(|id| id.eq_ignore_ascii_case(token)) {
                ids.push(token.to_string());
            }
        }
    }
    ids
}

fn find_root(parent: &mut [usize], mut i: usize) -> usize {
    while parent[i] != i {
        let up = parent[i];
        parent[i] = parent[up];
        i = up;
    }
    i
}

fn union_root(parent: &mut [usize], a: usize, b: usize) {
    let ra = find_root(parent, a);
    let rb = find_root(parent, b);
    if ra != rb {
        parent[rb] = ra;
    }
}

fn group_rows(rows: Vec<EnvelopeRow>, viewed: &str) -> Vec<Conversation> {
    if rows.is_empty() {
        return Vec::new();
    }
    let mut parent: Vec<usize> = (0..rows.len()).collect();
    let mut id_owner: HashMap<String, usize> = HashMap::new();
    let mut subj_owner: HashMap<String, usize> = HashMap::new();
    for (i, row) in rows.iter().enumerate() {
        if row.ids.is_empty() {
            let subj = format!("{}:subj:{}", row.account_id, normalize_subject(&row.subject));
            if let Some(&j) = subj_owner.get(&subj) {
                union_root(&mut parent, i, j);
            } else {
                subj_owner.insert(subj, i);
            }
            continue;
        }
        for id in &row.ids {
            let key = format!("{}:{}", row.account_id, id.to_ascii_lowercase());
            if let Some(&j) = id_owner.get(&key) {
                union_root(&mut parent, i, j);
            } else {
                id_owner.insert(key, i);
            }
        }
    }
    let mut order: Vec<usize> = Vec::new();
    let mut groups: HashMap<usize, Vec<EnvelopeRow>> = HashMap::new();
    for (i, row) in rows.into_iter().enumerate() {
        let root = find_root(&mut parent, i);
        if !groups.contains_key(&root) {
            order.push(root);
        }
        groups.entry(root).or_default().push(row);
    }
    let mut conversations = Vec::new();
    for key in order {
        let mut items = groups.remove(&key).unwrap_or_default();
        if !items.iter().any(|item| item.mailbox == viewed) {
            continue;
        }
        items.sort_by(|a, b| {
            let av = (a.mailbox == viewed) as i32;
            let bv = (b.mailbox == viewed) as i32;
            bv.cmp(&av).then(a.when_ts.cmp(&b.when_ts))
        });
        let mut unique = Vec::new();
        let mut seen_ids = HashSet::new();
        for item in items {
            if !item.message_id.is_empty() && !seen_ids.insert(item.message_id.clone()) {
                continue;
            }
            unique.push(item);
        }
        unique.sort_by_key(|item| item.when_ts);
        let latest = unique.last().cloned();
        let Some(latest) = latest else { continue };
        let mut participants: Vec<Participant> = Vec::new();
        let mut uids = Vec::new();
        let mut locations = Vec::new();
        let mut unread = false;
        let mut push_person = |name: &str, email: &str, mine: bool| {
            let email = email.trim();
            let label = if mine {
                "You".to_string()
            } else if !name.trim().is_empty() {
                name.trim().to_string()
            } else {
                email.to_string()
            };
            if label.is_empty() {
                return;
            }
            let seen = participants.iter().any(|p| {
                if !email.is_empty() && !p.email.is_empty() {
                    p.email.eq_ignore_ascii_case(email)
                } else {
                    p.name == label
                }
            });
            if !seen {
                participants.push(Participant {
                    name: label,
                    email: email.to_string(),
                    mine,
                });
            }
        };
        for item in &unique {
            uids.push(item.uid);
            locations.push(MailUid {
                mailbox: item.mailbox.clone(),
                uid: item.uid,
            });
            if item.mailbox == viewed {
                unread = unread || item.unread;
            }
            push_person(&item.from_name, &item.from_email, item.mine);
            if viewed == "sent" || viewed == "drafts" {
                for (name, email) in item.to.iter().chain(item.cc.iter()) {
                    if !item.account_email.is_empty() && email.eq_ignore_ascii_case(&item.account_email) {
                        continue;
                    }
                    push_person(name, email, false);
                }
            }
        }
        let mut to = Vec::new();
        if let Some(item) = unique
            .iter()
            .rev()
            .find(|item| item.mailbox == viewed)
            .or_else(|| unique.last())
        {
            for (name, email) in item.to.iter().chain(item.cc.iter()) {
                let email = email.trim();
                if email.is_empty() {
                    continue;
                }
                if to.iter().any(|p: &Participant| p.email.eq_ignore_ascii_case(email)) {
                    continue;
                }
                let label = if !name.trim().is_empty() && !name.eq_ignore_ascii_case(email) {
                    name.trim().to_string()
                } else {
                    email.to_string()
                };
                to.push(Participant {
                    name: label,
                    email: email.to_string(),
                    mine: false,
                });
            }
        }
        let preview_name = participants
            .iter()
            .find(|p| !p.mine)
            .map(|p| p.name.clone())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| {
                if latest.mine {
                    "You".into()
                } else {
                    latest.from_name.clone()
                }
            });
        let thread_id = unique
            .iter()
            .filter(|item| !item.message_id.is_empty())
            .min_by_key(|item| item.when_ts)
            .map(|item| item.message_id.clone())
            .unwrap_or_else(|| format!("subj:{}", normalize_subject(&latest.subject)));
        conversations.push(Conversation {
            id: format!("{}:{}", latest.account_id, thread_id),
            account_id: latest.account_id,
            mailbox: viewed.to_string(),
            unread,
            subject: latest.subject,
            preview: preview_name,
            when: latest.when,
            when_ts: latest.when_ts,
            participants,
            to,
            uids,
            items: locations,
            messages: Vec::new(),
            latest_mine: latest.mine,
        });
    }
    conversations.sort_by(|a, b| b.when_ts.cmp(&a.when_ts));
    conversations
}

fn and_or_search(query: &str, fields: &[&str], charset: bool) -> String {
    let mut clauses: Vec<String> = Vec::new();
    for token in query.split_whitespace() {
        let needle = imap_quote(token);
        let mut clause = format!("{} {needle}", fields[0]);
        for field in fields.iter().skip(1) {
            clause = format!("OR {clause} {field} {needle}");
        }
        clauses.push(clause);
    }
    let body = clauses.join(" ");
    if charset {
        format!("CHARSET UTF-8 {body}")
    } else {
        body
    }
}

fn search_uids(
    session: &mut ImapSession,
    query: &str,
    body_fallback: bool,
) -> Result<HashSet<u32>, Error> {
    let charset = !query.is_ascii();
    let field_sets: [&[&str]; 3] = [
        &["SUBJECT", "FROM", "TO", "CC"],
        &["SUBJECT", "FROM", "TO"],
        &["SUBJECT", "FROM"],
    ];
    let mut tried = HashSet::new();
    let mut last_err = None;
    let mut any_ok = false;
    for fields in field_sets {
        for use_charset in [charset, false] {
            let search = and_or_search(query, fields, use_charset);
            if !tried.insert(search.clone()) {
                continue;
            }
            match session.uid_search(&search) {
                Ok(set) if !set.is_empty() => return Ok(set),
                Ok(_) => any_ok = true,
                Err(err) => last_err = Some(err),
            }
        }
    }
    if body_fallback {
        for use_charset in [charset, false] {
            let search = and_or_search(query, &["BODY"], use_charset);
            if !tried.insert(search.clone()) {
                continue;
            }
            match session.uid_search(&search) {
                Ok(set) => return Ok(set),
                Err(err) => last_err = Some(err),
            }
        }
    }
    if any_ok {
        return Ok(HashSet::new());
    }
    Err(last_err.map(Into::into).unwrap_or_else(|| Error::Msg("search failed".into())))
}

fn query_set(
    session: &mut ImapSession,
    exists: u32,
    limit: u32,
    query: &str,
    body_fallback: bool,
) -> Result<String, Error> {
    let q = query.trim();
    if q.is_empty() {
        if exists == 0 {
            return Ok(String::new());
        }
        let take = limit.max(1);
        let start = exists.saturating_sub(take).saturating_add(1).max(1);
        return Ok(format!("{start}:{exists}"));
    }
    let uids = search_uids(session, q, body_fallback)?;
    let mut list: Vec<u32> = uids.into_iter().collect();
    list.sort_unstable();
    if list.len() > limit as usize {
        list = list.split_off(list.len() - limit as usize);
    }
    if list.is_empty() {
        return Ok(String::new());
    }
    Ok(list
        .iter()
        .map(|u| u.to_string())
        .collect::<Vec<_>>()
        .join(","))
}

const FETCH_FIELDS: &str =
    "(UID FLAGS ENVELOPE INTERNALDATE BODY.PEEK[HEADER.FIELDS (SUBJECT MESSAGE-ID REFERENCES IN-REPLY-TO)])";

fn unseen_count(session: &mut ImapSession) -> Result<u32, Error> {
    match session.search("UNSEEN") {
        Ok(set) => Ok(set.len() as u32),
        Err(_) => match session.uid_search("UNSEEN") {
            Ok(set) => Ok(set.len() as u32),
            Err(_) => Ok(0),
        },
    }
}

fn list_mailbox(
    account: &DiskAccount,
    session: &mut ImapSession,
    mailbox_role: &str,
    limit: u32,
    query: &str,
    body_fallback: bool,
) -> Result<(u32, Vec<EnvelopeRow>), Error> {
    let mailbox = resolve_mailbox(session, mailbox_role)?;
    let selected = session.select(&mailbox)?;
    let unread = unseen_count(session)?;
    let set = query_set(session, selected.exists, limit, query, body_fallback)?;
    if set.is_empty() {
        return Ok((unread, Vec::new()));
    }
    let fetches = if query.trim().is_empty() {
        session.fetch(&set, FETCH_FIELDS)?
    } else {
        session.uid_fetch(&set, FETCH_FIELDS)?
    };
    let mut rows = Vec::new();
    for fetch in fetches.iter() {
        if let Some(row) = fetch_to_row(account, mailbox_role, fetch) {
            rows.push(row);
        }
    }
    Ok((unread, rows))
}

fn list_account(
    account: &DiskAccount,
    session: &mut ImapSession,
    mailbox_role: &str,
    limit: u32,
    query: &str,
) -> Result<(u32, Vec<EnvelopeRow>), Error> {
    let (unread, mut rows) = list_mailbox(account, session, mailbox_role, limit, query, true)?;
    let extra = match mailbox_role {
        "inbox" | "archive" | "trash" => Some("sent"),
        "sent" => Some("inbox"),
        _ => None,
    };
    if let Some(extra) = extra {
        if let Ok((_, extra_rows)) =
            list_mailbox(account, session, extra, limit.max(100), query, false)
        {
            rows.extend(extra_rows);
        }
    }
    Ok((unread, rows))
}

fn html_attr(tag: &str, name: &str) -> Option<String> {
    let lower = tag.to_ascii_lowercase();
    let key = format!("{name}=");
    let pos = lower.find(&key)?;
    let rest = tag[pos + key.len()..].trim_start();
    if let Some(stripped) = rest.strip_prefix('"') {
        return stripped.split('"').next().map(|s| s.to_string());
    }
    if let Some(stripped) = rest.strip_prefix('\'') {
        return stripped.split('\'').next().map(|s| s.to_string());
    }
    rest.split_whitespace().next().map(|s| s.to_string())
}

fn is_void_tag(name: &str) -> bool {
    matches!(
        name,
        "br" | "img" | "hr" | "meta" | "input" | "source" | "area" | "col" | "wbr" | "embed" | "link"
            | "base" | "param" | "track"
    )
}

fn tag_is_quote(name: &str, raw: &str) -> bool {
    if name == "blockquote" {
        return true;
    }
    let Some(class) = html_attr(raw, "class") else {
        return false;
    };
    let class = class.to_ascii_lowercase();
    class.contains("gmail_quote")
        || class.contains("yahoo_quoted")
        || class.contains("protonmail_quote")
        || class.contains("moz-cite-prefix")
}

fn push_quoted(out: &mut String, text: &str, depth: u32) {
    for ch in text.chars() {
        if depth > 0 && ch != '\n' && (out.is_empty() || out.ends_with('\n')) {
            for _ in 0..depth {
                out.push_str("> ");
            }
        }
        out.push(ch);
    }
}

fn html_to_text(html: &str) -> String {
    let mut out = String::new();
    let mut in_tag = false;
    let mut skip = false;
    let mut tag = String::new();
    let mut link_href: Option<String> = None;
    let mut link_text = String::new();
    let mut quote_depth = 0u32;
    let mut quote_stack: Vec<bool> = Vec::new();
    for ch in html.chars() {
        if ch == '<' {
            in_tag = true;
            tag.clear();
            continue;
        }
        if in_tag {
            if ch == '>' {
                let raw = tag.trim();
                let closing = raw.starts_with('/');
                let name = raw
                    .trim_start_matches('/')
                    .split_whitespace()
                    .next()
                    .unwrap_or("")
                    .to_ascii_lowercase();
                if name == "script" || name == "style" {
                    skip = !closing;
                }
                if name == "a" && !closing {
                    link_href = html_attr(raw, "href");
                    link_text.clear();
                }
                if name == "a" && closing {
                    if let Some(href) = link_href.take() {
                        let label = if link_text.trim().is_empty() {
                            href.clone()
                        } else {
                            link_text.trim().to_string()
                        };
                        push_quoted(&mut out, &format!("[{label}]({href})"), quote_depth);
                    }
                    link_text.clear();
                }
                if !is_void_tag(&name) {
                    if closing {
                        if quote_stack.pop().unwrap_or(false) && quote_depth > 0 {
                            quote_depth -= 1;
                        }
                    } else {
                        let quoted = tag_is_quote(&name, raw);
                        quote_stack.push(quoted);
                        if quoted {
                            quote_depth += 1;
                        }
                    }
                }
                if name == "br"
                    || name == "p"
                    || name == "div"
                    || name == "li"
                    || name == "blockquote"
                    || name.starts_with('h')
                {
                    push_quoted(&mut out, "\n", quote_depth);
                }
                in_tag = false;
            } else {
                tag.push(ch);
            }
            continue;
        }
        if skip {
            continue;
        }
        if link_href.is_some() {
            link_text.push(ch);
        } else {
            push_quoted(&mut out, &ch.to_string(), quote_depth);
        }
    }
    unescape(&out)
}

fn named_entity(name: &str) -> Option<&'static str> {
    Some(match name.to_ascii_lowercase().as_str() {
        "amp" => "&",
        "lt" => "<",
        "gt" => ">",
        "quot" => "\"",
        "apos" => "'",
        "nbsp" | "ensp" | "emsp" | "thinsp" => " ",
        "zwnj" | "zwj" | "lrm" | "rlm" | "shy" | "zwsp" => "",
        "ndash" => "–",
        "mdash" => "—",
        "hellip" => "…",
        "bull" => "•",
        "middot" => "·",
        "lsquo" | "sbquo" => "‘",
        "rsquo" => "’",
        "ldquo" | "bdquo" => "“",
        "rdquo" => "”",
        "laquo" => "«",
        "raquo" => "»",
        "copy" => "©",
        "reg" => "®",
        "trade" => "™",
        "deg" => "°",
        "times" => "×",
        "divide" => "÷",
        "plusmn" => "±",
        "euro" => "€",
        "pound" => "£",
        "yen" => "¥",
        "cent" => "¢",
        "iexcl" => "¡",
        "iquest" => "¿",
        _ => return None,
    })
}

fn char_entity(ch: char) -> String {
    match ch {
        '\u{00A0}' | '\u{2002}' | '\u{2003}' | '\u{2009}' | '\u{202F}' => " ".into(),
        '\u{00AD}' | '\u{200B}' | '\u{200C}' | '\u{200D}' | '\u{200E}' | '\u{200F}' | '\u{FEFF}' => {
            String::new()
        }
        other => other.to_string(),
    }
}

fn parse_entity(s: &str) -> Option<(String, usize)> {
    let rest = s.strip_prefix('&')?;
    if let Some(digits) = rest.strip_prefix('#') {
        let hex = digits.starts_with('x') || digits.starts_with('X');
        let digits = if hex { &digits[1..] } else { digits };
        let end = digits.find(';')?;
        if end == 0 || end > 8 {
            return None;
        }
        let num = if hex {
            u32::from_str_radix(&digits[..end], 16).ok()?
        } else {
            digits[..end].parse().ok()?
        };
        let ch = char::from_u32(num)?;
        let consumed = 2 + usize::from(hex) + end + 1;
        return Some((char_entity(ch), consumed));
    }
    let end = rest.find(';')?;
    if end == 0 || end > 32 {
        return None;
    }
    let value = named_entity(&rest[..end])?;
    Some((value.to_string(), end + 2))
}

fn unescape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < text.len() {
        if text.as_bytes()[i] == b'&' {
            if let Some((value, n)) = parse_entity(&text[i..]) {
                out.push_str(&value);
                i += n;
                continue;
            }
        }
        let ch = text[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

fn is_quote_line(line: &str) -> bool {
    line.trim_start().starts_with('>')
}

fn is_attribution(line: &str) -> bool {
    let t = line.trim();
    if t.len() < 8 {
        return false;
    }
    let lower = t.to_ascii_lowercase();
    if lower.starts_with("on ")
        && (lower.contains(" wrote") || lower.contains(" writes") || lower.contains(" written"))
    {
        return true;
    }
    if lower.contains(" wrote:") || lower.contains(" writes:") {
        return true;
    }
    if (lower.starts_with("le ") || lower.starts_with("el "))
        && (lower.contains("écrit") || lower.contains("escribi") || lower.contains("escrito"))
    {
        return true;
    }
    if lower.starts_with("am ") && lower.contains("schrieb") {
        return true;
    }
    if lower.contains("original message") {
        return true;
    }
    if lower.starts_with("begin forwarded message") {
        return true;
    }
    let marks = t.chars().filter(|c| *c == '-' || *c == '_').count();
    marks >= 8 && t.chars().all(|c| c == '-' || c == '_' || c.is_whitespace())
}

fn is_outlook_quote_start(lines: &[&str], i: usize) -> bool {
    let lower = lines[i].trim().to_ascii_lowercase();
    if !lower.starts_with("from:") {
        return false;
    }
    let end = (i + 8).min(lines.len());
    let mut sent = false;
    let mut to_or_subj = false;
    for line in &lines[i..end] {
        let l = line.trim().to_ascii_lowercase();
        if l.starts_with("sent:") || l.starts_with("date:") {
            sent = true;
        }
        if l.starts_with("to:") || l.starts_with("subject:") {
            to_or_subj = true;
        }
    }
    sent && to_or_subj
}

fn looks_like_quoted_header(line: &str) -> bool {
    let lower = strip_quote_prefixes(line).trim().to_ascii_lowercase();
    lower.starts_with("from:")
        || lower.starts_with("sent:")
        || lower.starts_with("date:")
        || lower.starts_with("to:")
        || lower.starts_with("subject:")
        || lower.starts_with("cc:")
}

fn quote_has_history_signal(lines: &[&str]) -> bool {
    for line in lines {
        let stripped = strip_quote_prefixes(line);
        if is_attribution(line) || is_attribution(&stripped) || looks_like_quoted_header(line) {
            return true;
        }
        let t = line.trim_start();
        if t.starts_with(">>") || t.starts_with("> >") {
            return true;
        }
    }
    false
}

fn rest_is_trailing_quote(lines: &[&str], start: usize) -> bool {
    if start == 0 {
        return false;
    }
    let rest: Vec<&str> = lines[start..]
        .iter()
        .copied()
        .filter(|l| !l.trim().is_empty())
        .collect();
    if rest.is_empty() {
        return false;
    }
    if is_attribution(rest[0]) || is_outlook_quote_start(lines, start) {
        return true;
    }
    if !rest.iter().all(|l| is_quote_line(l) || is_attribution(l)) {
        return false;
    }
    if quote_has_history_signal(&rest) {
        return true;
    }
    let trailing_len: usize = rest.iter().map(|l| l.len()).sum();
    let original_len: usize = lines[..start].iter().map(|l| l.len()).sum();
    trailing_len > 280 && trailing_len > original_len
}

fn trailing_quote_start(lines: &[&str]) -> Option<usize> {
    for i in 0..lines.len() {
        if (is_attribution(lines[i]) || is_quote_line(lines[i]) || is_outlook_quote_start(lines, i))
            && rest_is_trailing_quote(lines, i)
        {
            return Some(i);
        }
    }
    None
}

fn strip_quote_prefixes(text: &str) -> String {
    text.lines()
        .map(|line| {
            let mut t = line.trim_start();
            while let Some(rest) = t.strip_prefix('>') {
                t = rest.trim_start();
            }
            t.to_string()
        })
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_string()
}

fn push_paragraph(chunk: &str, blocks: &mut Vec<Block>) {
    let line = chunk.trim();
    if line.is_empty() {
        return;
    }
    if line.starts_with("# ") {
        blocks.push(Block {
            kind: "heading".into(),
            text: line.trim_start_matches('#').trim().to_string(),
        });
        return;
    }
    if line.lines().all(|l| {
        let t = l.trim_start();
        t.starts_with("- ") || t.starts_with("* ")
    }) {
        let body = line
            .lines()
            .map(|l| {
                l.trim_start()
                    .trim_start_matches(['-', '*'])
                    .trim()
                    .to_string()
            })
            .collect::<Vec<_>>()
            .join("\n");
        blocks.push(Block {
            kind: "list".into(),
            text: body,
        });
        return;
    }
    blocks.push(Block {
        kind: "p".into(),
        text: line.to_string(),
    });
}

fn push_chunk(chunk: &str, blocks: &mut Vec<Block>) {
    let lines: Vec<&str> = chunk.lines().collect();
    if lines.is_empty() {
        return;
    }
    let mut i = 0;
    while i < lines.len() {
        let quoted = is_quote_line(lines[i]);
        let mut j = i + 1;
        while j < lines.len() && is_quote_line(lines[j]) == quoted {
            j += 1;
        }
        let part = lines[i..j].join("\n");
        if quoted {
            let body = strip_quote_prefixes(&part);
            if !body.is_empty() {
                blocks.push(Block {
                    kind: "quote".into(),
                    text: body,
                });
            }
        } else {
            push_paragraph(&part, blocks);
        }
        i = j;
    }
}

fn text_to_blocks(text: &str) -> Vec<Block> {
    let cleaned = text.replace('\r', "");
    let lines: Vec<&str> = cleaned.split('\n').collect();
    let (original, trailing) = if let Some(idx) = trailing_quote_start(&lines) {
        let original = lines[..idx].join("\n");
        let quoted = lines[idx..].join("\n");
        (original, Some(quoted))
    } else {
        (cleaned.clone(), None)
    };

    let mut blocks = Vec::new();
    for chunk in original.split("\n\n") {
        push_chunk(chunk, &mut blocks);
    }
    if let Some(quoted) = trailing {
        let body = strip_quote_prefixes(&quoted);
        if !body.is_empty() {
            blocks.push(Block {
                kind: "history".into(),
                text: body,
            });
        }
    }
    if blocks.is_empty() {
        blocks.push(Block {
            kind: "p".into(),
            text: cleaned.trim().to_string(),
        });
    }
    blocks
}

fn part_is_file(part: &ParsedMail<'_>) -> bool {
    let mime = part.ctype.mimetype.to_ascii_lowercase();
    if mime.starts_with("multipart/") {
        return false;
    }
    let disp = part.get_content_disposition();
    if disp.disposition == DispositionType::Attachment {
        return true;
    }
    if disp
        .params
        .keys()
        .any(|k| k == "filename" || k.starts_with("filename"))
    {
        return true;
    }
    if part.ctype.params.contains_key("name") && !mime.starts_with("text/plain") && !mime.starts_with("text/html")
    {
        return true;
    }
    !mime.starts_with("text/plain") && !mime.starts_with("text/html")
}

fn leaf_parts<'a>(part: &'a ParsedMail<'a>) -> Vec<&'a ParsedMail<'a>> {
    let mut out = Vec::new();
    fn walk<'a>(part: &'a ParsedMail<'a>, out: &mut Vec<&'a ParsedMail<'a>>) {
        if part.ctype.mimetype.to_ascii_lowercase().starts_with("multipart/") {
            for sub in &part.subparts {
                walk(sub, out);
            }
            return;
        }
        out.push(part);
    }
    walk(part, &mut out);
    out
}

fn safe_filename(name: &str) -> String {
    let base = name
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(name)
        .trim()
        .trim_matches('.');
    let cleaned: String = base
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | ' ') {
                c
            } else {
                '_'
            }
        })
        .collect();
    let cleaned = cleaned.trim().trim_matches('.').to_string();
    if cleaned.is_empty() {
        "attachment".into()
    } else {
        cleaned.chars().take(80).collect()
    }
}

fn mime_ext(mime: &str) -> &'static str {
    match mime.to_ascii_lowercase().as_str() {
        "application/pdf" => ".pdf",
        "image/png" => ".png",
        "image/jpeg" | "image/jpg" => ".jpg",
        "image/gif" => ".gif",
        "image/webp" => ".webp",
        "text/plain" => ".txt",
        "text/csv" => ".csv",
        "text/calendar" => ".ics",
        "application/zip" => ".zip",
        "application/json" => ".json",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => ".docx",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => ".xlsx",
        "application/msword" => ".doc",
        "message/rfc822" => ".eml",
        _ => "",
    }
}

fn part_filename(part: &ParsedMail<'_>, index: u32) -> String {
    let disp = part.get_content_disposition();
    if let Some(name) = disp.params.get("filename") {
        if !name.trim().is_empty() {
            return safe_filename(name);
        }
    }
    if let Some(name) = part.ctype.params.get("name") {
        if !name.trim().is_empty() {
            return safe_filename(name);
        }
    }
    format!("part-{index}{}", mime_ext(&part.ctype.mimetype))
}

fn collect_attachments(parsed: &ParsedMail<'_>) -> Vec<MailAttachment> {
    let mut out = Vec::new();
    for (index, part) in leaf_parts(parsed).into_iter().enumerate() {
        if !part_is_file(part) {
            continue;
        }
        let size = part.get_body_raw().map(|b| b.len() as u32).unwrap_or(0);
        out.push(MailAttachment {
            index: index as u32,
            name: part_filename(part, index as u32),
            mime: part.ctype.mimetype.to_ascii_lowercase(),
            size,
        });
    }
    out
}

fn extract_part(parsed: &ParsedMail<'_>, index: u32) -> Result<(String, String, Vec<u8>), Error> {
    let leaves = leaf_parts(parsed);
    let part = leaves
        .get(index as usize)
        .copied()
        .ok_or_else(|| Error::Msg("no such attachment".into()))?;
    if !part_is_file(part) {
        return Err(Error::Msg("not an attachment".into()));
    }
    let bytes = part.get_body_raw()?;
    Ok((
        part_filename(part, index),
        part.ctype.mimetype.to_ascii_lowercase(),
        bytes,
    ))
}

fn part_text(part: &ParsedMail<'_>) -> Result<(String, bool), Error> {
    if part_is_file(part) {
        return Ok((String::new(), false));
    }
    let ctype = part.ctype.mimetype.to_ascii_lowercase();
    if ctype.starts_with("text/plain") {
        return Ok((part.get_body()?, false));
    }
    if ctype.starts_with("text/html") {
        return Ok((part.get_body()?, true));
    }
    for sub in &part.subparts {
        let (text, html) = part_text(sub)?;
        if !text.trim().is_empty() {
            return Ok((text, html));
        }
    }
    Ok((String::new(), false))
}

fn parse_message(account: &DiskAccount, mailbox: &str, uid: u32, raw: &[u8]) -> Result<Message, Error> {
    let parsed = parse_mail(raw)?;
    let from_header = parsed
        .headers
        .get_first_value("From")
        .unwrap_or_default();
    let (from_name, from_email) = parse_from(&from_header);
    let when = parsed
        .headers
        .get_first_value("Date")
        .unwrap_or_default();
    let (body, is_html) = part_text(&parsed)?;
    let text = if is_html { html_to_text(&body) } else { body };
    let mine = !from_email.is_empty() && from_email.eq_ignore_ascii_case(&account.email);
    let message_id = parsed
        .headers
        .get_first_value("Message-ID")
        .unwrap_or_default();
    let in_reply_to = parsed
        .headers
        .get_first_value("In-Reply-To")
        .unwrap_or_default();
    let references = parsed
        .headers
        .get_first_value("References")
        .unwrap_or_default();
    let to = parse_address_list(
        &parsed.headers.get_first_value("To").unwrap_or_default(),
        &account.email,
    );
    let cc = parse_address_list(
        &parsed.headers.get_first_value("Cc").unwrap_or_default(),
        &account.email,
    );
    let bcc = parse_address_list(
        &parsed.headers.get_first_value("Bcc").unwrap_or_default(),
        &account.email,
    );
    Ok(Message {
        id: format!("{mailbox}:{uid}"),
        uid,
        mailbox: mailbox.to_string(),
        from: if mine {
            "You".into()
        } else if from_name.is_empty() {
            from_email.clone()
        } else {
            from_name
        },
        from_email,
        mine,
        when,
        message_id,
        in_reply_to,
        references,
        to,
        cc,
        bcc,
        text: text.clone(),
        blocks: text_to_blocks(&text),
        attachments: collect_attachments(&parsed),
    })
}

fn push_participant(out: &mut Vec<Participant>, name: String, email: String, me: &str) {
    let email = email.trim().to_string();
    if email.is_empty() {
        return;
    }
    let name = name.trim().to_string();
    let name = if name.is_empty() { email.clone() } else { name };
    if out
        .iter()
        .any(|p| p.email.eq_ignore_ascii_case(&email))
    {
        return;
    }
    let mine = !me.is_empty() && email.eq_ignore_ascii_case(me);
    out.push(Participant {
        name,
        email,
        mine,
    });
}

fn parse_address_list(raw: &str, me: &str) -> Vec<Participant> {
    let mut out = Vec::new();
    if let Ok(list) = addrparse(raw) {
        for addr in list.iter() {
            match addr {
                MailAddr::Single(info) => {
                    push_participant(
                        &mut out,
                        info.display_name.clone().unwrap_or_default(),
                        info.addr.clone(),
                        me,
                    );
                }
                MailAddr::Group(group) => {
                    for info in &group.addrs {
                        push_participant(
                            &mut out,
                            info.display_name.clone().unwrap_or_default(),
                            info.addr.clone(),
                            me,
                        );
                    }
                }
            }
        }
    }
    if out.is_empty() {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            let (name, email) = parse_from(trimmed);
            push_participant(&mut out, name, email, me);
        }
    }
    out
}

fn parse_from(header: &str) -> (String, String) {
    if let Some(start) = header.rfind('<') {
        if let Some(end) = header.rfind('>') {
            if end > start {
                let email = header[start + 1..end].trim().to_string();
                let name = header[..start].trim().trim_matches('"').to_string();
                return (if name.is_empty() { email.clone() } else { name }, email);
            }
        }
    }
    let email = header.trim().to_string();
    (email.clone(), email)
}

fn handle(state: &mut State, req: Request) -> Vec<serde_json::Value> {
    match req.cmd.as_str() {
        "ping" => vec![json!({ "id": req.id, "ok": true, "accounts": state.accounts.len() })],
        "list" | "search" => list_responses(state, &req),
        "fetch" => vec![match fetch_cmd(state, &req) {
            Ok(value) => value,
            Err(err) => json!({ "id": req.id, "ok": false, "error": err.to_string() }),
        }],
        "seen" => vec![match seen_cmd(state, &req) {
            Ok(value) => value,
            Err(err) => json!({ "id": req.id, "ok": false, "error": err.to_string() }),
        }],
        "move" => vec![match move_cmd(state, &req) {
            Ok(value) => value,
            Err(err) => json!({ "id": req.id, "ok": false, "error": err.to_string() }),
        }],
        "delete" => vec![match delete_cmd(state, &req) {
            Ok(value) => value,
            Err(err) => json!({ "id": req.id, "ok": false, "error": err.to_string() }),
        }],
        "send" => vec![match send_cmd(state, &req) {
            Ok(value) => value,
            Err(err) => json!({ "id": req.id, "ok": false, "error": err.to_string() }),
        }],
        "draft" => vec![match draft_cmd(state, &req) {
            Ok(value) => value,
            Err(err) => json!({ "id": req.id, "ok": false, "error": err.to_string() }),
        }],
        "status" => vec![match status_cmd(state, &req) {
            Ok(value) => value,
            Err(err) => json!({ "id": req.id, "ok": false, "error": err.to_string() }),
        }],
        "attachment" => vec![match attachment_cmd(state, &req) {
            Ok(value) => value,
            Err(err) => json!({ "id": req.id, "ok": false, "error": err.to_string() }),
        }],
        other => vec![json!({ "id": req.id, "ok": false, "error": format!("unknown cmd {other}") })],
    }
}

fn list_responses(state: &mut State, req: &Request) -> Vec<serde_json::Value> {
    let mailbox = if req.mailbox.is_empty() {
        "inbox"
    } else {
        req.mailbox.as_str()
    };
    let mut out = Vec::new();
    if req.use_cache && req.query.trim().is_empty() {
        if let Ok(accounts) = state.selected_accounts(&req.account) {
            if let Some((unread, conversations, contacts)) = load_list_cache(&accounts, mailbox) {
                out.push(json!({
                    "id": req.id,
                    "ok": true,
                    "cached": true,
                    "unread": unread,
                    "conversations": conversations,
                    "contacts": contacts
                }));
            }
        }
    }
    match list_cmd(state, req) {
        Ok(value) => out.push(value),
        Err(err) => {
            if out.is_empty() {
                out.push(json!({ "id": req.id, "ok": false, "error": err.to_string() }));
            }
        }
    }
    out
}

fn list_cmd(state: &mut State, req: &Request) -> Result<serde_json::Value, Error> {
    let accounts = state.selected_accounts(&req.account)?;
    let mailbox = if req.mailbox.is_empty() {
        "inbox"
    } else {
        req.mailbox.as_str()
    };
    let mut unread = 0u32;
    let mut rows = Vec::new();
    let ids: Vec<String> = accounts.iter().map(|a| a.id.clone()).collect();
    for id in ids {
        let query = req.query.clone();
        let limit = req.limit;
        let (count, part) = state.with_session(&id, |account, session| {
            list_account(account, session, mailbox, limit, &query)
        })?;
        unread += count;
        rows.extend(part);
    }
    let contacts = collect_contacts(&accounts, &rows);
    let mut conversations = group_rows(rows, mailbox);
    if conversations.len() > req.limit as usize {
        conversations.truncate(req.limit as usize);
    }
    if req.query.trim().is_empty() {
        save_list_cache(&conversations, &contacts, unread, mailbox);
    }
    Ok(json!({
        "id": req.id,
        "ok": true,
        "cached": false,
        "unread": unread,
        "conversations": conversations,
        "contacts": contacts
    }))
}

fn fetch_locations(req: &Request) -> Vec<MailUid> {
    if !req.items.is_empty() {
        return req.items.clone();
    }
    let mailbox = if req.mailbox.is_empty() {
        "inbox".into()
    } else {
        req.mailbox.clone()
    };
    let mut uids = req.uids.clone();
    if uids.is_empty() && req.uid > 0 {
        uids.push(req.uid);
    }
    uids.into_iter()
        .map(|uid| MailUid {
            mailbox: mailbox.clone(),
            uid,
        })
        .collect()
}

fn message_timestamp(when: &str) -> i64 {
    chrono::DateTime::parse_from_rfc2822(when.trim())
        .map(|dt| dt.timestamp())
        .unwrap_or(0)
}

fn fetch_cmd(state: &mut State, req: &Request) -> Result<serde_json::Value, Error> {
    let account_id = req.account.clone();
    let locations = fetch_locations(req);
    if locations.is_empty() {
        return Err(Error::Msg("no uids".into()));
    }
    let mut grouped: HashMap<String, Vec<u32>> = HashMap::new();
    for item in locations {
        let role = if item.mailbox.is_empty() {
            "inbox".into()
        } else {
            item.mailbox
        };
        grouped.entry(role).or_default().push(item.uid);
    }
    let viewed = if req.mailbox.is_empty() {
        "inbox".to_string()
    } else {
        req.mailbox.clone()
    };
    let messages = state.with_session(&account_id, |account, session| {
        let mut out = Vec::new();
        let mut seen_sets: Vec<(String, Vec<u32>)> = Vec::new();
        for (role, mut uids) in grouped {
            uids.sort_unstable();
            uids.dedup();
            let Ok(mailbox) = resolve_mailbox(session, &role) else { continue };
            if session.select(&mailbox).is_err() {
                continue;
            }
            let uid_set = uids
                .iter()
                .map(|u| u.to_string())
                .collect::<Vec<_>>()
                .join(",");
            let fetches = match session.uid_fetch(&uid_set, "BODY.PEEK[]") {
                Ok(f) => f,
                Err(_) => match session.uid_fetch(&uid_set, "RFC822") {
                    Ok(f) => f,
                    Err(_) => continue,
                },
            };
            for fetch in fetches.iter() {
                let uid = fetch.uid.unwrap_or(0);
                if let Some(body) = fetch.body() {
                    out.push(parse_message(account, &role, uid, body)?);
                }
            }
            if role == viewed {
                seen_sets.push((mailbox, uids));
            }
        }
        for (mailbox, uids) in seen_sets {
            let _ = mark_seen(session, &mailbox, &uids, true);
        }
        if out.is_empty() {
            return Err(Error::Msg("couldn't fetch messages".into()));
        }
        out.sort_by_key(|msg| message_timestamp(&msg.when));
        Ok(out)
    })?;
    Ok(json!({
        "id": req.id,
        "ok": true,
        "messages": messages
    }))
}

fn download_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("XDG_DOWNLOAD_DIR") {
        if !dir.trim().is_empty() {
            return PathBuf::from(dir);
        }
    }
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(format!("{home}/Downloads"))
}

fn open_cache_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(format!("{home}/.cache/omarchy/mail/open"))
}

fn unique_path(dir: &Path, name: &str) -> PathBuf {
    let name = safe_filename(name);
    let path = dir.join(&name);
    if !path.exists() {
        return path;
    }
    let stem = Path::new(&name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("attachment");
    let ext = Path::new(&name)
        .extension()
        .and_then(|s| s.to_str())
        .map(|s| format!(".{s}"))
        .unwrap_or_default();
    for n in 1..1000 {
        let candidate = dir.join(format!("{stem}-{n}{ext}"));
        if !candidate.exists() {
            return candidate;
        }
    }
    dir.join(format!("{stem}-dup{ext}"))
}

fn write_bytes(path: &Path, bytes: &[u8]) -> Result<(), Error> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    fs::write(path, bytes)?;
    Ok(())
}

fn open_path(path: &Path) -> Result<(), Error> {
    Command::new("xdg-open")
        .arg(path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| Error::Msg(format!("xdg-open: {e}")))?;
    Ok(())
}

fn mime_from_path(path: &Path) -> ContentType {
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    let raw = match ext.as_str() {
        "pdf" => "application/pdf",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "txt" => "text/plain",
        "csv" => "text/csv",
        "html" | "htm" => "text/html",
        "ics" => "text/calendar",
        "zip" => "application/zip",
        "json" => "application/json",
        "doc" => "application/msword",
        "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls" => "application/vnd.ms-excel",
        "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt" => "application/vnd.ms-powerpoint",
        "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "eml" => "message/rfc822",
        _ => "application/octet-stream",
    };
    ContentType::parse(raw).unwrap_or(ContentType::TEXT_PLAIN)
}

fn attachment_cmd(state: &mut State, req: &Request) -> Result<serde_json::Value, Error> {
    let account_id = request_account_id(state, req)?;
    let role = request_mailbox_role(req);
    let uid = if req.uid > 0 {
        req.uid
    } else {
        req.uids.first().copied().unwrap_or(0)
    };
    if uid == 0 {
        return Err(Error::Msg("no uid".into()));
    }
    let action = req.action.trim().to_ascii_lowercase();
    let (name, _mime, bytes) = state.with_session(&account_id, |_, session| {
        let mailbox = resolve_mailbox(session, &role)?;
        session.select(&mailbox)?;
        let fetches = match session.uid_fetch(&uid.to_string(), "BODY.PEEK[]") {
            Ok(f) => f,
            Err(_) => session.uid_fetch(&uid.to_string(), "RFC822")?,
        };
        let raw = fetches
            .iter()
            .find_map(|f| f.body().map(|b| b.to_vec()))
            .ok_or_else(|| Error::Msg("couldn't fetch message".into()))?;
        let parsed = parse_mail(&raw)?;
        extract_part(&parsed, req.index)
    })?;
    let dest = if action == "save" {
        unique_path(&download_dir(), &name)
    } else {
        unique_path(&open_cache_dir(), &name)
    };
    write_bytes(&dest, &bytes)?;
    if action != "save" && action != "extract" {
        open_path(&dest)?;
    }
    Ok(json!({
        "id": req.id,
        "ok": true,
        "path": dest.to_string_lossy(),
        "name": name,
        "saved": action == "save",
        "action": action
    }))
}

fn uids_still_present(session: &mut ImapSession, uids: &[u32]) -> Result<Vec<u32>, Error> {
    if uids.is_empty() {
        return Ok(Vec::new());
    }
    let query = format!(
        "UID {}",
        uids.iter()
            .map(|u| u.to_string())
            .collect::<Vec<_>>()
            .join(",")
    );
    let found = session.uid_search(&query)?;
    Ok(uids.iter().copied().filter(|uid| found.contains(uid)).collect())
}

fn move_uids(session: &mut ImapSession, from: &str, to: &str, uids: &[u32]) -> Result<(), Error> {
    session.select(from)?;
    let mut remaining = uids_still_present(session, uids)?;
    if remaining.is_empty() {
        return Ok(());
    }
    let uid_set = remaining
        .iter()
        .map(|u| u.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let _ = session.uid_mv(&uid_set, to);
    remaining = uids_still_present(session, &remaining)?;
    if !remaining.is_empty() {
        let uid_set = remaining
            .iter()
            .map(|u| u.to_string())
            .collect::<Vec<_>>()
            .join(",");
        session.uid_copy(&uid_set, to)?;
        let _ = session.uid_store(&uid_set, "+FLAGS (\\Deleted)");
        let _ = session.uid_expunge(&uid_set);
        let _ = session.expunge();
        remaining = uids_still_present(session, &remaining)?;
    }
    if !remaining.is_empty() {
        return Err(Error::Msg("couldn't move messages".into()));
    }
    Ok(())
}

fn request_account_id(state: &State, req: &Request) -> Result<String, Error> {
    if req.account.is_empty() || req.account == "all" {
        state
            .accounts
            .first()
            .map(|a| a.id.clone())
            .ok_or_else(|| Error::Msg("no accounts".into()))
    } else {
        Ok(req.account.clone())
    }
}

fn request_mailbox_role(req: &Request) -> String {
    if req.mailbox.is_empty() {
        "inbox".into()
    } else {
        req.mailbox.clone()
    }
}

fn request_uids(req: &Request, from_role: &str) -> Vec<u32> {
    let mut uids = req.uids.clone();
    if uids.is_empty() && req.uid > 0 {
        uids.push(req.uid);
    }
    if uids.is_empty() {
        for item in &req.items {
            let role = if item.mailbox.is_empty() {
                from_role
            } else {
                item.mailbox.as_str()
            };
            if role == from_role {
                uids.push(item.uid);
            }
        }
    }
    uids.sort_unstable();
    uids.dedup();
    uids
}

fn move_cmd(state: &mut State, req: &Request) -> Result<serde_json::Value, Error> {
    let account_id = request_account_id(state, req)?;
    let from_role = request_mailbox_role(req);
    let to_role = if req.to.is_empty() {
        return Err(Error::Msg("missing destination".into()));
    } else {
        req.to.clone()
    };
    let uids = request_uids(req, &from_role);
    if uids.is_empty() {
        return Err(Error::Msg("no uids".into()));
    }
    state.with_session(&account_id, |_, session| {
        let from = resolve_mailbox(session, &from_role)?;
        let to = resolve_mailbox(session, &to_role)?;
        move_uids(session, &from, &to, &uids)
    })?;
    Ok(json!({ "id": req.id, "ok": true }))
}

fn delete_cmd(state: &mut State, req: &Request) -> Result<serde_json::Value, Error> {
    let account_id = request_account_id(state, req)?;
    let from_role = request_mailbox_role(req);
    let uids = request_uids(req, &from_role);
    if uids.is_empty() {
        return Err(Error::Msg("no uids".into()));
    }
    state.with_session(&account_id, |_, session| {
        let mailbox = resolve_mailbox(session, &from_role)?;
        delete_uids(session, &mailbox, &uids)?;
        session.select(&mailbox)?;
        let leftover = uids_still_present(session, &uids)?;
        if !leftover.is_empty() {
            return Err(Error::Msg("couldn't delete messages".into()));
        }
        Ok(())
    })?;
    Ok(json!({ "id": req.id, "ok": true }))
}

fn mailbox_from(name: &str, email: &str) -> Result<Mailbox, Error> {
    let addr: lettre::Address = email
        .parse()
        .map_err(|e| Error::Msg(format!("invalid address {email}: {e}")))?;
    let name = name.trim();
    if name.is_empty() || name.eq_ignore_ascii_case(email) {
        Ok(Mailbox::new(None, addr))
    } else {
        Ok(Mailbox::new(Some(name.to_string()), addr))
    }
}

fn new_message_id(email: &str) -> String {
    let domain = email.split('@').nth(1).unwrap_or("localhost");
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("<{nanos}.omarchy-mail@{domain}>")
}

fn ensure_msg_id(value: &str) -> String {
    let value = value.trim();
    if value.is_empty() {
        String::new()
    } else if value.starts_with('<') {
        value.to_string()
    } else {
        format!("<{value}>")
    }
}

fn smtp_transport(account: &DiskAccount, password: &str) -> Result<SmtpTransport, Error> {
    if !account.smtp_tls {
        return Err(Error::Msg("SMTP without TLS is not supported yet".into()));
    }
    let port: u16 = account
        .smtp_port
        .parse()
        .map_err(|_| Error::Msg("invalid SMTP port".into()))?;
    let creds = Credentials::new(account.username.clone(), password.to_string());
    let builder = if port == 587 {
        SmtpTransport::starttls_relay(&account.smtp_host)
            .map_err(|e| Error::Msg(e.to_string()))?
    } else {
        SmtpTransport::relay(&account.smtp_host)
            .map_err(|e| Error::Msg(e.to_string()))?
    };
    Ok(builder.port(port).credentials(creds).build())
}

fn build_outgoing(
    account: &DiskAccount,
    req: &Request,
    to: &[(String, String)],
    cc: &[(String, String)],
    bcc: &[(String, String)],
    allow_empty: bool,
    keep_bcc: bool,
) -> Result<SmtpMessage, Error> {
    let from_name = if account.from_name.trim().is_empty() {
        account.name.as_str()
    } else {
        account.from_name.trim()
    };
    let from = mailbox_from(from_name, &account.email)?;
    let mut builder = SmtpMessage::builder()
        .from(from)
        .subject(req.subject.trim())
        .message_id(Some(new_message_id(&account.email)))
        .user_agent("Omarchy Mail".into())
        .date_now();
    if keep_bcc {
        builder = builder.keep_bcc();
    }
    if to.is_empty() && cc.is_empty() && bcc.is_empty() {
        if !allow_empty {
            return Err(Error::Msg("no recipients".into()));
        }
        let addr: lettre::Address = account
            .email
            .parse()
            .map_err(|e| Error::Msg(format!("invalid from address: {e}")))?;
        let envelope = Envelope::new(Some(addr.clone()), vec![addr])
            .map_err(|e| Error::Msg(e.to_string()))?;
        builder = builder.envelope(envelope);
    } else {
        for (name, email) in to {
            builder = builder.to(mailbox_from(name, email)?);
        }
        for (name, email) in cc {
            builder = builder.cc(mailbox_from(name, email)?);
        }
        for (name, email) in bcc {
            builder = builder.bcc(mailbox_from(name, email)?);
        }
    }
    let in_reply_to = ensure_msg_id(&req.in_reply_to);
    if !in_reply_to.is_empty() {
        builder = builder.in_reply_to(in_reply_to);
    }
    for token in req.references.split_whitespace() {
        let id = ensure_msg_id(token);
        if !id.is_empty() {
            builder = builder.references(id);
        }
    }
    if req.files.is_empty() {
        return builder
            .header(ContentType::TEXT_PLAIN)
            .body(req.body.clone())
            .map_err(|e| Error::Msg(e.to_string()));
    }
    let mut mp = MultiPart::mixed().singlepart(
        SinglePart::builder()
            .header(ContentType::TEXT_PLAIN)
            .body(req.body.clone()),
    );
    for raw in &req.files {
        let path = PathBuf::from(raw);
        if !path.is_file() {
            return Err(Error::Msg(format!(
                "missing attachment {}",
                path.display()
            )));
        }
        let data = fs::read(&path)?;
        let name = path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("attachment")
            .to_string();
        mp = mp.singlepart(SmtpAttachment::new(name).body(data, mime_from_path(&path)));
    }
    builder.multipart(mp).map_err(|e| Error::Msg(e.to_string()))
}

fn session_password(state: &State, account_id: &str) -> Result<String, Error> {
    if let Some(entry) = state.sessions.get(account_id) {
        if !entry.password.is_empty() {
            return Ok(entry.password.clone());
        }
    }
    lookup_password(account_id)
}

fn send_cmd(state: &mut State, req: &Request) -> Result<serde_json::Value, Error> {
    let account_id = if req.account.is_empty() || req.account == "all" {
        state
            .accounts
            .first()
            .map(|a| a.id.clone())
            .ok_or_else(|| Error::Msg("no accounts".into()))?
    } else {
        req.account.clone()
    };
    let account = state.account(&account_id)?.clone();
    let to = parse_recipients(&req.to_list)?;
    let cc = parse_recipients(&req.cc_list)?;
    let bcc = parse_recipients(&req.bcc_list)?;
    if to.is_empty() && cc.is_empty() && bcc.is_empty() {
        return Err(Error::Msg("no recipients".into()));
    }
    let password = session_password(state, &account_id)?;
    let email = build_outgoing(&account, req, &to, &cc, &bcc, false, false)?;
    let mailer = smtp_transport(&account, &password)?;
    mailer
        .send(&email)
        .map_err(|e| Error::Msg(format!("SMTP: {e}")))?;
    let raw = email.formatted();
    let replace_drafts = req.mailbox == "drafts";
    let replace_uids = req.uids.clone();
    let saved = state
        .with_session(&account_id, |_, session| {
            let sent = resolve_mailbox(session, "sent")?;
            session.append_with_flags(&sent, &raw, &[Flag::Seen])?;
            if replace_drafts && !replace_uids.is_empty() {
                let drafts = resolve_mailbox(session, "drafts")?;
                delete_uids(session, &drafts, &replace_uids)?;
            }
            Ok(())
        })
        .is_ok();
    Ok(json!({
        "id": req.id,
        "ok": true,
        "saved": saved
    }))
}

fn draft_cmd(state: &mut State, req: &Request) -> Result<serde_json::Value, Error> {
    let account_id = if req.account.is_empty() || req.account == "all" {
        state
            .accounts
            .first()
            .map(|a| a.id.clone())
            .ok_or_else(|| Error::Msg("no accounts".into()))?
    } else {
        req.account.clone()
    };
    let account = state.account(&account_id)?.clone();
    let to = parse_recipient_list(&req.to_list, false)?;
    let cc = parse_recipient_list(&req.cc_list, false)?;
    let bcc = parse_recipient_list(&req.bcc_list, false)?;
    if to.is_empty()
        && cc.is_empty()
        && bcc.is_empty()
        && req.subject.trim().is_empty()
        && req.body.trim().is_empty()
        && req.files.is_empty()
    {
        return Err(Error::Msg("nothing to save".into()));
    }
    let email = build_outgoing(&account, req, &to, &cc, &bcc, true, true)?;
    let raw = email.formatted();
    let replace_uids = req.uids.clone();
    state.with_session(&account_id, |_, session| {
        let drafts = resolve_mailbox(session, "drafts")?;
        session.append_with_flags(&drafts, &raw, &[Flag::Seen, Flag::Draft])?;
        if !replace_uids.is_empty() {
            delete_uids(session, &drafts, &replace_uids)?;
        }
        Ok(())
    })?;
    Ok(json!({ "id": req.id, "ok": true }))
}

fn delete_uids(session: &mut ImapSession, mailbox: &str, uids: &[u32]) -> Result<(), Error> {
    if uids.is_empty() {
        return Ok(());
    }
    session.select(mailbox)?;
    let remaining = uids_still_present(session, uids)?;
    if remaining.is_empty() {
        return Ok(());
    }
    let uid_set = remaining
        .iter()
        .map(|u| u.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let _ = session.uid_store(&uid_set, "+FLAGS (\\Deleted)");
    let _ = session.uid_expunge(&uid_set);
    let _ = session.expunge();
    Ok(())
}

fn mark_seen(session: &mut ImapSession, mailbox: &str, uids: &[u32], seen: bool) -> Result<(), Error> {
    if uids.is_empty() {
        return Ok(());
    }
    session.select(mailbox)?;
    let remaining = uids_still_present(session, uids)?;
    if remaining.is_empty() {
        return Ok(());
    }
    let uid_set = remaining
        .iter()
        .map(|u| u.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let flags = if seen {
        "+FLAGS (\\Seen)"
    } else {
        "-FLAGS (\\Seen)"
    };
    session.uid_store(&uid_set, flags)?;
    Ok(())
}

fn seen_cmd(state: &mut State, req: &Request) -> Result<serde_json::Value, Error> {
    let account_id = request_account_id(state, req)?;
    let from_role = request_mailbox_role(req);
    let uids = request_uids(req, &from_role);
    if uids.is_empty() {
        return Err(Error::Msg("no uids".into()));
    }
    state.with_session(&account_id, |_, session| {
        let mailbox = resolve_mailbox(session, &from_role)?;
        mark_seen(session, &mailbox, &uids, !req.unseen)
    })?;
    Ok(json!({ "id": req.id, "ok": true }))
}

fn idle_account(account: DiskAccount, tx: mpsc::Sender<Event>) {
    loop {
        let password = match lookup_password(&account.id) {
            Ok(p) if !p.is_empty() => p,
            _ => {
                thread::sleep(Duration::from_secs(20));
                continue;
            }
        };
        let mut session = match connect(&account, &password) {
            Ok(s) => s,
            Err(_) => {
                thread::sleep(Duration::from_secs(15));
                continue;
            }
        };
        if session.select("INBOX").is_err() {
            thread::sleep(Duration::from_secs(15));
            continue;
        }
        loop {
            let handle = match session.idle() {
                Ok(h) => h,
                Err(_) => break,
            };
            match handle.wait_keepalive() {
                Ok(()) => {
                    if tx.send(Event::Exists).is_err() {
                        return;
                    }
                }
                Err(_) => break,
            }
        }
        thread::sleep(Duration::from_secs(5));
    }
}

fn status_cmd(state: &mut State, req: &Request) -> Result<serde_json::Value, Error> {
    let accounts = state.selected_accounts(&req.account)?;
    let mut unread = 0u32;
    let ids: Vec<String> = accounts.iter().map(|a| a.id.clone()).collect();
    for id in ids {
        unread += state.with_session(&id, |_, session| {
            session.select("INBOX")?;
            unseen_count(session)
        })?;
    }
    Ok(json!({ "id": req.id, "ok": true, "unread": unread }))
}

fn write_json(stdout: &Mutex<io::Stdout>, value: &serde_json::Value) {
    if let Ok(mut out) = stdout.lock() {
        let _ = writeln!(out, "{value}");
        let _ = out.flush();
    }
}

fn main() {
    let path = config_path();
    let mut state = match State::new(path) {
        Ok(state) => state,
        Err(err) => {
            let _ = writeln!(
                io::stderr(),
                "{}",
                json!({ "id": "", "ok": false, "error": err.to_string() })
            );
            std::process::exit(1);
        }
    };
    let (tx, rx) = mpsc::channel::<Event>();
    let stdout = Arc::new(Mutex::new(io::stdout()));
    {
        let tx = tx.clone();
        thread::spawn(move || {
            let stdin = io::stdin();
            for line in stdin.lock().lines() {
                let Ok(line) = line else { break };
                if tx.send(Event::Line(line)).is_err() {
                    break;
                }
            }
        });
    }
    for account in state.accounts.clone() {
        let tx = tx.clone();
        thread::spawn(move || idle_account(account, tx));
    }
    drop(tx);
    for event in rx {
        match event {
            Event::Exists => {
                write_json(
                    &stdout,
                    &json!({ "id": "", "ok": true, "event": "exists" }),
                );
            }
            Event::Line(line) => {
                if line.trim().is_empty() {
                    continue;
                }
                let req: Request = match serde_json::from_str(&line) {
                    Ok(req) => req,
                    Err(err) => {
                        write_json(
                            &stdout,
                            &json!({ "id": "", "ok": false, "error": format!("bad request: {err}") }),
                        );
                        continue;
                    }
                };
                if req.cmd == "shutdown" {
                    write_json(&stdout, &json!({ "id": req.id, "ok": true }));
                    break;
                }
                for response in handle(&mut state, req) {
                    write_json(&stdout, &response);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        collect_attachments, decode_bytes, decode_mime_words, html_to_text, looks_like_email,
        parse_addr_token, parse_recipient_list, parse_recipients, part_text, text_to_blocks,
        unescape,
    };
    use mailparse::parse_mail;

    #[test]
    fn trailing_on_wrote_becomes_quote() {
        let text = "Thanks, see you Monday.\n\nOn Tue, Aug 19, 2026 at 3:07 PM K Salone wrote:\nHello everyone\nPlease find the notes below.";
        let blocks = text_to_blocks(text);
        assert!(blocks.iter().any(|b| b.kind == "p" && b.text.contains("see you Monday")), "{blocks:?}");
        let quote = blocks.iter().find(|b| b.kind == "history").expect("history");
        assert!(quote.text.contains("K Salone wrote"), "{}", quote.text);
        assert!(quote.text.contains("Hello everyone"), "{}", quote.text);
        assert!(!blocks.iter().any(|b| b.kind == "p" && b.text.contains("Hello everyone")));
    }

    #[test]
    fn newsletter_blockquote_is_not_history() {
        let mut original = String::from("City council met Tuesday and approved the budget.\n\n");
        original.push_str("Residents spoke for an hour about potholes, parks, and the library millage.\n\n");
        original.push_str("> The Missoulian reported that the vote was 4-1, with one member absent.\n\n");
        original.push_str("That matches what we heard in the room.");
        let blocks = text_to_blocks(&original);
        assert!(blocks.iter().any(|b| b.kind == "quote" && b.text.contains("Missoulian")), "{blocks:?}");
        assert!(blocks.iter().all(|b| b.kind != "history"), "{blocks:?}");
        assert!(blocks.iter().any(|b| b.kind == "p" && b.text.contains("matches what we heard")), "{blocks:?}");
    }

    #[test]
    fn mid_quote_does_not_eat_reply() {
        let text = "See below.\n\n> old question\n\nI think we should wait.";
        let blocks = text_to_blocks(text);
        assert!(blocks.iter().any(|b| b.kind == "quote" && b.text.contains("old question")), "{blocks:?}");
        assert!(blocks.iter().any(|b| b.kind == "p" && b.text.contains("should wait")), "{blocks:?}");
    }

    #[test]
    fn collects_pdf_attachment() {
        let raw = b"From: a@b.com\r\n\
To: c@d.com\r\n\
Subject: files\r\n\
MIME-Version: 1.0\r\n\
Content-Type: multipart/mixed; boundary=bound\r\n\
\r\n\
--bound\r\n\
Content-Type: text/plain; charset=utf-8\r\n\
\r\n\
Hello\r\n\
--bound\r\n\
Content-Type: application/pdf; name=\"doc.pdf\"\r\n\
Content-Disposition: attachment; filename=\"doc.pdf\"\r\n\
Content-Transfer-Encoding: base64\r\n\
\r\n\
AQIDBA==\r\n\
--bound--\r\n";
        let parsed = parse_mail(raw).expect("parse");
        let (text, html) = part_text(&parsed).expect("text");
        assert!(!html);
        assert_eq!(text.trim(), "Hello");
        let files = collect_attachments(&parsed);
        assert_eq!(files.len(), 1, "{files:?}");
        assert_eq!(files[0].name, "doc.pdf");
        assert_eq!(files[0].mime, "application/pdf");
        assert!(files[0].size > 0);
    }

    #[test]
    fn unescapes_zwnj_and_numeric_zw() {
        let text = unescape("foo&zwnj;bar&#8204;baz&#x200c;qux");
        assert_eq!(text, "foobarbazqux");
        assert_eq!(unescape("A&nbsp;B&amp;C"), "A B&C");
        assert_eq!(html_to_text("<p>join&zwnj;ed</p>").replace('\n', ""), "joined");
    }

    #[test]
    fn html_blockquote_becomes_quote() {
        let html = "<p>My reply.</p><blockquote>Earlier message from Kyle</blockquote>";
        let blocks = text_to_blocks(&html_to_text(html));
        assert!(blocks.iter().any(|b| b.kind == "p" && b.text.contains("My reply")), "{blocks:?}");
        let quote = blocks.iter().find(|b| b.kind == "quote").expect("quote");
        assert!(quote.text.contains("Earlier message from Kyle"), "{}", quote.text);
        assert!(blocks.iter().all(|b| b.kind != "history"), "{blocks:?}");
    }

    #[test]
    fn quoted_reply_history_is_history() {
        let text = "Sounds good.\n\n> On Tue, Aug 19, 2026 at 3:07 PM K Salone wrote:\n> Hello everyone\n> Please find the notes below.\n> More of the previous email keeps going.";
        let blocks = text_to_blocks(text);
        assert!(blocks.iter().any(|b| b.kind == "p" && b.text.contains("Sounds good")), "{blocks:?}");
        assert!(blocks.iter().any(|b| b.kind == "history" && b.text.contains("Hello everyone")), "{blocks:?}");
    }

    #[test]
    fn decodes_short_q_word() {
        assert_eq!(decode_mime_words("=?UTF-8?Q?hello_there?="), "hello there");
    }

    #[test]
    fn decodes_long_b_word() {
        let encoded = "=?utf-8?B?TG9yZW0gaXBzdW0gZG9sb3Igc2l0IGFtZXQsIGNvbnNlY3RldHVyIGFkaXBpc2NpbmcgZWxpdC4gVXQgaW50ZXJkdW0gcXVhbSBldSBmYWNpbGlzaXMgb3JuYXJlLg==?=";
        assert_eq!(
            decode_mime_words(encoded),
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut interdum quam eu facilisis ornare."
        );
    }

    #[test]
    fn decodes_split_q_subject_with_quotes() {
        let encoded = "=?UTF-8?Q?Fwd:_Meeting_records:_=E2=80=9COnline_Givehub_Meeting_?= =?UTF-8?Q?with_Debbie_Churchill=E2=80=9D,_Aug_19,_2026?=";
        assert_eq!(
            decode_mime_words(encoded),
            "Fwd: Meeting records: “Online Givehub Meeting with Debbie Churchill”, Aug 19, 2026"
        );
    }

    #[test]
    fn decodes_givehub_split_in_the_middle() {
        let encoded = "=?UTF-8?Q?Fwd:_Meeting_records:_=E2=80=9COnline_Givehub_Meeting_=?= =?UTF-8?Q?bie_Churchill=29=E2=80=9D,_Aug_19=2C_2026?=";
        let got = decode_mime_words(encoded);
        assert!(!got.contains("=?UTF-8"), "{got}");
        assert!(got.contains("Givehub"), "{got}");
        assert!(got.contains("Churchill"), "{got}");
    }

    #[test]
    fn decode_bytes_strips_quotes() {
        assert_eq!(decode_bytes(b"\"=?UTF-8?Q?Hello_world?=\""), "Hello world");
    }

    #[test]
    fn parses_named_and_bare_addresses() {
        assert_eq!(
            parse_addr_token("Ada Lovelace <ada@example.com>").unwrap(),
            ("Ada Lovelace".into(), "ada@example.com".into())
        );
        assert_eq!(
            parse_addr_token("ada@example.com").unwrap(),
            ("".into(), "ada@example.com".into())
        );
        assert!(looks_like_email("ada@example.com"));
        assert!(!looks_like_email("not-an-address"));
        let got = parse_recipients(&["Ada <ada@example.com>, bob@site.org".into()]).unwrap();
        assert_eq!(got.len(), 2);
        assert_eq!(got[1].1, "bob@site.org");
        let draft = parse_recipient_list(&["ada@example.com, not-an-address".into()], false).unwrap();
        assert_eq!(draft.len(), 1);
        assert_eq!(draft[0].1, "ada@example.com");
        assert!(parse_recipient_list(&["".into()], false).unwrap().is_empty());
    }
}
