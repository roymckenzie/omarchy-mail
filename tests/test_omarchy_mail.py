import os
import sys
import tempfile
import unittest
from email.message import EmailMessage
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bin"))
import omarchy_mail as mail


def row(**kw):
    item = {
        "account_id": "acct1",
        "mailbox": "inbox",
        "uid": 1,
        "unread": False,
        "subject": "Hello",
        "when": "Sat, 22 Aug 2026 20:16:05 -0600",
        "when_ts": 1000,
        "from_name": "Maya Chen",
        "from_email": "maya@example.com",
        "account_email": "you@example.com",
        "to": [("You", "you@example.com")],
        "cc": [],
        "mine": False,
        "key": "",
        "message_id": "<a@example.com>",
        "ids": ["<a@example.com>"],
    }
    item.update(kw)
    return item


class TestDecodeAndHtml(unittest.TestCase):
    def test_rfc2047_q_word(self):
        self.assertEqual(mail.decode_mime_words("=?UTF-8?Q?hello_there?="), "hello there")

    def test_rfc2047_b_word(self):
        encoded = "=?utf-8?B?TG9yZW0gaXBzdW0gZG9sb3Igc2l0IGFtZXQsIGNvbnNlY3RldHVyIGFkaXBpc2NpbmcgZWxpdC4gVXQgaW50ZXJkdW0gcXVhbSBldSBmYWNpbGlzaXMgb3JuYXJlLg==?="
        self.assertEqual(
            mail.decode_mime_words(encoded),
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut interdum quam eu facilisis ornare.",
        )

    def test_rfc2047_split_q_subject(self):
        encoded = "=?UTF-8?Q?Fwd:_Meeting_records:_=E2=80=9COnline_Givehub_Meeting_?= =?UTF-8?Q?with_Debbie_Churchill=E2=80=9D,_Aug_19,_2026?="
        self.assertEqual(
            mail.decode_mime_words(encoded),
            "Fwd: Meeting records: “Online Givehub Meeting with Debbie Churchill”, Aug 19, 2026",
        )

    def test_rfc2047_split_in_the_middle(self):
        encoded = "=?UTF-8?Q?Fwd:_Meeting_records:_=E2=80=9COnline_Givehub_Meeting_=?= =?UTF-8?Q?bie_Churchill=29=E2=80=9D,_Aug_19=2C_2026?="
        got = mail.decode_mime_words(encoded)
        self.assertNotIn("=?UTF-8", got)
        self.assertIn("Givehub", got)
        self.assertIn("Churchill", got)

    def test_decode_bytes_strips_quotes(self):
        self.assertEqual(mail.decode_bytes(b'"=?UTF-8?Q?Hello_world?="'), "Hello world")

    def test_html_entities(self):
        self.assertEqual(mail.unescape("A&nbsp;B&amp;C"), "A B&C")
        self.assertEqual(mail.html_to_text("<p>join&zwnj;ed</p>").replace("\n", ""), "joined")

    def test_blockquote_is_quote_not_history(self):
        html = "<p>My reply.</p><blockquote>Earlier message from Kyle</blockquote>"
        blocks = mail.text_to_blocks(mail.html_to_text(html))
        self.assertTrue(any(b["type"] == "p" and "My reply" in b["text"] for b in blocks))
        quote = next(b for b in blocks if b["type"] == "quote")
        self.assertIn("Earlier message from Kyle", quote["text"])
        self.assertTrue(all(b["type"] != "history" for b in blocks))

    def test_quoted_reply_is_history(self):
        text = (
            "Sounds good.\n\n"
            "> On Tue, Aug 19, 2026 at 3:07 PM K Salone wrote:\n"
            "> Hello everyone\n"
            "> Please find the notes below.\n"
            "> More of the previous email keeps going."
        )
        blocks = mail.text_to_blocks(text)
        self.assertTrue(any(b["type"] == "p" and "Sounds good" in b["text"] for b in blocks))
        self.assertTrue(any(b["type"] == "history" and "Hello everyone" in b["text"] for b in blocks))

    def test_addresses(self):
        self.assertEqual(
            mail.parse_addr_token("Ada Lovelace <ada@example.com>"),
            ("Ada Lovelace", "ada@example.com"),
        )
        self.assertEqual(mail.parse_addr_token("ada@example.com"), ("", "ada@example.com"))
        self.assertTrue(mail.looks_like_email("ada@example.com"))
        self.assertFalse(mail.looks_like_email("not-an-address"))
        got = mail.parse_recipients(["Ada <ada@example.com>, bob@site.org"])
        self.assertEqual(len(got), 2)
        self.assertEqual(got[1][1], "bob@site.org")
        draft = mail.parse_recipient_list(["ada@example.com, not-an-address"], False)
        self.assertEqual(draft, [("", "ada@example.com")])
        self.assertEqual(mail.parse_recipient_list([""], False), [])


