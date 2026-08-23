import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/settings"
  readonly property string configPath: stateDir + "/omarchy-mail.json"

  property var accounts: []
  property var secrets: ({})
  property bool loaded: false
  property bool foundFile: false
  property bool _writing: false
  property var _queue: []

  signal ready()

  function accountsWithSecrets() {
    var out = []
    for (var i = 0; i < accounts.length; i++) {
      var acc = Model.normalizeAccount(accounts[i])
      acc.password = secrets[acc.id] || ""
      acc.hasPassword = acc.password !== "" || accounts[i].hasPassword === true
      out.push(acc)
    }
    return out
  }

  function persist(list) {
    var previous = {}
    for (var i = 0; i < accounts.length; i++) previous[accounts[i].id] = true

    var next = []
    var nextSecrets = Model.copy(secrets)
    var seen = {}
    for (var j = 0; j < (list || []).length; j++) {
      var acc = Model.normalizeAccount(list[j])
      seen[acc.id] = true
      if (String(acc.password || "") !== "") {
        nextSecrets[acc.id] = acc.password
        enqueue({ op: "store", id: acc.id, name: acc.name, password: acc.password })
      }
      var disk = Model.accountForDisk(acc)
      disk.hasPassword = String(acc.password || "") !== "" || acc.hasPassword === true || !!nextSecrets[acc.id]
      next.push(disk)
    }

    for (var id in previous) {
      if (!seen[id]) {
        delete nextSecrets[id]
        enqueue({ op: "clear", id: id })
      }
    }

    accounts = next
    secrets = nextSecrets
    _writing = true
    ensureDirProc.running = true
    configFile.setText(Model.serializeAccounts(next))
    chmodProc.running = true
    pump()
  }

  function enqueue(job) {
    _queue.push(job)
    pump()
  }

  function pump() {
    if (secretProc.running || _queue.length === 0) return
    var job = _queue.shift()
    secretProc.job = job
    if (job.op === "store") {
      secretProc.stdinEnabled = true
      secretProc.command = [
        "secret-tool", "store",
        "--label", "Omarchy Mail · " + (job.name || job.id),
        "service", "omarchy-mail",
        "account", job.id
      ]
      secretProc.secret = job.password
      secretProc.running = true
    } else if (job.op === "lookup") {
      secretProc.stdinEnabled = false
      secretProc.secret = ""
      secretProc.command = ["secret-tool", "lookup", "service", "omarchy-mail", "account", job.id]
      secretProc.running = true
    } else if (job.op === "clear") {
      secretProc.stdinEnabled = false
      secretProc.secret = ""
      secretProc.command = ["secret-tool", "clear", "service", "omarchy-mail", "account", job.id]
      secretProc.running = true
    }
  }

  function finishLoad() {
    loaded = true
    root.ready()
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", root.stateDir]
    running: false
  }

  Process {
    id: chmodProc
    command: ["chmod", "600", root.configPath]
    running: false
  }

  Process {
    id: secretProc
    property var job: ({})
    property string secret: ""
    running: false
    stdinEnabled: false
    stdout: StdioCollector { id: secretOut; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      if (job && job.op === "store") {
        write(secret + "\n")
        secret = ""
        stdinEnabled = false
      }
    }
    onExited: function() {
      var current = job || {}
      if (current.op === "lookup" && current.id) {
        var value = String(secretOut.text || "").replace(/\n$/, "")
        if (value !== "") {
          var next = Model.copy(root.secrets)
          next[current.id] = value
          root.secrets = next
        }
      }
      job = ({})
      if (root._queue.length) root.pump()
      else if (!root.loaded) root.finishLoad()
    }
  }

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: if (!root._writing) reload()
    onLoaded: {
      if (root._writing) {
        root._writing = false
        chmodProc.running = true
        return
      }
      var parsed = Model.parseAccounts(text())
      root.foundFile = true
      root.accounts = parsed
      var lookups = 0
      for (var i = 0; i < parsed.length; i++) {
        if (parsed[i].hasPassword) {
          root.enqueue({ op: "lookup", id: parsed[i].id })
          lookups += 1
        }
      }
      if (lookups === 0) root.finishLoad()
    }
    onLoadFailed: {
      root.foundFile = false
      root.accounts = []
      root.finishLoad()
    }
  }

  Component.onCompleted: {
    ensureDirProc.running = true
    Qt.callLater(function() { configFile.reload() })
  }
}
