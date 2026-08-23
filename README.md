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

A Hyprland bind of Super+M can toggle the panel (not installed by the plugin):

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
Opening a draft uses the compose pane; Sent is a reading pane.

The To/Cc/Bcc fields autocomplete from addresses harvested from IMAP envelopes
(From on inbox, To/Cc on sent). HTML mail is rendered as a small block model
(paragraph, heading, quote, list) — not a web view.

## How it is put together

This is a [Qt Quick](https://doc.qt.io/qt-6/qtquick-index.html) plugin, not a
standalone PyQt/PySide or GTK app. `omarchy-shell` is a long-running
[Quickshell](https://quickshell.org/) process (one `QGuiApplication` for the
whole desktop). The plugin is loaded into that process: `Panel.qml` is the
entry component, the same role `main.qml` plays with
`QQmlApplicationEngine`. There is no `if __name__ == "__main__"` window of
yours, and no GTK `Application`.

IMAP and SMTP stay out of the UI process. Python 3 runs as a child
(`bin/omarchy_mail.py`, launched by `bin/omarchy-mail-helper`) using stdlib
`imaplib`, `smtplib`, and `email`. `ImapService.qml` starts that process and
speaks JSON lines on stdin/stdout — the same idea as `QProcess` in Qt or
`GSubprocess` in GTK.

| If you know this | Here |
| --- | --- |
| PySide/PyQt `QMainWindow` / GTK `ApplicationWindow` | `Panel.qml` (bar chip + overlay panel) |
| `.ui` files, widgets, QML components | sibling `*.qml` files (`ComposePane.qml`, `SettingsPane.qml`, …) |
| Python helpers / a view-model module | `Model.js` (pure functions; `.pragma library`) |
| `QProcess` / a worker talking to the network | `ImapService.qml` + `bin/omarchy_mail.py` |
| `QSettings` / GSettings | `Store.qml` → `~/.local/state/omarchy/settings/omarchy-mail.json` |
| libsecret / `secretstorage` | `secret-tool` from the helper |
| `unittest` / `pytest` | `python3 bin/omarchy-mail-helper --test` |
| Qt Test / `pytest-qt` | `qmltestrunner` on `tests/tst_model.qml` |

QML files sit next to `manifest.json` because that is how Omarchy plugins
load (`entryPoints.barWidget`). Same layout as first-party Omarchy plugins.

```
manifest.json            plugin metadata (id, entry point)
Panel.qml                bar widget + panel (the host window)
ComposePane.qml          compose / reply / forward
SettingsPane.qml         account form
*.qml                    other UI pieces
Model.js                 QML-side helpers (addresses, filters, reply-all)
ImapService.qml          child process + JSON protocol
Store.qml                account JSON on disk
bin/omarchy_mail.py      IMAP / SMTP / MIME (Python 3 stdlib)
bin/omarchy-mail-helper  launcher (`python3` + `--test`)
tests/                   unittest + Qt Test
test.sh                  runs both suites
```

Hot-reload: saving a `.qml` or `.js` file reloads the plugin in the running
shell. Changing the Python helper does not — close and reopen the panel, or
`omarchy restart shell`, so Quickshell starts a new process.

## Local development

```sh
git clone https://github.com/roymckenzie/omarchy-mail.git
ln -sfn "$PWD/omarchy-mail" \
  ~/.config/omarchy/plugins/io.github.roymckenzie.omarchy-mail
omarchy plugin enable io.github.roymckenzie.omarchy-mail --section right
```

Tests need no mail server. `./test.sh` runs the Python suite (RFC2047,
threading, SEARCH, MIME) and the QML suite (`Model.js`). The QML runner is
Qt 6 `qmltestrunner` from `qt6-declarative` (`/usr/lib/qt6/bin/qmltestrunner`
on Arch; `/usr/bin/qmltestrunner` is Qt 5 and cannot run these tests):

```sh
./test.sh

# or separately:
python3 bin/omarchy-mail-helper --test
PYTHONPATH=bin python3 -m unittest discover -s tests -v
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -o -,txt
```

## Remove

```sh
omarchy plugin remove io.github.roymckenzie.omarchy-mail
```

This removes the plugin. Account settings, the keyring entry, and the envelope
cache are left in place.

## License

MIT. See [LICENSE](LICENSE).