class TestThreading(unittest.TestCase):
    def test_reply_joins_parent_by_in_reply_to(self):
        parent = row(
            uid=1,
            message_id="<a@example.com>",
            ids=["<a@example.com>"],
            when_ts=1,
            subject="Hello",
        )
        reply = row(
            uid=2,
            message_id="<b@example.com>",
            ids=["<b@example.com>", "<a@example.com>"],
            subject="Re: Hello",
            when_ts=2,
            from_name="You",
            from_email="you@example.com",
            mine=True,
        )
        convs = mail.group_rows([parent, reply], "inbox")
        self.assertEqual(len(convs), 1)
        self.assertEqual(convs[0]["uids"], [1, 2])
        self.assertEqual(convs[0]["id"], "acct1:<a@example.com>")
        names = [p["name"] for p in convs[0]["participants"]]
        self.assertIn("Maya Chen", names)
        self.assertIn("You", names)

    def test_unrelated_ids_stay_apart(self):
        a = row(uid=1, message_id="<a@example.com>", ids=["<a@example.com>"], subject="One")
        b = row(
            uid=2,
            message_id="<b@example.com>",
            ids=["<b@example.com>"],
            subject="Two",
            from_name="Luis",
            from_email="luis@example.com",
            when_ts=2000,
            when="Sun, 23 Aug 2026 09:00:00 -0600",
        )
        convs = mail.group_rows([a, b], "inbox")
        self.assertEqual(len(convs), 2)

    def test_subject_fallback_strips_re(self):
        a = row(uid=1, message_id="", ids=[], subject="Dinner", when_ts=1)
        b = row(
            uid=2,
            message_id="",
            ids=[],
            subject="Re: Dinner",
            when_ts=2,
            from_name="Luis",
            from_email="luis@example.com",
        )
        convs = mail.group_rows([a, b], "inbox")
        self.assertEqual(len(convs), 1)
        self.assertEqual(convs[0]["uids"], [1, 2])

    def test_sent_and_inbox_share_thread_when_viewing_inbox(self):
        incoming = row(
            uid=10,
            mailbox="inbox",
            message_id="<a@example.com>",
            ids=["<a@example.com>"],
            unread=True,
            when_ts=1,
        )
        sent = row(
            uid=20,
            mailbox="sent",
            message_id="<b@example.com>",
            ids=["<b@example.com>", "<a@example.com>"],
            mine=True,
            from_name="You",
            from_email="you@example.com",
            unread=False,
            when_ts=2,
        )
        convs = mail.group_rows([incoming, sent], "inbox")
        self.assertEqual(len(convs), 1)
        self.assertEqual(convs[0]["items"], [
            {"mailbox": "inbox", "uid": 10},
            {"mailbox": "sent", "uid": 20},
        ])
        self.assertTrue(convs[0]["unread"])

    def test_sent_only_thread_hidden_in_inbox(self):
        sent = row(uid=20, mailbox="sent", message_id="<s@example.com>", ids=["<s@example.com>"])
        self.assertEqual(mail.group_rows([sent], "inbox"), [])

    def test_normalize_subject(self):
        self.assertEqual(mail.normalize_subject("Re: Fwd: Hello"), "hello")
        self.assertEqual(mail.thread_key({"in-reply-to": "<a@x>"}, "Re: Hi"), "<a@x>")
        self.assertEqual(mail.thread_key({}, "Re: Hi"), "subj:hi")


