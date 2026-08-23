"""Omarchy Mail helper — IMAP/SMTP over JSON lines, Python stdlib only."""

from __future__ import annotations

import json
import os
import queue
import re
import ssl
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from email import policy
from email.header import decode_header, make_header
from email.message import EmailMessage
from email.parser import BytesParser
from email.utils import formatdate, getaddresses, parsedate_to_datetime
from imaplib import IMAP4, IMAP4_SSL
from pathlib import Path
from typing import Any

PAGE = 50
FETCH_HEADERS = (
    "(UID FLAGS INTERNALDATE "
    "BODY.PEEK[HEADER.FIELDS (FROM TO CC BCC SUBJECT DATE MESSAGE-ID REFERENCES IN-REPLY-TO)])"
)
FETCH_BODY = "(FLAGS BODY.PEEK[])"

MAILBOX_CANDIDATES = {
    "archive": ["Archive", "Archives", "INBOX.Archive", "[Gmail]/All Mail"],
    "trash": ["Trash", "Deleted Messages", "INBOX.Trash", "[Gmail]/Trash"],
    "sent": [
        "INBOX.Sent Messages",
        "Sent Messages",
        "Sent Items",
        "Sent",
        "INBOX.Sent",
        "[Gmail]/Sent Mail",
    ],
    "drafts": ["INBOX.Drafts", "Drafts", "Draft", "[Gmail]/Drafts"],
    "junk": [
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
}

SPECIAL_USE = {
    "sent": "\\sent",
    "drafts": "\\drafts",
    "trash": "\\trash",
    "archive": "\\archive",
    "junk": "\\junk",
}

MIME_EXT = {
    "application/pdf": ".pdf",
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/gif": ".gif",
    "image/webp": ".webp",
    "text/plain": ".txt",
    "text/csv": ".csv",
    "text/calendar": ".ics",
    "application/zip": ".zip",
    "application/json": ".json",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": ".xlsx",
    "application/msword": ".doc",
    "message/rfc822": ".eml",
}

MIME_FROM_EXT = {
    "pdf": "application/pdf",
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "gif": "image/gif",
    "webp": "image/webp",
    "txt": "text/plain",
    "csv": "text/csv",
    "html": "text/html",
    "htm": "text/html",
    "ics": "text/calendar",
    "zip": "application/zip",
    "json": "application/json",
    "doc": "application/msword",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xls": "application/vnd.ms-excel",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "ppt": "application/vnd.ms-powerpoint",
    "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "eml": "message/rfc822",
}


class Error(Exception):
    pass


def home() -> str:
    return os.environ.get("HOME", "")


def config_path() -> str:
    return os.environ.get(
        "OMARCHY_MAIL_CONFIG",
        f"{home()}/.local/state/omarchy/settings/omarchy-mail.json",
    )


def cache_dir() -> Path:
    return Path(f"{home()}/.local/state/omarchy/mail/cache")


def cache_path(account_id: str, mailbox: str) -> Path:
    return cache_dir() / account_id / f"{mailbox}.json"


def download_dir() -> Path:
    env = os.environ.get("XDG_DOWNLOAD_DIR", "").strip()
    if env:
        return Path(env)
    return Path(f"{home()}/Downloads")


def open_cache_dir() -> Path:
    return Path(f"{home()}/.cache/omarchy/mail/open")


def lookup_password(account_id: str) -> str:
    try:
        out = subprocess.run(
            ["secret-tool", "lookup", "service", "omarchy-mail", "account", account_id],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        raise Error(f"secret-tool: {exc}") from exc
    if out.returncode != 0:
        raise Error("no password in keyring")
    return out.stdout.strip()


def load_accounts(path: str) -> list[dict[str, Any]]:
    try:
        raw = Path(path).read_text()
    except OSError as exc:
        raise Error(f"couldn't read {path}: {exc}") from exc
    try:
        file = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise Error(f"invalid config: {exc}") from exc
    return list(file.get("accounts") or [])


# --- RFC2047 -----------------------------------------------------------------


def still_rfc2047(text: str) -> bool:
    lower = text.lower()
    start = lower.find("=?")
    if start < 0:
        return False
    rest = lower[start + 2 :]
    return "?q?" in rest or "?b?" in rest


def unfold_header(raw: str) -> str:
    s = raw.replace("\r\n", "\n").replace("\r", "\n")
    out: list[str] = []
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "\n":
            i += 1
            while i < len(s) and s[i] in " \t":
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def decode_q_bytes(text: bytes) -> bytes:
    out = bytearray()
    i = 0
    while i < len(text):
        b = text[i]
        if b == 95:  # _
            out.append(32)
            i += 1
        elif b == 61 and i + 1 < len(text) and text[i + 1] in (10, 13):
            i += 1
            if i < len(text) and text[i] in (10, 13):
                i += 1
        elif b == 61 and i + 2 < len(text):
            try:
                out.append(int(text[i + 1 : i + 3].decode("ascii"), 16))
                i += 3
            except ValueError:
                i += 1
        else:
            out.append(b)
            i += 1
    return bytes(out)


def decode_b64_bytes(text: bytes) -> bytes | None:
    def val(c: int) -> int | None:
        if 65 <= c <= 90:
            return c - 65
        if 97 <= c <= 122:
            return c - 97 + 26
        if 48 <= c <= 57:
            return c - 48 + 52
        if c in (43, 45):
            return 62
        if c in (47, 95):
            return 63
        return None

    raw = bytes(b for b in text if not (b <= 32 or b == 61))
    if not raw:
        return b""
    out = bytearray()
    i = 0
    while i < len(raw):
        a = val(raw[i])
        if a is None:
            return None
        b = val(raw[i + 1]) if i + 1 < len(raw) else 0
        if b is None:
            return None
        out.append((a << 2) | (b >> 4))
        if i + 2 < len(raw):
            c = val(raw[i + 2]) or 0
            out.append(((b << 4) | (c >> 2)) & 0xFF)
            if i + 3 < len(raw):
                d = val(raw[i + 3]) or 0
                out.append(((c << 6) | d) & 0xFF)
        i += 4
    return bytes(out)


def decode_charset(label: str, data: bytes) -> str:
    lower = label.strip().lower()
    if lower in ("utf-8", "utf8", "us-ascii", "ascii"):
        return data.decode("utf-8", "replace")
    if lower in ("iso-8859-1", "latin1", "windows-1252"):
        return "".join(chr(b) for b in data)
    return data.decode("utf-8", "replace")


def parse_encoded_word(data: bytes) -> tuple[int, str] | None:
    if len(data) < 6 or data[0] != 61 or data[1] != 63:
        return None
    try:
        charset_end = data.index(63, 2)
        enc_end = data.index(63, charset_end + 1)
    except ValueError:
        return None
    k = enc_end + 1
    while k + 1 < len(data):
        if data[k] == 63 and data[k + 1] == 61:
            charset = data[2:charset_end].decode("ascii", "ignore")
            encoding = data[charset_end + 1 : enc_end].decode("ascii", "ignore")
            payload = data[enc_end + 1 : k]
            enc = encoding.upper()
            if enc == "Q":
                decoded = decode_charset(charset, decode_q_bytes(payload))
            elif enc == "B":
                raw = decode_b64_bytes(payload)
                if raw is None:
                    return None
                decoded = decode_charset(charset, raw)
            else:
                return None
            return k + 2, decoded
        k += 1
    return None


def decode_mime_words_fallback(text: str) -> str:
    data = text.encode("utf-8")
    out: list[str] = []
    i = 0
    last_encoded = False
    while i < len(data):
        if last_encoded and data[i] <= 32:
            j = i
            while j < len(data) and data[j] <= 32:
                j += 1
            if parse_encoded_word(data[j:]) is not None:
                i = j
                continue
        parsed = parse_encoded_word(data[i:])
        if parsed is not None:
            consumed, decoded = parsed
            out.append(decoded)
            i += consumed
            last_encoded = True
            continue
        last_encoded = False
        ch = text[i:][:1]
        if not ch:
            break
        out.append(ch)
        i += len(ch.encode("utf-8"))
    return "".join(out)


def take_decoded(text: str) -> str | None:
    trimmed = text.strip()
    if not trimmed or still_rfc2047(trimmed):
        return None
    return trimmed


def decode_mime_words(raw: str) -> str:
    unfolded = unfold_header(raw)
    got = take_decoded(decode_mime_words_fallback(unfolded))
    if got is not None:
        return got
    try:
        header = str(make_header(decode_header(unfolded)))
        got = take_decoded(header)
        if got is not None:
            return got
    except Exception:
        pass
    return raw.strip()


def decode_bytes(raw: bytes | str) -> str:
    text = raw.decode("utf-8", "replace") if isinstance(raw, (bytes, bytearray)) else str(raw)
    text = text.strip()
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        text = text[1:-1].strip()
    return decode_mime_words(text)


# --- HTML / blocks -----------------------------------------------------------


def html_attr(tag: str, name: str) -> str | None:
    lower = tag.lower()
    key = f"{name}="
    pos = lower.find(key)
    if pos < 0:
        return None
    rest = tag[pos + len(key) :].lstrip()
    if not rest:
        return None
    if rest[0] in "\"'":
        quote = rest[0]
        end = rest.find(quote, 1)
        return rest[1:end] if end >= 0 else rest[1:]
    out = []
    for ch in rest:
        if ch.isspace() or ch in ">":
            break
        out.append(ch)
    return "".join(out)


def tag_is_quote(name: str, raw: str) -> bool:
    if name in ("blockquote", "cite"):
        return True
    if name == "div":
        cls = (html_attr(raw, "class") or "").lower()
        return "gmail_quote" in cls or "quote" in cls
    return False


def is_void_tag(name: str) -> bool:
    return name in {
        "br", "hr", "img", "input", "meta", "link", "area", "base", "col",
        "embed", "source", "track", "wbr",
    }


def named_entity(name: str) -> str | None:
    return {
        "amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'",
        "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ",
        "zwnj": "", "zwj": "", "lrm": "", "rlm": "", "shy": "", "zwsp": "",
        "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·",
        "lsquo": "‘", "sbquo": "‘", "rsquo": "’",
        "ldquo": "“", "bdquo": "“", "rdquo": "”",
        "laquo": "«", "raquo": "»", "copy": "©", "reg": "®", "trade": "™",
        "deg": "°", "times": "×", "divide": "÷", "plusmn": "±",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢",
        "iexcl": "¡", "iquest": "¿",
    }.get(name.lower())


def char_entity(ch: str) -> str:
    if ch in "\u00a0\u2002\u2003\u2009\u202f":
        return " "
    if ch in "\u00ad\u200b\u200c\u200d\u200e\u200f\ufeff":
        return ""
    return ch


def parse_entity(s: str) -> tuple[str, int] | None:
    if not s.startswith("&"):
        return None
    rest = s[1:]
    if rest.startswith("#"):
        hexed = rest[1:2] in "xX"
        digits = rest[2:] if hexed else rest[1:]
        end = digits.find(";")
        if end <= 0 or end > 8:
            return None
        try:
            num = int(digits[:end], 16 if hexed else 10)
        except ValueError:
            return None
        try:
            ch = chr(num)
        except ValueError:
            return None
        return char_entity(ch), 2 + int(hexed) + end + 1
    end = rest.find(";")
    if end <= 0 or end > 32:
        return None
    value = named_entity(rest[:end])
    if value is None:
        return None
    return value, end + 2


def unescape(text: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(text):
        if text[i] == "&":
            parsed = parse_entity(text[i:])
            if parsed:
                value, n = parsed
                out.append(value)
                i += n
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


def push_quoted(out: list[str], piece: str, depth: int) -> None:
    if depth <= 0:
        out.append(piece)
        return
    prefix = "> " * depth
    for ch in piece:
        if not out or out[-1].endswith("\n"):
            if ch != "\n":
                out.append(prefix)
        out.append(ch)


def html_to_text(html: str) -> str:
    out: list[str] = []
    in_tag = False
    skip = False
    tag = ""
    link_href: str | None = None
    link_text = ""
    quote_depth = 0
    quote_stack: list[bool] = []
    for ch in html:
        if ch == "<":
            in_tag = True
            tag = ""
            continue
        if in_tag:
            if ch == ">":
                raw = tag.strip()
                closing = raw.startswith("/")
                name = raw.lstrip("/").split(None, 1)[0].lower() if raw.lstrip("/") else ""
                if name in ("script", "style"):
                    skip = not closing
                if name == "a" and not closing:
                    link_href = html_attr(raw, "href")
                    link_text = ""
                if name == "a" and closing and link_href is not None:
                    label = link_text.strip() or link_href
                    push_quoted(out, f"[{label}]({link_href})", quote_depth)
                    link_href = None
                    link_text = ""
                if not is_void_tag(name):
                    if closing:
                        if quote_stack and quote_stack.pop() and quote_depth > 0:
                            quote_depth -= 1
                    else:
                        quoted = tag_is_quote(name, raw)
                        quote_stack.append(quoted)
                        if quoted:
                            quote_depth += 1
                if name in ("br", "p", "div", "li", "blockquote") or name.startswith("h"):
                    push_quoted(out, "\n", quote_depth)
                in_tag = False
            else:
                tag += ch
            continue
        if skip:
            continue
        if link_href is not None:
            link_text += ch
        else:
            push_quoted(out, ch, quote_depth)
    return unescape("".join(out))


def is_quote_line(line: str) -> bool:
    return line.lstrip().startswith(">")


def is_attribution(line: str) -> bool:
    t = line.strip()
    if len(t) < 8:
        return False
    lower = t.lower()
    if lower.startswith("on ") and any(s in lower for s in (" wrote", " writes", " written")):
        return True
    if " wrote:" in lower or " writes:" in lower:
        return True
    if (lower.startswith("le ") or lower.startswith("el ")) and any(
        s in lower for s in ("écrit", "escribi", "escrito")
    ):
        return True
    if lower.startswith("am ") and "schrieb" in lower:
        return True
    if "original message" in lower:
        return True
    if lower.startswith("begin forwarded message"):
        return True
    marks = sum(1 for c in t if c in "-_")
    return marks >= 8 and all(c in "-_ \t" for c in t)


def looks_like_quoted_header(line: str) -> bool:
    lower = strip_quote_prefixes(line).strip().lower()
    return lower.startswith(
        ("from:", "sent:", "date:", "to:", "subject:", "cc:")
    )


def is_outlook_quote_start(lines: list[str], i: int) -> bool:
    if not lines[i].strip().lower().startswith("from:"):
        return False
    sent = False
    to_or_subj = False
    for line in lines[i : i + 8]:
        l = line.strip().lower()
        if l.startswith("sent:") or l.startswith("date:"):
            sent = True
        if l.startswith("to:") or l.startswith("subject:"):
            to_or_subj = True
    return sent and to_or_subj


def quote_has_history_signal(lines: list[str]) -> bool:
    for line in lines:
        stripped = strip_quote_prefixes(line)
        if is_attribution(line) or is_attribution(stripped) or looks_like_quoted_header(line):
            return True
        t = line.lstrip()
        if t.startswith(">>") or t.startswith("> >"):
            return True
    return False


def rest_is_trailing_quote(lines: list[str], start: int) -> bool:
    if start == 0:
        return False
    rest = [l for l in lines[start:] if l.strip()]
    if not rest:
        return False
    if is_attribution(rest[0]) or is_outlook_quote_start(lines, start):
        return True
    if not all(is_quote_line(l) or is_attribution(l) for l in rest):
        return False
    if quote_has_history_signal(rest):
        return True
    trailing_len = sum(len(l) for l in rest)
    original_len = sum(len(l) for l in lines[:start])
    return trailing_len > 280 and trailing_len > original_len


def trailing_quote_start(lines: list[str]) -> int | None:
    for i, line in enumerate(lines):
        if (is_attribution(line) or is_quote_line(line) or is_outlook_quote_start(lines, i)) and rest_is_trailing_quote(lines, i):
            return i
    return None


def strip_quote_prefixes(text: str) -> str:
    bits = []
    for line in text.splitlines():
        t = line.lstrip()
        while t.startswith(">"):
            t = t[1:].lstrip()
        bits.append(t)
    return "\n".join(bits).strip()


def push_paragraph(chunk: str, blocks: list[dict[str, str]]) -> None:
    line = chunk.strip()
    if not line:
        return
    if line.startswith("# "):
        blocks.append({"type": "heading", "text": line.lstrip("#").strip()})
        return
    rows = line.splitlines()
    if rows and all(r.lstrip().startswith(("- ", "* ")) for r in rows):
        body = "\n".join(r.lstrip().lstrip("-*").strip() for r in rows)
        blocks.append({"type": "list", "text": body})
        return
    blocks.append({"type": "p", "text": line})


def push_chunk(chunk: str, blocks: list[dict[str, str]]) -> None:
    lines = chunk.splitlines()
    i = 0
    while i < len(lines):
        quoted = is_quote_line(lines[i])
        j = i + 1
        while j < len(lines) and is_quote_line(lines[j]) == quoted:
            j += 1
        part = "\n".join(lines[i:j])
        if quoted:
            body = strip_quote_prefixes(part)
            if body:
                blocks.append({"type": "quote", "text": body})
        else:
            push_paragraph(part, blocks)
        i = j


def text_to_blocks(text: str) -> list[dict[str, str]]:
    cleaned = text.replace("\r", "")
    lines = cleaned.split("\n")
    idx = trailing_quote_start(lines)
    if idx is not None:
        original = "\n".join(lines[:idx])
        trailing = "\n".join(lines[idx:])
    else:
        original = cleaned
        trailing = None
    blocks: list[dict[str, str]] = []
    for chunk in original.split("\n\n"):
        push_chunk(chunk, blocks)
    if trailing:
        body = strip_quote_prefixes(trailing)
        if body:
            blocks.append({"type": "history", "text": body})
    if not blocks:
        blocks.append({"type": "p", "text": cleaned.strip()})
    return blocks


# --- addresses ---------------------------------------------------------------


def looks_like_email(value: str) -> bool:
    value = value.strip()
    parts = value.split("@")
    if len(parts) != 2:
        return False
    local, host = parts
    return bool(local) and "." in host and not host.startswith(".") and not host.endswith(".")


def parse_addr_token(token: str) -> tuple[str, str]:
    token = token.strip()
    if not token:
        raise Error("empty address")
    start = token.rfind("<")
    end = token.rfind(">")
    if start >= 0 and end > start:
        email = token[start + 1 : end].strip()
        name = token[:start].strip().strip("\"'")
        if looks_like_email(email):
            return name, email
    if looks_like_email(token):
        return "", token
    raise Error(f"invalid address: {token}")


def parse_recipient_list(items: list[str], strict: bool) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for raw in items:
        cur = ""
        depth = 0
        for ch in raw:
            if ch == "<":
                depth += 1
                cur += ch
            elif ch == ">":
                if depth > 0:
                    depth -= 1
                cur += ch
            elif ch in ",;" and depth == 0:
                token = cur.strip()
                cur = ""
                if token:
                    _push_recipient(out, seen, token, strict)
            else:
                cur += ch
        token = cur.strip()
        if token:
            _push_recipient(out, seen, token, strict)
    if not out and strict:
        raise Error("no recipients")
    return out


def _push_recipient(out: list[tuple[str, str]], seen: set[str], token: str, strict: bool) -> None:
    try:
        name, email = parse_addr_token(token)
    except Error:
        if strict:
            raise
        return
    key = email.lower()
    if key not in seen:
        seen.add(key)
        out.append((name, email))


def parse_recipients(items: list[str]) -> list[tuple[str, str]]:
    return parse_recipient_list(items, True)


def parse_from(header: str) -> tuple[str, str]:
    start = header.rfind("<")
    end = header.rfind(">")
    if start >= 0 and end > start:
        email = header[start + 1 : end].strip()
        name = header[:start].strip().strip('"')
        return (email if not name else name, email)
    email = header.strip()
    return email, email


def push_participant(out: list[dict[str, Any]], name: str, email: str, me: str) -> None:
    email = email.strip()
    if not email:
        return
    name = name.strip() or email
    if any(p["email"].lower() == email.lower() for p in out):
        return
    out.append({"name": name, "email": email, "mine": bool(me) and email.lower() == me.lower()})


def parse_address_list(raw: str, me: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    pairs = getaddresses([raw]) if raw.strip() else []
    for name, email in pairs:
        push_participant(out, decode_mime_words(name), email, me)
    if not out and raw.strip():
        name, email = parse_from(raw)
        push_participant(out, name, email, me)
    return out


def normalize_subject(subject: str) -> str:
    s = subject.strip()
    while True:
        lower = s.lower()
        for prefix in ("re:", "fwd:", "fw:"):
            if lower.startswith(prefix):
                s = s[len(prefix) :].strip()
                break
        else:
            break
    return s.lower()


def header_ids(headers: dict[str, str]) -> list[str]:
    ids: list[str] = []
    for key in ("message-id", "in-reply-to", "references"):
        value = headers.get(key, "")
        for tok in value.split():
            token = tok.strip()
            if token and not any(i.lower() == token.lower() for i in ids):
                ids.append(token)
    return ids


def thread_key(headers: dict[str, str], subject: str) -> str:
    refs = headers.get("references", "")
    first = refs.split()[0] if refs.split() else ""
    if first:
        return first.strip()
    reply = headers.get("in-reply-to", "").split()
    if reply and reply[0].strip():
        return reply[0].strip()
    mid = headers.get("message-id", "").strip()
    if mid:
        return mid
    return f"subj:{normalize_subject(subject)}"


def message_timestamp(when: str) -> int:
    text = when.strip().strip('"')
    if not text:
        return 0
    for fmt in ("%d-%b-%Y %H:%M:%S %z", " %d-%b-%Y %H:%M:%S %z"):
        try:
            return int(datetime.strptime(text, fmt).timestamp())
        except ValueError:
            pass
    try:
        dt = parsedate_to_datetime(text)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    except Exception:
        return 0


# --- IMAP plumbing -----------------------------------------------------------


def imap_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def parse_list_line(raw: bytes | str) -> tuple[str, list[str]]:
    s = raw.decode("utf-8", "replace") if isinstance(raw, (bytes, bytearray)) else raw
    attrs: list[str] = []
    rest = s
    if s.startswith("("):
        end = s.find(")")
        if end >= 0:
            inner = s[1:end]
            attrs = [a.strip().lstrip("\\").lower() for a in inner.split() if a]
            rest = s[end + 1 :].strip()
    parts = rest.split(None, 1)
    name = parts[1] if len(parts) > 1 else rest
    name = name.strip()
    if name.startswith('"') and name.endswith('"') and len(name) >= 2:
        name = name[1:-1]
    return name, attrs


def connect(account: dict[str, Any], password: str) -> IMAP4:
    if not account.get("imapTls", True):
        raise Error("IMAP without TLS is not supported yet")
    try:
        port = int(str(account.get("imapPort") or "993"))
    except ValueError as exc:
        raise Error("invalid IMAP port") from exc
    host = str(account.get("imapHost") or "")
    ctx = ssl.create_default_context()
    try:
        imap = IMAP4_SSL(host, port, ssl_context=ctx)
        imap.login(str(account.get("username") or ""), password)
    except Exception as exc:
        raise Error(f"login failed: {exc}") from exc
    return imap


def exists_count(imap: IMAP4, mailbox: str) -> int:
    typ, data = imap.select(mailbox)
    if typ != "OK":
        raise Error(f"couldn't select {mailbox}")
    try:
        return int(data[0] or 0)
    except (TypeError, ValueError):
        return 0


def resolve_mailbox(imap: IMAP4, role: str) -> str:
    if role in ("inbox", ""):
        return "INBOX"
    typ, data = imap.list()
    listed = []
    if typ == "OK":
        for item in data or []:
            if item:
                listed.append(parse_list_line(item))
    hits: list[str] = []
    flag = SPECIAL_USE.get(role)
    if flag:
        for name, attrs in listed:
            if flag.lstrip("\\") in attrs and not any(h.lower() == name.lower() for h in hits):
                hits.append(name)
    for candidate in MAILBOX_CANDIDATES.get(role, ["INBOX"]):
        for name, _attrs in listed:
            if name.lower() == candidate.lower() and not any(h.lower() == name.lower() for h in hits):
                hits.append(name)
    if not hits:
        raise Error(f"no {role} mailbox on this account")
    if len(hits) == 1:
        return hits[0]
    best = hits[0]
    best_n = 0
    for hit in hits:
        try:
            n = exists_count(imap, hit)
        except Error:
            continue
        if n >= best_n:
            best_n = n
            best = hit
    return best


UID_RE = re.compile(rb"\bUID\s+(\d+)", re.I)
FLAGS_RE = re.compile(rb"FLAGS\s+\(([^)]*)\)", re.I)
INTERNALDATE_RE = re.compile(rb'INTERNALDATE\s+"([^"]+)"', re.I)


def parse_fetch_data(data: list[Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    i = 0
    while i < len(data):
        item = data[i]
        meta = b""
        body = b""
        if item is None:
            i += 1
            continue
        if isinstance(item, tuple) and item:
            meta = item[0] if isinstance(item[0], (bytes, bytearray)) else str(item[0]).encode()
            if len(item) > 1 and isinstance(item[1], (bytes, bytearray)):
                body = bytes(item[1])
            if i + 1 < len(data) and isinstance(data[i + 1], (bytes, bytearray)) and data[i + 1].strip() in (b")", b")\r\n"):
                i += 1
        elif isinstance(item, (bytes, bytearray)):
            meta = bytes(item)
        uid_m = UID_RE.search(meta)
        flags_m = FLAGS_RE.search(meta)
        date_m = INTERNALDATE_RE.search(meta)
        flags = (flags_m.group(1).decode("utf-8", "replace").lower() if flags_m else "")
        out.append(
            {
                "uid": int(uid_m.group(1)) if uid_m else 0,
                "unread": "\\seen" not in flags,
                "internaldate": date_m.group(1).decode("utf-8", "replace") if date_m else "",
                "body": body,
                "meta": meta,
            }
        )
        i += 1
    return [row for row in out if row["uid"] or row["body"]]


def imap_fetch(imap: IMAP4, spec: str, items: str, uid: bool) -> list[dict[str, Any]]:
    if uid:
        typ, data = imap.uid("FETCH", spec, items)
    else:
        typ, data = imap.fetch(spec, items)
    if typ != "OK" or not data:
        return []
    return parse_fetch_data(list(data))


def uid_search(imap: IMAP4, criteria: str, charset: str | None = None) -> list[int]:
    if charset:
        typ, data = imap.uid("SEARCH", charset, criteria)
    else:
        typ, data = imap.uid("SEARCH", None, criteria)
    if typ != "OK":
        raise Error("search failed")
    raw = data[0] or b""
    if not raw:
        return []
    return [int(x) for x in raw.decode().split() if x.isdigit()]


def and_or_search(query: str, fields: list[str], charset: bool) -> str:
    clauses = []
    for token in query.split():
        needle = imap_quote(token)
        clause = f"{fields[0]} {needle}"
        for field in fields[1:]:
            clause = f"OR {clause} {field} {needle}"
        clauses.append(clause)
    body = " ".join(clauses)
    return body


def search_uids(imap: IMAP4, query: str, body_fallback: bool) -> list[int]:
    charset = not query.isascii()
    field_sets = [
        ["SUBJECT", "FROM", "TO", "CC"],
        ["SUBJECT", "FROM", "TO"],
        ["SUBJECT", "FROM"],
    ]
    tried: set[str] = set()
    last_err: Exception | None = None
    any_ok = False
    for fields in field_sets:
        for use_charset in ([charset, False] if charset else [False]):
            criteria = and_or_search(query, fields, use_charset)
            key = f"{use_charset}:{criteria}"
            if key in tried:
                continue
            tried.add(key)
            try:
                found = uid_search(imap, criteria, "UTF-8" if use_charset else None)
                any_ok = True
                if found:
                    return found
            except Exception as exc:
                last_err = exc
    if body_fallback:
        for use_charset in ([charset, False] if charset else [False]):
            criteria = and_or_search(query, ["BODY"], use_charset)
            key = f"{use_charset}:{criteria}"
            if key in tried:
                continue
            tried.add(key)
            try:
                return uid_search(imap, criteria, "UTF-8" if use_charset else None)
            except Exception as exc:
                last_err = exc
    if any_ok:
        return []
    raise Error(str(last_err) if last_err else "search failed")


def query_set(imap: IMAP4, exists: int, limit: int, query: str, body_fallback: bool) -> tuple[str, bool]:
    q = query.strip()
    if not q:
        if exists <= 0:
            return "", False
        take = max(limit, 1)
        start = max(exists - take + 1, 1)
        return f"{start}:{exists}", False
    uids = search_uids(imap, q, body_fallback)
    uids.sort()
    if len(uids) > limit:
        uids = uids[-limit:]
    if not uids:
        return "", True
    return ",".join(str(u) for u in uids), True


def unseen_count(imap: IMAP4) -> int:
    try:
        typ, data = imap.search(None, "UNSEEN")
        if typ == "OK" and data and data[0]:
            return len(data[0].split())
    except Exception:
        pass
    try:
        return len(uid_search(imap, "UNSEEN"))
    except Exception:
        return 0


def headers_from_bytes(raw: bytes) -> dict[str, str]:
    if not raw:
        return {}
    msg = BytesParser(policy=policy.default).parsebytes(raw)
    out = {}
    for key in ("Subject", "From", "To", "Cc", "Bcc", "Date", "Message-ID", "References", "In-Reply-To"):
        value = msg.get(key)
        if value:
            out[key.lower()] = decode_mime_words(str(value))
    return out


def people_from_header(raw: str) -> list[tuple[str, str]]:
    out = []
    for name, email in getaddresses([raw] if raw else []):
        if email:
            out.append((decode_mime_words(name), email))
    if not out and raw.strip():
        name, email = parse_from(raw)
        if email:
            out.append((name, email))
    return out


def fetch_to_row(account: dict[str, Any], mailbox: str, item: dict[str, Any]) -> dict[str, Any] | None:
    uid = item.get("uid") or 0
    if not uid:
        return None
    headers = headers_from_bytes(item.get("body") or b"")
    subject = headers.get("subject") or "(no subject)"
    from_people = people_from_header(headers.get("from", ""))
    to = people_from_header(headers.get("to", ""))
    cc = people_from_header(headers.get("cc", ""))
    from_name, from_email = from_people[0] if from_people else ("", "")
    me = str(account.get("email") or "")
    mine = bool(from_email) and from_email.lower() == me.lower()
    when = headers.get("date") or item.get("internaldate") or ""
    when_ts = message_timestamp(item.get("internaldate") or "") or message_timestamp(when)
    message_id = headers.get("message-id", "").strip()
    ids = header_ids(headers)
    return {
        "account_id": account["id"],
        "mailbox": mailbox,
        "uid": uid,
        "unread": bool(item.get("unread")),
        "subject": subject,
        "when": when,
        "when_ts": when_ts,
        "from_name": from_name,
        "from_email": from_email,
        "account_email": me,
        "to": to,
        "cc": cc,
        "mine": mine,
        "key": thread_key(headers, subject),
        "message_id": message_id,
        "ids": ids,
    }


def find_root(parent: list[int], i: int) -> int:
    while parent[i] != i:
        parent[i] = parent[parent[i]]
        i = parent[i]
    return i


def union_root(parent: list[int], a: int, b: int) -> None:
    ra, rb = find_root(parent, a), find_root(parent, b)
    if ra != rb:
        parent[rb] = ra


def group_rows(rows: list[dict[str, Any]], viewed: str) -> list[dict[str, Any]]:
    if not rows:
        return []
    parent = list(range(len(rows)))
    id_owner: dict[str, int] = {}
    subj_owner: dict[str, int] = {}
    for i, row in enumerate(rows):
        if not row["ids"]:
            subj = f"{row['account_id']}:subj:{normalize_subject(row['subject'])}"
            if subj in subj_owner:
                union_root(parent, i, subj_owner[subj])
            else:
                subj_owner[subj] = i
            continue
        for ident in row["ids"]:
            key = f"{row['account_id']}:{ident.lower()}"
            if key in id_owner:
                union_root(parent, i, id_owner[key])
            else:
                id_owner[key] = i
    order: list[int] = []
    groups: dict[int, list[dict[str, Any]]] = {}
    for i, row in enumerate(rows):
        root = find_root(parent, i)
        if root not in groups:
            order.append(root)
        groups.setdefault(root, []).append(row)
    conversations = []
    for key in order:
        items = groups.get(key) or []
        if not any(item["mailbox"] == viewed for item in items):
            continue
        items.sort(key=lambda a: ((a["mailbox"] != viewed), a["when_ts"]))
        unique = []
        seen_ids: set[str] = set()
        for item in items:
            if item["message_id"] and item["message_id"] in seen_ids:
                continue
            if item["message_id"]:
                seen_ids.add(item["message_id"])
            unique.append(item)
        unique.sort(key=lambda a: a["when_ts"])
        if not unique:
            continue
        latest = unique[-1]
        participants: list[dict[str, Any]] = []

        def push_person(name: str, email: str, mine: bool) -> None:
            email = email.strip()
            label = "You" if mine else (name.strip() or email)
            if not label:
                return
            for p in participants:
                if email and p["email"] and p["email"].lower() == email.lower():
                    return
                if not email and p["name"] == label:
                    return
            participants.append({"name": label, "email": email, "mine": mine})

        uids = []
        locations = []
        unread = False
        for item in unique:
            uids.append(item["uid"])
            locations.append({"mailbox": item["mailbox"], "uid": item["uid"]})
            if item["mailbox"] == viewed:
                unread = unread or item["unread"]
            push_person(item["from_name"], item["from_email"], item["mine"])
            if viewed in ("sent", "drafts"):
                for name, email in item["to"] + item["cc"]:
                    if item["account_email"] and email.lower() == item["account_email"].lower():
                        continue
                    push_person(name, email, False)
        to: list[dict[str, Any]] = []
        src = next((item for item in reversed(unique) if item["mailbox"] == viewed), unique[-1])
        for name, email in src["to"] + src["cc"]:
            email = email.strip()
            if not email or any(p["email"].lower() == email.lower() for p in to):
                continue
            label = name.strip() if name.strip() and name.lower() != email.lower() else email
            to.append({"name": label, "email": email, "mine": False})
        preview = next((p["name"] for p in participants if not p["mine"] and p["name"]), "")
        if not preview:
            preview = "You" if latest["mine"] else latest["from_name"]
        dated = [item for item in unique if item["message_id"]]
        if dated:
            thread_id = min(dated, key=lambda item: item["when_ts"])["message_id"]
        else:
            thread_id = f"subj:{normalize_subject(latest['subject'])}"
        conversations.append(
            {
                "id": f"{latest['account_id']}:{thread_id}",
                "accountId": latest["account_id"],
                "mailbox": viewed,
                "unread": unread,
                "subject": latest["subject"],
                "preview": preview,
                "when": latest["when"],
                "participants": participants,
                "to": to,
                "uids": uids,
                "items": locations,
                "messages": [],
                "latestMine": latest["mine"],
            }
        )
    conversations.sort(key=lambda c: message_timestamp(c["when"]), reverse=True)
    return conversations


def collect_contacts(accounts: list[dict[str, Any]], rows: list[dict[str, Any]]) -> list[dict[str, str]]:
    mine = {str(a.get("email") or "").lower() for a in accounts}
    sorted_rows = sorted(rows, key=lambda r: r["when_ts"], reverse=True)
    seen: set[str] = set()
    out: list[dict[str, str]] = []

    def add(name: str, email: str) -> None:
        email = email.strip()
        if not email or not looks_like_email(email):
            return
        key = email.lower()
        if key in mine or key in seen:
            return
        seen.add(key)
        label = name.strip()
        if not label or label.lower() == email.lower():
            label = email
        out.append({"name": label, "email": email})

    for row in sorted_rows:
        if row["mailbox"] == "sent":
            for name, email in row["to"] + row["cc"]:
                add(name, email)
        else:
            add(row["from_name"], row["from_email"])
    return out[:400]


def load_account_cache(account_id: str, mailbox: str) -> dict[str, Any] | None:
    path = cache_path(account_id, mailbox)
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def save_account_cache(account_id: str, mailbox: str, cache: dict[str, Any]) -> None:
    path = cache_path(account_id, mailbox)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cache))


def load_list_cache(accounts: list[dict[str, Any]], mailbox: str):
    unread = 0
    conversations = []
    contacts = []
    any_cache = False
    for account in accounts:
        cache = load_account_cache(account["id"], mailbox)
        if not cache:
            continue
        any_cache = True
        unread += int(cache.get("unread") or 0)
        conversations.extend(cache.get("conversations") or [])
        contacts.extend(cache.get("contacts") or [])
    if not any_cache:
        return None
    conversations.sort(key=lambda c: message_timestamp(c.get("when") or ""), reverse=True)
    return unread, conversations, contacts


def save_list_cache(conversations: list[dict[str, Any]], contacts: list[dict[str, str]], unread: int, mailbox: str) -> None:
    by_account: dict[str, dict[str, Any]] = {}
    for conv in conversations:
        aid = conv.get("accountId") or ""
        entry = by_account.setdefault(aid, {"unread": 0, "conversations": [], "contacts": []})
        row = dict(conv)
        row["messages"] = []
        entry["conversations"].append(row)
    if by_account:
        first = next(iter(by_account.values()))
        first["contacts"] = list(contacts)
    for entry in by_account.values():
        entry["unread"] = unread
    for account_id, cache in by_account.items():
        save_account_cache(account_id, mailbox, cache)


# --- MIME messages -----------------------------------------------------------


def leaf_parts(msg) -> list[Any]:
    if msg.is_multipart():
        out = []
        for part in msg.get_payload():
            out.extend(leaf_parts(part))
        return out
    return [msg]


def part_is_file(part) -> bool:
    mime = (part.get_content_type() or "").lower()
    if mime.startswith("multipart/"):
        return False
    disp = (part.get_content_disposition() or "").lower()
    if disp == "attachment":
        return True
    filename = part.get_filename()
    if filename:
        return True
    if part.get_param("name") and not mime.startswith("text/plain") and not mime.startswith("text/html"):
        return True
    return not mime.startswith("text/plain") and not mime.startswith("text/html")


def safe_filename(name: str) -> str:
    base = re.split(r"[\\/]", name)[-1].strip().strip(".")
    cleaned = "".join(c if c.isalnum() or c in ".-_ " else "_" for c in base).strip().strip(".")
    if not cleaned:
        return "attachment"
    return cleaned[:80]


def part_filename(part, index: int) -> str:
    name = part.get_filename() or part.get_param("name") or ""
    if str(name).strip():
        return safe_filename(str(name))
    mime = (part.get_content_type() or "").lower()
    return f"part-{index}{MIME_EXT.get(mime, '')}"


def collect_attachments(msg) -> list[dict[str, Any]]:
    out = []
    for index, part in enumerate(leaf_parts(msg)):
        if not part_is_file(part):
            continue
        payload = part.get_payload(decode=True) or b""
        out.append(
            {
                "index": index,
                "name": part_filename(part, index),
                "mime": (part.get_content_type() or "").lower(),
                "size": len(payload),
            }
        )
    return out


def extract_part(msg, index: int) -> tuple[str, str, bytes]:
    leaves = leaf_parts(msg)
    if index < 0 or index >= len(leaves):
        raise Error("no such attachment")
    part = leaves[index]
    if not part_is_file(part):
        raise Error("not an attachment")
    return part_filename(part, index), (part.get_content_type() or "").lower(), part.get_payload(decode=True) or b""


def decode_part_text(part) -> str:
    payload = part.get_payload(decode=True) or b""
    charset = part.get_content_charset() or "utf-8"
    try:
        return payload.decode(charset, "replace")
    except LookupError:
        return payload.decode("utf-8", "replace")


def part_text(msg) -> tuple[str, bool]:
    if part_is_file(msg):
        return "", False
    ctype = (msg.get_content_type() or "").lower()
    if ctype.startswith("text/plain"):
        return decode_part_text(msg), False
    if ctype.startswith("text/html"):
        return decode_part_text(msg), True
    if msg.is_multipart():
        for sub in msg.get_payload():
            text, html = part_text(sub)
            if text.strip():
                return text, html
    return "", False


def parse_message(
    account: dict[str, Any], mailbox: str, uid: int, raw: bytes, unread: bool = False
) -> dict[str, Any]:
    msg = BytesParser(policy=policy.default).parsebytes(raw)
    from_header = str(msg.get("From") or "")
    from_name, from_email = parse_from(from_header)
    if from_header:
        people = people_from_header(from_header)
        if people:
            from_name, from_email = people[0]
    when = str(msg.get("Date") or "")
    body, is_html = part_text(msg)
    text = html_to_text(body) if is_html else body
    me = str(account.get("email") or "")
    mine = bool(from_email) and from_email.lower() == me.lower()
    return {
        "id": f"{mailbox}:{uid}",
        "uid": uid,
        "mailbox": mailbox,
        "from": "You" if mine else (from_name or from_email),
        "fromEmail": from_email,
        "mine": mine,
        "when": when,
        "messageId": str(msg.get("Message-ID") or ""),
        "inReplyTo": str(msg.get("In-Reply-To") or ""),
        "references": str(msg.get("References") or ""),
        "to": parse_address_list(str(msg.get("To") or ""), me),
        "cc": parse_address_list(str(msg.get("Cc") or ""), me),
        "bcc": parse_address_list(str(msg.get("Bcc") or ""), me),
        "text": text,
        "blocks": text_to_blocks(text),
        "attachments": collect_attachments(msg),
        "unread": bool(unread),
    }


def unique_path(directory: Path, name: str) -> Path:
    name = safe_filename(name)
    path = directory / name
    if not path.exists():
        return path
    stem = path.stem
    ext = path.suffix
    for n in range(1, 1000):
        candidate = directory / f"{stem}-{n}{ext}"
        if not candidate.exists():
            return candidate
    return directory / f"{stem}-dup{ext}"


def mime_from_path(path: Path) -> str:
    ext = path.suffix.lower().lstrip(".")
    return MIME_FROM_EXT.get(ext, "application/octet-stream")


def ensure_msg_id(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    return value if value.startswith("<") else f"<{value}>"


def new_message_id(email: str) -> str:
    domain = email.split("@")[-1] if "@" in email else "localhost"
    return f"<{time.time_ns()}.omarchy-mail@{domain}>"


def mailbox_header(name: str, email: str) -> str:
    name = name.strip()
    if not name or name.lower() == email.lower():
        return email
    return f"{name} <{email}>"


def build_outgoing(
    account: dict[str, Any],
    req: dict[str, Any],
    to: list[tuple[str, str]],
    cc: list[tuple[str, str]],
    bcc: list[tuple[str, str]],
    allow_empty: bool,
    keep_bcc: bool,
) -> EmailMessage:
    from_name = str(account.get("fromName") or "").strip() or str(account.get("name") or "")
    msg = EmailMessage()
    msg["From"] = mailbox_header(from_name, str(account.get("email") or ""))
    msg["Subject"] = str(req.get("subject") or "").strip()
    msg["Message-ID"] = new_message_id(str(account.get("email") or ""))
    msg["User-Agent"] = "Omarchy Mail"
    msg["Date"] = formatdate(localtime=True)
    if not to and not cc and not bcc:
        if not allow_empty:
            raise Error("no recipients")
    else:
        if to:
            msg["To"] = ", ".join(mailbox_header(n, e) for n, e in to)
        if cc:
            msg["Cc"] = ", ".join(mailbox_header(n, e) for n, e in cc)
        if bcc and keep_bcc:
            msg["Bcc"] = ", ".join(mailbox_header(n, e) for n, e in bcc)
    in_reply = ensure_msg_id(str(req.get("inReplyTo") or ""))
    if in_reply:
        msg["In-Reply-To"] = in_reply
    refs = [ensure_msg_id(tok) for tok in str(req.get("references") or "").split() if ensure_msg_id(tok)]
    if refs:
        msg["References"] = " ".join(refs)
    body = str(req.get("body") or "")
    files = list(req.get("files") or [])
    msg.set_content(body or "")
    for raw in files:
        path = Path(raw)
        if not path.is_file():
            raise Error(f"missing attachment {path}")
        data = path.read_bytes()
        maintype, _, subtype = mime_from_path(path).partition("/")
        msg.add_attachment(
            data,
            maintype=maintype or "application",
            subtype=subtype or "octet-stream",
            filename=path.name,
        )
    return msg


def smtp_send(account: dict[str, Any], password: str, msg: EmailMessage, bcc: list[tuple[str, str]]) -> None:
    if not account.get("smtpTls", True):
        raise Error("SMTP without TLS is not supported yet")
    try:
        port = int(str(account.get("smtpPort") or "465"))
    except ValueError as exc:
        raise Error("invalid SMTP port") from exc
    host = str(account.get("smtpHost") or "")
    user = str(account.get("username") or "")
    ctx = ssl.create_default_context()
    recipients = []
    for header in ("To", "Cc"):
        if msg.get(header):
            recipients.extend(addr for _n, addr in getaddresses([msg.get(header)]))
    recipients.extend(email for _n, email in bcc)
    if not recipients:
        recipients = [str(account.get("email") or "")]
    try:
        if port == 587:
            with smtplib_smtp(host, port) as smtp:
                smtp.starttls(context=ctx)
                smtp.login(user, password)
                smtp.send_message(msg, to_addrs=recipients)
        else:
            with smtplib_smtp_ssl(host, port, context=ctx) as smtp:
                smtp.login(user, password)
                smtp.send_message(msg, to_addrs=recipients)
    except Exception as exc:
        raise Error(f"SMTP: {exc}") from exc


def smtplib_smtp(host: str, port: int):
    import smtplib

    return smtplib.SMTP(host, port)


def smtplib_smtp_ssl(host: str, port: int, context: ssl.SSLContext):
    import smtplib

    return smtplib.SMTP_SSL(host, port, context=context)


def open_path(path: Path) -> None:
    subprocess.Popen(
        ["xdg-open", str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


# --- session / commands ------------------------------------------------------


class State:
    def __init__(self, path: str):
        self.config_path = path
        self.accounts = load_accounts(path)
        self.sessions: dict[str, tuple[dict[str, Any], str, IMAP4]] = {}

    def account(self, account_id: str) -> dict[str, Any]:
        for acc in self.accounts:
            if acc.get("id") == account_id:
                return acc
        raise Error(f"unknown account {account_id}")

    def selected_accounts(self, account_id: str) -> list[dict[str, Any]]:
        if not account_id or account_id == "all":
            if not self.accounts:
                raise Error("no accounts")
            return list(self.accounts)
        return [self.account(account_id)]

    def drop_session(self, account_id: str) -> None:
        entry = self.sessions.pop(account_id, None)
        if entry:
            try:
                entry[2].logout()
            except Exception:
                try:
                    entry[2].shutdown()
                except Exception:
                    pass

    def password(self, account_id: str) -> str:
        if account_id in self.sessions and self.sessions[account_id][1]:
            return self.sessions[account_id][1]
        return lookup_password(account_id)

    def with_session(self, account_id: str, fn):
        account = self.account(account_id)
        last = None
        for _attempt in range(2):
            try:
                if account_id not in self.sessions:
                    password = lookup_password(account_id)
                    imap = connect(account, password)
                    self.sessions[account_id] = (account, password, imap)
                _account, _password, imap = self.sessions[account_id]
                return fn(account, imap)
            except Exception as exc:
                last = exc
                self.drop_session(account_id)
        raise last


def request_account_id(state: State, req: dict[str, Any]) -> str:
    account = str(req.get("account") or "")
    if not account or account == "all":
        if not state.accounts:
            raise Error("no accounts")
        return str(state.accounts[0]["id"])
    return account


def request_mailbox_role(req: dict[str, Any]) -> str:
    return str(req.get("mailbox") or "inbox") or "inbox"


def request_uids(req: dict[str, Any], from_role: str) -> list[int]:
    items = req.get("items") or []
    uids: list[int] = []
    if items:
        for item in items:
            role = str(item.get("mailbox") or from_role)
            if role == from_role or not item.get("mailbox"):
                uids.append(int(item.get("uid") or 0))
    uids.extend(int(u) for u in (req.get("uids") or []) if u)
    if not uids and req.get("uid"):
        uids.append(int(req["uid"]))
    uids = [u for u in uids if u]
    return sorted(set(uids))


def fetch_locations(req: dict[str, Any]) -> list[dict[str, Any]]:
    items = req.get("items") or []
    if items:
        return list(items)
    mailbox = str(req.get("mailbox") or "inbox")
    uids = list(req.get("uids") or [])
    if not uids and req.get("uid"):
        uids.append(int(req["uid"]))
    return [{"mailbox": mailbox, "uid": int(u)} for u in uids]


def uids_still_present(imap: IMAP4, uids: list[int]) -> list[int]:
    if not uids:
        return []
    found = set(uid_search(imap, "UID " + ",".join(str(u) for u in uids)))
    return [u for u in uids if u in found]


def delete_uids(imap: IMAP4, mailbox: str, uids: list[int]) -> None:
    if not uids:
        return
    imap.select(mailbox)
    remaining = uids_still_present(imap, uids)
    if not remaining:
        return
    uid_set = ",".join(str(u) for u in remaining)
    imap.uid("STORE", uid_set, "+FLAGS", r"(\Deleted)")
    try:
        imap.uid("EXPUNGE", uid_set)
    except Exception:
        imap.expunge()


def mark_seen(imap: IMAP4, mailbox: str, uids: list[int], seen: bool) -> None:
    if not uids:
        return
    imap.select(mailbox)
    remaining = uids_still_present(imap, uids)
    if not remaining:
        return
    uid_set = ",".join(str(u) for u in remaining)
    flags = r"+FLAGS (\Seen)" if seen else r"-FLAGS (\Seen)"
    imap.uid("STORE", uid_set, flags.split()[0], " ".join(flags.split()[1:]))


def move_uids(imap: IMAP4, src: str, dest: str, uids: list[int]) -> None:
    imap.select(src)
    remaining = uids_still_present(imap, uids)
    if not remaining:
        return
    uid_set = ",".join(str(u) for u in remaining)
    try:
        typ, _ = imap.uid("MOVE", uid_set, dest)
        if typ == "OK":
            leftover = uids_still_present(imap, remaining)
            if not leftover:
                return
            remaining = leftover
            uid_set = ",".join(str(u) for u in remaining)
    except Exception:
        pass
    imap.uid("COPY", uid_set, dest)
    delete_uids(imap, src, remaining)
    leftover = uids_still_present(imap, remaining)
    if leftover:
        raise Error("couldn't move messages")


def list_mailbox(account: dict[str, Any], imap: IMAP4, role: str, limit: int, query: str, body_fallback: bool):
    mailbox = resolve_mailbox(imap, role)
    exists = exists_count(imap, mailbox)
    unread = unseen_count(imap)
    spec, use_uid = query_set(imap, exists, limit, query, body_fallback)
    if not spec:
        return unread, []
    items = imap_fetch(imap, spec, FETCH_HEADERS, use_uid)
    rows = []
    for item in items:
        row = fetch_to_row(account, role, item)
        if row:
            rows.append(row)
    return unread, rows


def list_account(account: dict[str, Any], imap: IMAP4, role: str, limit: int, query: str):
    unread, rows = list_mailbox(account, imap, role, limit, query, True)
    extra = None
    if role in ("inbox", "archive", "trash"):
        extra = "sent"
    elif role == "sent":
        extra = "inbox"
    if extra:
        try:
            _n, extra_rows = list_mailbox(account, imap, extra, max(limit, 100), query, False)
            rows.extend(extra_rows)
        except Exception:
            pass
    return unread, rows


def list_cmd(state: State, req: dict[str, Any]) -> dict[str, Any]:
    accounts = state.selected_accounts(str(req.get("account") or ""))
    mailbox = str(req.get("mailbox") or "inbox") or "inbox"
    limit = int(req.get("limit") or PAGE)
    query = str(req.get("query") or "")
    unread = 0
    rows: list[dict[str, Any]] = []
    for acc in accounts:
        count, part = state.with_session(acc["id"], lambda account, imap: list_account(account, imap, mailbox, limit, query))
        unread += count
        rows.extend(part)
    contacts = collect_contacts(accounts, rows)
    conversations = group_rows(rows, mailbox)
    if len(conversations) > limit:
        conversations = conversations[:limit]
    if not query.strip():
        save_list_cache(conversations, contacts, unread, mailbox)
    return {
        "id": req["id"],
        "ok": True,
        "cached": False,
        "unread": unread,
        "conversations": conversations,
        "contacts": contacts,
    }


def list_responses(state: State, req: dict[str, Any]) -> list[dict[str, Any]]:
    mailbox = str(req.get("mailbox") or "inbox") or "inbox"
    out: list[dict[str, Any]] = []
    if req.get("useCache", True) and not str(req.get("query") or "").strip():
        try:
            accounts = state.selected_accounts(str(req.get("account") or ""))
        except Error:
            accounts = []
        cached = load_list_cache(accounts, mailbox) if accounts else None
        if cached:
            unread, conversations, contacts = cached
            out.append(
                {
                    "id": req["id"],
                    "ok": True,
                    "cached": True,
                    "unread": unread,
                    "conversations": conversations,
                    "contacts": contacts,
                }
            )
    try:
        out.append(list_cmd(state, req))
    except Exception as exc:
        if not out:
            out.append({"id": req["id"], "ok": False, "error": str(exc)})
    return out


def fetch_cmd(state: State, req: dict[str, Any]) -> dict[str, Any]:
    account_id = str(req.get("account") or "")
    locations = fetch_locations(req)
    if not locations:
        raise Error("no uids")
    grouped: dict[str, list[int]] = {}
    for item in locations:
        role = str(item.get("mailbox") or "inbox") or "inbox"
        grouped.setdefault(role, []).append(int(item.get("uid") or 0))
    viewed = str(req.get("mailbox") or "inbox") or "inbox"

    def work(account, imap):
        messages = []
        seen_sets = []
        for role, uids in grouped.items():
            uids = sorted({u for u in uids if u})
            try:
                mailbox = resolve_mailbox(imap, role)
                imap.select(mailbox)
            except Exception:
                continue
            uid_set = ",".join(str(u) for u in uids)
            items = imap_fetch(imap, uid_set, FETCH_BODY, True)
            if not items:
                items = imap_fetch(imap, uid_set, "(FLAGS RFC822)", True)
            for item in items:
                body = item.get("body") or b""
                if body:
                    messages.append(
                        parse_message(
                            account, role, item["uid"], body, bool(item.get("unread"))
                        )
                    )
            if role == viewed:
                seen_sets.append((mailbox, uids))
        for mailbox, uids in seen_sets:
            try:
                mark_seen(imap, mailbox, uids, True)
            except Exception:
                pass
        if not messages:
            raise Error("couldn't fetch messages")
        messages.sort(key=lambda m: message_timestamp(m.get("when") or ""))
        return messages

    messages = state.with_session(account_id, work)
    return {"id": req["id"], "ok": True, "messages": messages}


def seen_cmd(state: State, req: dict[str, Any]) -> dict[str, Any]:
    account_id = request_account_id(state, req)
    role = request_mailbox_role(req)
    uids = request_uids(req, role)
    if not uids:
        raise Error("no uids")
    seen = not bool(req.get("unseen"))

    def work(_account, imap):
        mailbox = resolve_mailbox(imap, role)
        mark_seen(imap, mailbox, uids, seen)

    state.with_session(account_id, work)
    return {"id": req["id"], "ok": True}


def move_cmd(state: State, req: dict[str, Any]) -> dict[str, Any]:
    account_id = request_account_id(state, req)
    from_role = request_mailbox_role(req)
    to_role = str(req.get("to") or "")
    if not to_role:
        raise Error("missing destination")
    uids = request_uids(req, from_role)
    if not uids:
        raise Error("no uids")

    def work(_account, imap):
        src = resolve_mailbox(imap, from_role)
        dest = resolve_mailbox(imap, to_role)
        move_uids(imap, src, dest, uids)

    state.with_session(account_id, work)
    return {"id": req["id"], "ok": True}


def delete_cmd(state: State, req: dict[str, Any]) -> dict[str, Any]:
    account_id = request_account_id(state, req)
    role = request_mailbox_role(req)
    uids = request_uids(req, role)
    if not uids:
        raise Error("no uids")

    def work(_account, imap):
        mailbox = resolve_mailbox(imap, role)
        delete_uids(imap, mailbox, uids)
        imap.select(mailbox)
        leftover = uids_still_present(imap, uids)
        if leftover:
            raise Error("couldn't delete messages")

    state.with_session(account_id, work)
    return {"id": req["id"], "ok": True}


def append_raw(imap: IMAP4, mailbox: str, flags: str, raw: bytes) -> None:
    imap.append(mailbox, flags, None, raw)


def send_cmd(state: State, req: dict[str, Any]) -> dict[str, Any]:
    account_id = request_account_id(state, req)
    account = state.account(account_id)
    to = parse_recipients(list(req.get("toList") or []))
    cc = parse_recipient_list(list(req.get("ccList") or []), False)
    bcc = parse_recipient_list(list(req.get("bccList") or []), False)
    if not to and not cc and not bcc:
        raise Error("no recipients")
    password = state.password(account_id)
    email_msg = build_outgoing(account, req, to, cc, bcc, False, False)
    smtp_send(account, password, email_msg, bcc)
    raw = email_msg.as_bytes()
    replace_drafts = str(req.get("mailbox") or "") == "drafts"
    replace_uids = [int(u) for u in (req.get("uids") or []) if u]
    saved = True
    try:
        def work(_account, imap):
            sent = resolve_mailbox(imap, "sent")
            append_raw(imap, sent, r"(\Seen)", raw)
            if replace_drafts and replace_uids:
                drafts = resolve_mailbox(imap, "drafts")
                delete_uids(imap, drafts, replace_uids)

        state.with_session(account_id, work)
    except Exception:
        saved = False
    return {"id": req["id"], "ok": True, "saved": saved}


def draft_cmd(state: State, req: dict[str, Any]) -> dict[str, Any]:
    account_id = request_account_id(state, req)
    account = state.account(account_id)
    to = parse_recipient_list(list(req.get("toList") or []), False)
    cc = parse_recipient_list(list(req.get("ccList") or []), False)
    bcc = parse_recipient_list(list(req.get("bccList") or []), False)
    if (
        not to
        and not cc
        and not bcc
        and not str(req.get("subject") or "").strip()
        and not str(req.get("body") or "").strip()
        and not (req.get("files") or [])
    ):
        raise Error("nothing to save")
    email_msg = build_outgoing(account, req, to, cc, bcc, True, True)
    raw = email_msg.as_bytes()
    replace_uids = [int(u) for u in (req.get("uids") or []) if u]

    def work(_account, imap):
        drafts = resolve_mailbox(imap, "drafts")
        append_raw(imap, drafts, r"(\Seen \Draft)", raw)
        if replace_uids:
            delete_uids(imap, drafts, replace_uids)

    state.with_session(account_id, work)
    return {"id": req["id"], "ok": True}


def status_cmd(state: State, req: dict[str, Any]) -> dict[str, Any]:
    accounts = state.selected_accounts(str(req.get("account") or ""))
    unread = 0
    for acc in accounts:
        unread += state.with_session(acc["id"], lambda _a, imap: (imap.select("INBOX"), unseen_count(imap))[1])
    return {"id": req["id"], "ok": True, "unread": unread}


def attachment_cmd(state: State, req: dict[str, Any]) -> dict[str, Any]:
    account_id = request_account_id(state, req)
    role = request_mailbox_role(req)
    uid = int(req.get("uid") or 0) or (int((req.get("uids") or [0])[0]) if req.get("uids") else 0)
    if not uid:
        raise Error("no uid")
    action = str(req.get("action") or "").strip().lower()
    index = int(req.get("index") or 0)

    def work(_account, imap):
        mailbox = resolve_mailbox(imap, role)
        imap.select(mailbox)
        items = imap_fetch(imap, str(uid), FETCH_BODY, True)
        if not items:
            items = imap_fetch(imap, str(uid), "(RFC822)", True)
        raw = next((item.get("body") for item in items if item.get("body")), b"")
        if not raw:
            raise Error("couldn't fetch message")
        msg = BytesParser(policy=policy.default).parsebytes(raw)
        return extract_part(msg, index)

    name, _mime, data = state.with_session(account_id, work)
    dest_dir = download_dir() if action == "save" else open_cache_dir()
    dest = unique_path(dest_dir, name)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    if action not in ("save", "extract"):
        open_path(dest)
    return {
        "id": req["id"],
        "ok": True,
        "path": str(dest),
        "name": name,
        "saved": action == "save",
        "action": action,
    }


def handle(state: State, req: dict[str, Any]) -> list[dict[str, Any]]:
    cmd = str(req.get("cmd") or "")
    rid = req.get("id") or ""
    try:
        if cmd == "ping":
            return [{"id": rid, "ok": True, "accounts": len(state.accounts)}]
        if cmd in ("list", "search"):
            return list_responses(state, req)
        if cmd == "fetch":
            return [fetch_cmd(state, req)]
        if cmd == "seen":
            return [seen_cmd(state, req)]
        if cmd == "move":
            return [move_cmd(state, req)]
        if cmd == "delete":
            return [delete_cmd(state, req)]
        if cmd == "send":
            return [send_cmd(state, req)]
        if cmd == "draft":
            return [draft_cmd(state, req)]
        if cmd == "status":
            return [status_cmd(state, req)]
        if cmd == "attachment":
            return [attachment_cmd(state, req)]
        return [{"id": rid, "ok": False, "error": f"unknown cmd {cmd}"}]
    except Exception as exc:
        return [{"id": rid, "ok": False, "error": str(exc)}]


def idle_account(account: dict[str, Any], events: queue.Queue, stop: threading.Event) -> None:
    while not stop.is_set():
        try:
            password = lookup_password(account["id"])
        except Exception:
            stop.wait(20)
            continue
        try:
            imap = connect(account, password)
            imap.select("INBOX")
        except Exception:
            stop.wait(15)
            continue
        try:
            while not stop.is_set():
                try:
                    with imap.idle(duration=25 * 60) as idler:
                        for _typ, _data in idler:
                            if stop.is_set():
                                return
                            events.put("exists")
                            break
                except Exception:
                    break
        finally:
            try:
                imap.logout()
            except Exception:
                pass
        stop.wait(5)


def write_json(lock: threading.Lock, value: dict[str, Any]) -> None:
    line = json.dumps(value, ensure_ascii=False)
    with lock:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def main() -> None:
    path = config_path()
    try:
        state = State(path)
    except Error as exc:
        sys.stderr.write(json.dumps({"id": "", "ok": False, "error": str(exc)}) + "\n")
        sys.exit(1)
    events: queue.Queue = queue.Queue()
    stop = threading.Event()
    out_lock = threading.Lock()

    def read_stdin():
        for line in sys.stdin:
            events.put(("line", line))
        events.put(("line", None))

    threading.Thread(target=read_stdin, daemon=True).start()
    for account in state.accounts:
        threading.Thread(target=idle_account, args=(account, events, stop), daemon=True).start()
    while True:
        item = events.get()
        if item == "exists":
            write_json(out_lock, {"id": "", "ok": True, "event": "exists"})
            continue
        kind, line = item
        if line is None:
            break
        text = line.strip()
        if not text:
            continue
        try:
            req = json.loads(text)
        except json.JSONDecodeError as exc:
            write_json(out_lock, {"id": "", "ok": False, "error": f"bad request: {exc}"})
            continue
        if str(req.get("cmd") or "") == "shutdown":
            write_json(out_lock, {"id": req.get("id") or "", "ok": True})
            break
        for response in handle(state, req):
            write_json(out_lock, response)
    stop.set()


def run_tests() -> int:
    import unittest

    suite = unittest.defaultTestLoader.discover(
        str(Path(__file__).resolve().parent.parent / "tests"),
        pattern="test_*.py",
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    if "--test" in sys.argv:
        raise SystemExit(run_tests())
    main()
