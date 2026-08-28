# Mail

Bar widget for [Omarchy](https://omarchy.org/). Unread count on the bar, two-pane
IMAP client in the panel.

Plugin id: `io.github.roymckenzie.omarchy-mail`

With a saved account, the helper lists the latest 50 envelopes over IMAP,
searches on the server, and fetches bodies when you open a thread. Envelope
lists are cached on disk so the panel can open immediately; IMAP IDLE
refreshes in the background and new mail posts an Omarchy notification.
Until an account is saved, the panel is empty.

## Install

```sh
omarchy plugin add https://github.com/roymckenzie/omarchy-mail.git --enable
```

`--enable` places the widget on the right of the bar. Open it with a left
click, then add an IMAP/SMTP account (gear or `s`).

The helper is `bin/omarchy-mail-helper`, a Python 3 script (stdlib only: no pip,
no virtualenv). `omarchy plugin add` is enough; there is no compile step.

## Requirements

- [Omarchy](https://omarchy.org/) with `omarchy-shell`
- An IMAP and SMTP mailbox (host, ports, username, password)
- `secret-tool` (`libsecret`) for passwords in the user keyring
- `python3` (stdlib `imaplib` / `smtplib` / `email`)
- `xdg-desktop-portal` (GTK 3 fallback) for the attach picker

The plugin does not use sudo. It talks to your mail hosts from the helper
process, stores account metadata in
`~/.local/state/omarchy/settings/omarchy-mail.json` (mode 600), and caches
envelopes in `~/.local/state/omarchy/mail/cache/`. Passwords never go in that
file.

## Configure

```sh
omarchy bar move io.github.roymckenzie.omarchy-mail --section right
```

General settings can make Mail the default `mailto:` handler. A Hyprland bind
of Super+M can toggle the panel (not installed by the plugin):

```lua
o.bind("SUPER + M", "Mail", "omarchy-shell shell toggle io.github.roymckenzie.omarchy-mail")
```

## Usage

- Left click opens the panel
- `?` shortcuts
- `/` search (IMAP Subject/From/To/Cc, then BODY if nothing matches)
- Gear (or `s`) opens account settings
- Mailbox icon left of the account chips (Inbox / Sent / Drafts / Archive / Junk / Trash)
- `j` / `k` move, `h` / `l` list or message, `Enter` open
- `r` reply, `a` reply all, `f` forward, `c` compose
- `e` archive (or move back to Inbox), `!` junk (or not junk from Junk)
- `x` trash (deletes forever from Sent, Trash, and Junk), `u` toggle unread
- `g i` / `g s` / `g d` / `g e` / `g b` / `g t` jump to inbox, sent, drafts, archive, junk, trash
- `Esc` hides address suggestions, then cancels compose/reply, then closes the panel
- `Ctrl+Enter` sends, `Ctrl+S` saves a draft
- Middle click (or `0`) reloads the current folder

Reply, reply-all, forward, and compose are plaintext. Reply-all puts the sender
in To and everyone else (minus you) in Cc. Compose Cc/Bcc fields expand from
chips on the To row. Forward quotes the thread and can carry its attachments.
An in-progress compose or reply is kept if you close the panel.

Attachments on a thread open with a click and save to Downloads on right-click.
Compose and reply attach through an out-of-process portal picker (the panel
closes for the dialog, then restores the draft). Compose sends over SMTP and
appends a copy to Sent. Save Draft appends to the account Drafts folder.
With more than one account, click From in compose to pick which address
sends the message; Send and Save Draft use that account's SMTP, Sent, and
Drafts. General settings can mute new-mail notifications and choose the
default From account when All is selected. Opening a draft uses the compose pane; Sent is a reading pane.

The To/Cc/Bcc fields autocomplete from addresses harvested from IMAP envelopes
(From on inbox, To/Cc on sent). HTML mail is rendered as a small block model
(paragraph, heading, quote, list) — not a web view.

Architecture and local development: [DEVELOPMENT.md](DEVELOPMENT.md).

## Remove

```sh
omarchy plugin remove io.github.roymckenzie.omarchy-mail
```

This removes the plugin. Account settings, the keyring entry, and the envelope
cache are left in place.

## License

MIT. See [LICENSE](LICENSE).