class TestSearch(unittest.TestCase):
    def test_imap_quote(self):
        self.assertEqual(mail.imap_quote('a"b'), '"a\\"b"')

    def test_and_or_search_builds_or_tree(self):
        clause = mail.and_or_search("roy", ["SUBJECT", "FROM", "TO", "CC"], False)
        self.assertEqual(
            clause,
            'OR OR OR SUBJECT "roy" FROM "roy" TO "roy" CC "roy"',
        )

    def test_and_or_search_ands_tokens(self):
        clause = mail.and_or_search("kick friday", ["SUBJECT", "FROM"], False)
        self.assertIn('SUBJECT "kick"', clause)
        self.assertIn('SUBJECT "friday"', clause)
        self.assertTrue(clause.startswith("OR ") or " OR " in clause)

    def test_query_set_latest_page_uses_sequence(self):
        spec, use_uid = mail.query_set(None, 100, 50, "", False)
        self.assertEqual(spec, "51:100")
        self.assertFalse(use_uid)

    def test_query_set_empty_mailbox(self):
        spec, use_uid = mail.query_set(None, 0, 50, "", False)
        self.assertEqual(spec, "")
        self.assertFalse(use_uid)

    def test_query_set_small_mailbox(self):
        spec, _use_uid = mail.query_set(None, 3, 50, "", False)
        self.assertEqual(spec, "1:3")


class TestMime(unittest.TestCase):
    def _message(self, with_html=False, with_pdf=False):
        msg = EmailMessage()
        msg["From"] = "Maya Chen <maya@example.com>"
        msg["To"] = "You <you@example.com>"
        msg["Cc"] = "Luis Ortega <luis@example.com>"
        msg["Subject"] = "Project kickoff Friday"
        msg["Message-ID"] = "<kick@example.com>"
        msg["Date"] = "Sat, 22 Aug 2026 20:16:05 -0600"
        if with_html:
            msg.set_content("plain body")
            msg.add_alternative("<p>html &amp; body</p>", subtype="html")
        else:
            msg.set_content("Friday morning works.")
        if with_pdf:
            msg.add_attachment(
                b"%PDF-fake",
                maintype="application",
                subtype="pdf",
                filename="agenda.pdf",
            )
        return msg

    def test_plain_parse(self):
        raw = self._message().as_bytes()
        parsed = mail.parse_message(
            {"email": "you@example.com", "id": "acct1"}, "inbox", 12, raw
        )
        self.assertEqual(parsed["from"], "Maya Chen")
        self.assertEqual(parsed["fromEmail"], "maya@example.com")
        self.assertFalse(parsed["mine"])
        self.assertIn("Friday morning works.", parsed["text"])
        self.assertEqual(parsed["uid"], 12)
        self.assertEqual(parsed["attachments"], [])
        self.assertEqual(len(parsed["cc"]), 1)
        self.assertEqual(parsed["cc"][0]["email"], "luis@example.com")

    def test_html_alternative_keeps_plain(self):
        raw = self._message(with_html=True).as_bytes()
        parsed = mail.parse_message({"email": "you@example.com"}, "inbox", 1, raw)
        self.assertIn("plain body", parsed["text"])
        self.assertNotIn("&amp;", parsed["text"])

    def test_collect_and_extract_pdf(self):
        msg = self._message(with_pdf=True)
        atts = mail.collect_attachments(msg)
        self.assertEqual(len(atts), 1)
        self.assertEqual(atts[0]["name"], "agenda.pdf")
        self.assertEqual(atts[0]["mime"], "application/pdf")
        self.assertGreater(atts[0]["size"], 0)
        name, mime, data = mail.extract_part(msg, atts[0]["index"])
        self.assertEqual(name, "agenda.pdf")
        self.assertEqual(mime, "application/pdf")
        self.assertEqual(data, b"%PDF-fake")

    def test_extract_rejects_body_part(self):
        msg = self._message()
        with self.assertRaises(mail.Error):
            mail.extract_part(msg, 0)

    def test_cap_text_truncates(self):
        old = mail.MAX_TEXT_CHARS
        mail.MAX_TEXT_CHARS = 8
        try:
            self.assertEqual(mail.cap_text("hello"), "hello")
            out = mail.cap_text("abcdefghijk")
            self.assertTrue(out.endswith("[Truncated]"))
            self.assertLessEqual(len(out), 8 + len("\n\n[Truncated]"))
        finally:
            mail.MAX_TEXT_CHARS = old

    def test_parse_message_rejects_huge_raw(self):
        old = mail.MAX_MESSAGE_BYTES
        mail.MAX_MESSAGE_BYTES = 32
        try:
            with self.assertRaises(mail.Error):
                mail.parse_message(
                    {"email": "you@example.com"},
                    "inbox",
                    1,
                    b"From: a@b.c\n\n" + b"x" * 64,
                )
        finally:
            mail.MAX_MESSAGE_BYTES = old

    def test_extract_part_rejects_huge_attachment(self):
        old = mail.MAX_ATTACHMENT_BYTES
        mail.MAX_ATTACHMENT_BYTES = 4
        try:
            msg = EmailMessage()
            msg["From"] = "a@b.c"
            msg["To"] = "c@d.e"
            msg.set_content("hi")
            msg.add_attachment(
                b"0123456789",
                maintype="application",
                subtype="octet-stream",
                filename="big.bin",
            )
            atts = mail.collect_attachments(msg)
            self.assertEqual(len(atts), 1)
            with self.assertRaises(mail.Error):
                mail.extract_part(msg, atts[0]["index"])
        finally:
            mail.MAX_ATTACHMENT_BYTES = old

    def test_stub_oversized_message(self):
        msg = mail.stub_oversized_message({"email": "you@example.com"}, "inbox", 9, True)
        self.assertTrue(msg["truncated"])
        self.assertEqual(msg["uid"], 9)
        self.assertEqual(msg["attachments"], [])
        self.assertIn("too large", msg["text"])

    def test_safe_filename_strips_paths(self):
        self.assertEqual(mail.safe_filename("../../etc/passwd"), "passwd")
        self.assertEqual(mail.safe_filename(""), "attachment")

    def test_mine_uses_account_email(self):
        msg = self._message()
        msg.replace_header("From", "You <you@example.com>")
        parsed = mail.parse_message({"email": "you@example.com"}, "sent", 3, msg.as_bytes())
        self.assertTrue(parsed["mine"])
        self.assertEqual(parsed["from"], "You")


