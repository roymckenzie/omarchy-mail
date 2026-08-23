.pragma library

function sampleAccounts() {
  return [
    {
      id: "work",
      name: "Work",
      fromName: "Roy McKenzie",
      email: "roy@example.com",
      imapHost: "imap.example.com",
      imapPort: "993",
      imapTls: true,
      smtpHost: "smtp.example.com",
      smtpPort: "465",
      smtpTls: true,
      username: "roy@example.com",
      password: ""
    },
    {
      id: "personal",
      name: "Personal",
      fromName: "Roy McKenzie",
      email: "roy@icloud.com",
      imapHost: "imap.mail.me.com",
      imapPort: "993",
      imapTls: true,
      smtpHost: "smtp.mail.me.com",
      smtpPort: "587",
      smtpTls: true,
      username: "roy",
      password: ""
    },
    {
      id: "fervid",
      name: "Fervid Digital",
      fromName: "Roy McKenzie",
      email: "roy@fervid.digital",
      imapHost: "imap.fastmail.com",
      imapPort: "993",
      imapTls: true,
      smtpHost: "smtp.fastmail.com",
      smtpPort: "465",
      smtpTls: true,
      username: "roy@fervid.digital",
      password: ""
    },
    {
      id: "family",
      name: "Family",
      fromName: "Roy McKenzie",
      email: "roy@icloud.com",
      imapHost: "imap.mail.me.com",
      imapPort: "993",
      imapTls: true,
      smtpHost: "smtp.mail.me.com",
      smtpPort: "587",
      smtpTls: true,
      username: "roy",
      password: ""
    }
  ]
}

var accounts = sampleAccounts()

function isoMinutesAgo(minutes) {
  return new Date(Date.now() - minutes * 60000).toISOString()
}

function isoDaysAgo(days, hour, minute) {
  var d = new Date()
  d.setDate(d.getDate() - days)
  d.setHours(hour === undefined ? 9 : hour, minute === undefined ? 12 : minute, 0, 0)
  return d.toISOString()
}

