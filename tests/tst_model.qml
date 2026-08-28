import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Model"

  function sampleThread() {
    return {
      subject: "Project kickoff",
      accountId: "acct1",
      mailbox: "inbox",
      to: [{ name: "You", email: "you@example.com", mine: true }],
      messages: [
        {
          from: "Maya Chen",
          fromEmail: "maya@example.com",
          mine: false,
          to: [
            { name: "You", email: "you@example.com", mine: true },
            { name: "Luis Ortega", email: "luis@example.com", mine: false }
          ],
          cc: [{ name: "Priya Shah", email: "priya@example.com", mine: false }]
        }
      ]
    }
  }

  function test_replySubject() {
    compare(Model.replySubject("Hello"), "Re: Hello")
    compare(Model.replySubject("Re: Hello"), "Re: Hello")
    compare(Model.replySubject("RE: Hello"), "RE: Hello")
    compare(Model.replySubject("  "), "")
  }

  function test_forwardSubject() {
    compare(Model.forwardSubject("Hello"), "Fwd: Hello")
    compare(Model.forwardSubject("Fwd: Hello"), "Fwd: Hello")
    compare(Model.forwardSubject("Fw: Hello"), "Fw: Hello")
    compare(Model.forwardSubject(""), "Fwd:")
  }

  function test_formatAddress() {
    compare(Model.formatAddress("Maya Chen", "maya@example.com"), "Maya Chen <maya@example.com>")
    compare(Model.formatAddress("maya@example.com", "maya@example.com"), "maya@example.com")
    compare(Model.formatAddress("You", "you@example.com"), "you@example.com")
    compare(Model.formatAddress("", "you@example.com"), "you@example.com")
  }

  function test_splitAddresses() {
    var parts = Model.splitAddresses("Maya Chen <maya@example.com>, luis@example.com")
    compare(parts.length, 2)
    compare(parts[0], "Maya Chen <maya@example.com>")
    compare(parts[1], "luis@example.com")
    var nested = Model.splitAddresses("Ada <ada@example.com, via list>, bob@site.org")
    compare(nested.length, 2)
    compare(Model.splitAddresses("").length, 0)
  }

  function test_replyAddress_uses_latest_other() {
    var conv = sampleThread()
    compare(Model.replyAddress(conv, "you@example.com"), "Maya Chen <maya@example.com>")
  }

  function test_replyAll_puts_others_on_cc() {
    var recips = Model.replyAllRecipients(sampleThread(), "you@example.com")
    compare(recips.to, "Maya Chen <maya@example.com>")
    verify(recips.cc.indexOf("luis@example.com") >= 0)
    verify(recips.cc.indexOf("priya@example.com") >= 0)
    verify(recips.cc.indexOf("you@example.com") < 0)
  }

  function test_replyAll_own_message_keeps_original_to() {
    var conv = {
      messages: [
        {
          from: "You",
          fromEmail: "you@example.com",
          mine: true,
          to: [{ name: "Maya Chen", email: "maya@example.com", mine: false }],
          cc: [{ name: "Luis Ortega", email: "luis@example.com", mine: false }]
        }
      ]
    }
    var recips = Model.replyAllRecipients(conv, "you@example.com")
    compare(recips.to, "Maya Chen <maya@example.com>")
    compare(recips.cc, "Luis Ortega <luis@example.com>")
  }

  function test_filtered_mailbox_and_query() {
    var inbox = [
      { id: "1", mailbox: "inbox", accountId: "a", subject: "Kickoff Friday", preview: "", participants: [] },
      { id: "2", mailbox: "sent", accountId: "a", subject: "Kickoff Friday", preview: "", participants: [] },
      { id: "3", mailbox: "inbox", accountId: "b", subject: "Invoice", preview: "", participants: [] }
    ]
    compare(Model.filtered(inbox, "all", "inbox", "").length, 2)
    compare(Model.filtered(inbox, "a", "inbox", "").length, 1)
    compare(Model.filtered(inbox, "all", "inbox", "invoice").length, 1)
    compare(Model.filtered(inbox, "all", "inbox", "nope").length, 0)
  }

  function test_messageOpenByDefault() {
    compare(Model.messageOpenByDefault({ unread: false }, true), true)
    compare(Model.messageOpenByDefault({ unread: true }, true), true)
    compare(Model.messageOpenByDefault({ unread: true }, false), true)
    compare(Model.messageOpenByDefault({ unread: false }, false), false)
    compare(Model.messageOpenByDefault({}, false), false)
  }

  function test_defaultExpandedIds_freezes_unread_at_open() {
    var ids = Model.defaultExpandedIds([
      { id: "a", unread: true },
      { id: "b", unread: false },
      { id: "c", unread: false }
    ])
    compare(ids.a, true)
    compare(ids.b, false)
    compare(ids.c, true)
    var afterRead = Model.defaultExpandedIds([
      { id: "a", unread: false },
      { id: "b", unread: false },
      { id: "c", unread: false }
    ])
    compare(afterRead.a, false)
    compare(afterRead.c, true)
  }

  function test_escapeHtml() {
    compare(Model.escapeHtml("a <b> & c"), "a &lt;b&gt; &amp; c")
  }

  function test_bodyRuns_joins_paragraphs() {
    var runs = Model.bodyRuns([
      { type: "p", text: "Hello" },
      { type: "heading", text: "Title" },
      { type: "p", text: "World" },
      { type: "history", text: "old thread" },
      { type: "p", text: "After" }
    ])
    compare(runs.length, 3)
    compare(runs[0].kind, "body")
    compare(runs[0].blocks.length, 3)
    compare(runs[1].kind, "quote")
    compare(runs[1].block.type, "history")
    compare(runs[2].kind, "body")
    compare(runs[2].blocks.length, 1)
  }

  function test_formatBodyRun_keeps_paragraphs_in_one_document() {
    var html = Model.formatBodyRun([
      { type: "p", text: "Hello" },
      { type: "p", text: "World" }
    ])
    verify(html.indexOf("Hello") >= 0)
    verify(html.indexOf("World") >= 0)
    verify(html.indexOf("<br") >= 0)
  }

  function test_resolvedComposeAccountId() {
    var accounts = [
      { id: "personal", email: "me@home.example" },
      { id: "work", email: "me@work.example" }
    ]
    compare(Model.resolvedComposeAccountId(accounts, "work", "personal", "personal"), "work")
    compare(Model.resolvedComposeAccountId(accounts, "", "personal", "work"), "personal")
    compare(Model.resolvedComposeAccountId(accounts, "", "all", "work"), "work")
    compare(Model.resolvedComposeAccountId(accounts, "", "all", ""), "personal")
    compare(Model.resolvedComposeAccountId(accounts, "gone", "all", ""), "personal")
    compare(Model.resolvedComposeAccountId([], "", "all", ""), "")
  }
}