class TestImapParsing(unittest.TestCase):
    def test_parse_list_line_special_use(self):
        name, attrs = mail.parse_list_line(
            b'(\\HasNoChildren \\Sent) "/" "INBOX.Sent Messages"'
        )
        self.assertEqual(name, "INBOX.Sent Messages")
        self.assertIn("sent", attrs)

    def test_parse_list_line_junk(self):
        name, attrs = mail.parse_list_line(b'(\\Junk \\HasNoChildren) "." INBOX.Junk')
        self.assertEqual(name, "INBOX.Junk")
        self.assertIn("junk", attrs)

    def test_fetch_flags_unread(self):
        data = [
            (
                b"1 (UID 23641 FLAGS (\\Seen) INTERNALDATE \"22-Aug-2026 20:16:05 -0600\" BODY[HEADER.FIELDS (SUBJECT)] {8}",
                b"Subject:",
            ),
            b")",
        ]
        rows = mail.parse_fetch_data(data)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["uid"], 23641)
        self.assertFalse(rows[0]["unread"])
        self.assertIn("22-Aug-2026", rows[0]["internaldate"])

    def test_fetch_unseen_without_seen_flag(self):
        data = [(b"2 (UID 9 FLAGS (\\Flagged) BODY[] {4}", b"Hi\r\n")]
        rows = mail.parse_fetch_data(data)
        self.assertEqual(rows[0]["uid"], 9)
        self.assertTrue(rows[0]["unread"])

    def test_fetch_rfc822_size(self):
        data = [(b"1 (UID 12 RFC822.SIZE 441 FLAGS (\\Seen)", b"")]
        rows = mail.parse_fetch_data(data)
        self.assertEqual(rows[0]["uid"], 12)
        self.assertEqual(rows[0]["size"], 441)
        self.assertFalse(rows[0]["unread"])

    def test_fetch_body_items_is_ranged(self):
        spec = mail.fetch_body_items()
        self.assertIn(f"BODY.PEEK[]<0.{mail.MAX_MESSAGE_BYTES + 1}>", spec)
        self.assertNotIn("RFC822", spec)
        self.assertNotRegex(spec, r"BODY\.PEEK\[\](?!<)")

    def test_body_overflows_limit(self):
        old = mail.MAX_MESSAGE_BYTES
        mail.MAX_MESSAGE_BYTES = 8
        try:
            self.assertFalse(mail.body_overflows_limit(b"12345678"))
            self.assertTrue(mail.body_overflows_limit(b"123456789"))
            self.assertIn("<0.9>", mail.fetch_body_items())
        finally:
            mail.MAX_MESSAGE_BYTES = old

    def test_parse_fetch_partial_body(self):
        data = [
            (b"1 (UID 4 FLAGS () BODY[]<0> {9}", b"012345678"),
            b")",
        ]
        rows = mail.parse_fetch_data(data)
        self.assertEqual(rows[0]["uid"], 4)
        self.assertEqual(rows[0]["body"], b"012345678")

    def test_contacts_skip_self_and_prefer_inbox_from(self):
        accounts = [{"email": "you@example.com"}]
        rows = [
            row(from_name="Maya Chen", from_email="maya@example.com", mailbox="inbox", when_ts=2),
            row(
                mailbox="sent",
                from_email="you@example.com",
                to=[("Maya Chen", "maya@example.com"), ("Luis", "luis@example.com")],
                cc=[],
                when_ts=1,
            ),
        ]
        contacts = mail.collect_contacts(accounts, rows)
        emails = [c["email"] for c in contacts]
        self.assertEqual(emails, ["maya@example.com", "luis@example.com"])