function freshInbox() {
  var items = [
    {
      id: "c1",
      accountId: "work",
      unread: true,
      subject: "Project kickoff Friday",
      preview: "Friday works. I'll send a short agenda this afternoon.",
      when: isoMinutesAgo(18),
      participants: ["Alice Chen", "Bob Alvarez"],
      messages: [
        {
          id: "c1m1",
          from: "Alice Chen",
          fromEmail: "alice@example.com",
          mine: false,
          when: isoMinutesAgo(94),
          blocks: [
            { type: "p", text: "Can we lock Friday for the kickoff? I want an hour with the full group before we start building." },
            { type: "p", text: "Happy to move if that collides with anything on your side." }
          ]
        },
        {
          id: "c1m2",
          from: "Bob Alvarez",
          fromEmail: "bob@example.com",
          mine: false,
          when: isoMinutesAgo(71),
          blocks: [
            { type: "p", text: "Friday morning is open for me. Afternoon is already packed." }
          ]
        },
        {
          id: "c1m3",
          from: "You",
          fromEmail: "roy@example.com",
          mine: true,
          when: isoMinutesAgo(18),
          blocks: [
            { type: "p", text: "Friday works. I'll send a short agenda this afternoon." }
          ]
        }
      ]
    },
    {
      id: "c2",
      accountId: "work",
      unread: true,
      subject: "[omarchy-mail] Review requested",
      preview: "roy requested your review on pull request #12: Two-pane inbox mockup",
      when: isoMinutesAgo(42),
      participants: ["GitHub"],
      messages: [
        {
          id: "c2m1",
          from: "GitHub",
          fromEmail: "notifications@github.com",
          mine: false,
          when: isoMinutesAgo(42),
          blocks: [
            { type: "p", text: "roy requested your review on pull request #12: Two-pane inbox mockup." },
            { type: "p", text: "Bar unread count, conversation list, HTML-as-blocks reading pane, and plaintext reply." },
            { type: "quote", text: "Keep fetch logic out of this pass. The panel should be something we can live in first." }
          ]
        }
      ]
    },
    {
      id: "c3",
      accountId: "work",
      unread: true,
      subject: "Omarchy Quattro notes",
      preview: "The plugin system is the whole product. If mail lives anywhere, it lives in the bar.",
      when: isoDaysAgo(1, 16, 40),
      participants: ["DHH"],
      messages: [
        {
          id: "c3m1",
          from: "DHH",
          fromEmail: "dhh@hey.com",
          mine: false,
          when: isoDaysAgo(1, 16, 4),
          blocks: [
            { type: "p", text: "The plugin system is the whole product. If mail lives anywhere, it lives in the bar." },
            { type: "p", text: "Unread number. Click. Triage. Gone." }
          ]
        },
        {
          id: "c3m2",
          from: "You",
          fromEmail: "roy@example.com",
          mine: true,
          when: isoDaysAgo(1, 16, 40),
          blocks: [
            { type: "p", text: "That's the shape. Conversation list, not folders. Reply in plain text." }
          ]
        }
      ]
    },
    {
      id: "c4",
      accountId: "personal",
      unread: false,
      subject: "Photos from the weekend",
      preview: "The last three are the keepers. The rest can live in the dump folder.",
      when: isoDaysAgo(2, 11, 8),
      participants: ["Mom"],
      messages: [
        {
          id: "c4m1",
          from: "Mom",
          fromEmail: "mom@icloud.com",
          mine: false,
          when: isoDaysAgo(2, 10, 22),
          blocks: [
            { type: "p", text: "Finally sent the photos. The last three are the keepers. The rest can live in the dump folder." },
            { type: "list", text: "Lake path at dusk\nThe group shot on the porch\nThat ridiculous sandwich" }
          ]
        },
        {
          id: "c4m2",
          from: "You",
          fromEmail: "roy@icloud.com",
          mine: true,
          when: isoDaysAgo(2, 11, 8),
          blocks: [
            { type: "p", text: "Got them. The porch one is going on the fridge." }
          ]
        }
      ]
    },
    {
      id: "c5",
      accountId: "personal",
      unread: false,
      subject: "Your invoice for August",
      preview: "Thanks for being a Fastmail customer. Invoice INV-1842 is ready.",
      when: isoDaysAgo(4, 8, 1),
      participants: ["Fastmail"],
      messages: [
        {
          id: "c5m1",
          from: "Fastmail",
          fromEmail: "billing@fastmail.com",
          mine: false,
          when: isoDaysAgo(4, 8, 1),
          blocks: [
            { type: "heading", text: "Invoice INV-1842" },
            { type: "p", text: "Thanks for being a Fastmail customer. Your August invoice is ready." },
            { type: "list", text: "Standard plan  ·  $5.00\nPeriod  ·  1–31 August" },
            { type: "p", text: "No action needed. This is a receipt, not a request for payment." }
          ],
          attachments: [
            { index: 0, name: "INV-1842.pdf", mime: "application/pdf", size: 48210 }
          ]
        }
      ]
    },
    {
      id: "c6",
      accountId: "personal",
      unread: false,
      subject: "This week in Linux",
      preview: "Hyprland 0.52, a quieter plugin story for Omarchy, and why HTML mail is still a trap.",
      when: isoDaysAgo(6, 7, 30),
      participants: ["Weekly Linux"],
      messages: [
        {
          id: "c6m1",
          from: "Weekly Linux",
          fromEmail: "news@weeklylinux.example",
          mine: false,
          when: isoDaysAgo(6, 7, 30),
          blocks: [
            { type: "heading", text: "Issue 214" },
            { type: "p", text: "Hyprland 0.52, a quieter plugin story for Omarchy, and why HTML mail is still a trap." },
            { type: "quote", text: "If your mail client needs Chromium to render a receipt, the receipt won." },
            { type: "p", text: "Also this week: LocalSend on iOS still wants the app in the foreground. No surprises." }
          ]
        }
      ]
    },
    {
      id: "c7",
      accountId: "personal",
      mailbox: "junk",
      unread: true,
      subject: "You have WON a cruise",
      preview: "Claim your prize before midnight or we give it to the next winner.",
      when: isoDaysAgo(1, 14, 12),
      participants: ["Prize Desk"],
      messages: [
        {
          id: "c7m1",
          from: "Prize Desk",
          fromEmail: "winner@prizes.example",
          mine: false,
          when: isoDaysAgo(1, 14, 12),
          blocks: [
            { type: "p", text: "Congratulations. You have been selected." },
            { type: "p", text: "Claim your prize before midnight or we give it to the next winner." }
          ]
        }
      ]
    }
  ]
  for (var i = 0; i < items.length; i++) {
    if (!items[i].mailbox) items[i].mailbox = "inbox"
  }
  return items
}
