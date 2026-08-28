# Development

Architecture and local setup for [omarchy-mail](README.md). Users install with
`omarchy plugin add`; this file is for changing the plugin.

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