class TestOutgoing(unittest.TestCase):
    def test_outgoing_from_uses_account(self):
        account = {"email": "work@example.com", "fromName": "Work", "name": "Office"}
        msg = mail.build_outgoing(
            account,
            {"subject": "Hi", "body": "hello"},
            [("Maya", "maya@example.com")],
            [],
            [],
            False,
            False,
        )
        self.assertEqual(msg["From"], "Work <work@example.com>")

    def test_draft_replace_account_id(self):
        self.assertEqual(mail.draft_replace_account_id({"replaceAccount": "b"}, "a"), "b")
        self.assertEqual(mail.draft_replace_account_id({}, "a"), "a")
        self.assertEqual(mail.draft_replace_account_id({"replaceAccount": "all"}, "a"), "a")

    def test_parse_desktop_name(self):
        text = "[Desktop Entry]\nName=HEY\nName[es]=HEY\nExec=hey\n"
        self.assertEqual(mail.parse_desktop_name(text), "HEY")
        self.assertEqual(mail.parse_desktop_name("[Other]\nName=Nope\n"), "")

    def test_pretty_desktop_id(self):
        self.assertEqual(mail.pretty_desktop_id("HEY.desktop"), "HEY")
        self.assertEqual(mail.pretty_desktop_id("io.github.roymckenzie.omarchy-mail.desktop"), "Mail")
        self.assertEqual(mail.pretty_desktop_id("org.gnome.Evolution.desktop"), "Evolution")

    def test_install_mailto_desktop(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = mail.install_mailto_desktop(Path(tmp))
            self.assertTrue(dest.is_file())
            text = dest.read_text(encoding="utf-8")
            self.assertIn("x-scheme-handler/mailto", text)
            self.assertIn("omarchy-mail compose", text)
            self.assertEqual(mail.parse_desktop_name(text), "Mail")


class TestListCache(unittest.TestCase):
    def round_trip(self, unread, conversations):
        accounts = [{"id": aid} for aid in unread]
        with tempfile.TemporaryDirectory() as tmp:
            old_home = os.environ.get("HOME")
            os.environ["HOME"] = tmp
            try:
                mail.save_list_cache(conversations, [], unread, "inbox")
                return mail.load_list_cache(accounts, "inbox")
            finally:
                if old_home is None:
                    del os.environ["HOME"]
                else:
                    os.environ["HOME"] = old_home

    def test_unread_is_per_account_not_the_total(self):
        unread = {"acct1": 3, "acct2": 4}
        convs = [
            {"accountId": "acct1", "id": "c1", "when": ""},
            {"accountId": "acct2", "id": "c2", "when": ""},
        ]
        total, cached, _contacts = self.round_trip(unread, convs)
        self.assertEqual(total, 7)
        self.assertEqual(len(cached), 2)

    def test_account_without_conversations_still_caches_its_count(self):
        # acct2's messages fell outside the page, so it contributes no conversation rows
        unread = {"acct1": 3, "acct2": 4}
        convs = [{"accountId": "acct1", "id": "c1", "when": ""}]
        total, cached, _contacts = self.round_trip(unread, convs)
        self.assertEqual(total, 7)
        self.assertEqual(len(cached), 1)


if __name__ == "__main__":
    unittest.main()
