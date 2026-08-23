import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// QProcess-style wrapper: JSON lines to bin/omarchy-mail-helper (Python IMAP/SMTP).
Item {
  id: root

  property string accountId: "all"
  property string mailbox: "inbox"
  property string query: ""
  property var conversations: []
  property int unread: 0
  property string lastError: ""
  property bool loading: false
  property string fetchingId: ""
  property bool available: false
  property bool live: false
  property bool sending: false
  property bool saving: false
  property string sendError: ""
  property var contacts: []
  property var unreadFlags: ({})
  property var _pendingUnread: ({})
  property var _dropped: ({})
  property int _epoch: 0
  property int _mutPending: 0
  property bool _quietUnread: false
  property bool _stopping: false
  property bool watchList: false
  property bool _booted: false
  property var _seen: ({})

  signal sent()
  signal drafted()
  signal sendFailed(string error)
  signal attached(string path, string name, string action)

  readonly property string helperPath: Model.pluginFile(Qt.resolvedUrl("bin/omarchy-mail-helper"))

  property int _seq: 0
  property var _pending: ({})
  property var _bodies: ({})
  property var _previews: ({})

  function start() {
    if (proc.running) return
    lastError = ""
    _booted = false
    _seen = ({})
    proc.running = true
  }

  function restart() {
    lastError = ""
    if (proc.running) {
      _stopping = true
      proc.running = false
      return
    }
    start()
  }

  function retry() {
    lastError = ""
    conversations = []
    fetchingId = ""
    loading = true
    restart()
  }

  function clearList() {
    conversations = []
    fetchingId = ""
    lastError = ""
    loading = true
  }

  function mutating() {
    return _mutPending > 0 || mutDebounce.running
  }

  function scheduleRefresh() {
    mutDebounce.restart()
  }

  function refresh(quiet) {
    if (!proc.running) start()
    if (mutating() && quiet) {
      scheduleRefresh()
      return
    }
    if (!quiet) loading = true
    send("list", { useCache: false })
  }

  function loadList() {
    if (!proc.running) start()
    loading = true
    send("list", { useCache: true })
  }

  function mailboxUids(conversation) {
    var box = (conversation && conversation.mailbox) ? conversation.mailbox : root.mailbox
    var items = conversation && conversation.items ? conversation.items : []
    var uids = []
    if (items && items.length) {
      for (var i = 0; i < items.length; i++) {
        var item = items[i]
        var role = item && item.mailbox ? item.mailbox : box
        var uid = Number(item && item.uid ? item.uid : 0)
        if (role === box && uid > 0) uids.push(uid)
      }
      return uids
    }
    var raw = conversation && conversation.uids ? conversation.uids : []
    for (var j = 0; j < raw.length; j++) {
      var n = Number(raw[j])
      if (n > 0) uids.push(n)
    }
    return uids
  }

  function latestMailboxUid(conversation) {
    var uids = mailboxUids(conversation)
    if (!uids || !uids.length) return 0
    return Number(uids[uids.length - 1]) || 0
  }

  function fetchThread(conversation) {
    var items = conversation && conversation.items ? conversation.items : []
    var uids = conversation && conversation.uids ? conversation.uids : []
    if ((!items || !items.length) && (!uids || !uids.length)) return
    fetchingId = conversation.id
    send("fetch", {
      account: conversation.accountId,
      mailbox: conversation.mailbox || root.mailbox,
      items: items,
      uids: uids,
      conv: conversation.id
    })
  }

  function setSeen(conversation, seen) {
    var uid = latestMailboxUid(conversation)
    if (!uid) return false
    var box = conversation.mailbox || root.mailbox
    var account = conversation.accountId
    if (!account || account === "all")
      account = root.accountId !== "all" ? root.accountId : ""
    _quietUnread = true
    send("seen", {
      account: account,
      mailbox: box,
      uids: [uid],
      items: [{ mailbox: box, uid: uid }],
      unseen: seen === false,
      conv: conversation.id
    })
    return true
  }

  function patchUnread(id, isUnread) {
    if (!id) return
    var flag = isUnread === true
    for (var i = 0; i < conversations.length; i++) {
      if (conversations[i].id === id) {
        conversations[i].unread = flag
        break
      }
    }
    var pending = Model.copy(_pendingUnread)
    pending[id] = flag
    _pendingUnread = pending
    var flags = Model.copy(unreadFlags)
    flags[id] = flag
    unreadFlags = flags
  }

  function syncUnreadFlags(convs) {
    var flags = {}
    for (var i = 0; i < (convs || []).length; i++) {
      var row = convs[i]
      if (!row || !row.id) continue
      flags[row.id] = row.unread === true
    }
    var pending = _pendingUnread || {}
    for (var id in pending) flags[id] = pending[id] === true
    unreadFlags = flags
  }

  function moveThread(conversation, toMailbox) {
    var uids = mailboxUids(conversation)
    if (!uids || !uids.length) return false
    var account = conversation.accountId
    if (!account || account === "all")
      account = root.accountId !== "all" ? root.accountId : ""
    dropConversation(conversation.id)
    _mutPending += 1
    send("move", {
      account: account,
      mailbox: conversation.mailbox || root.mailbox,
      uids: uids,
      items: conversation.items || [],
      to: toMailbox,
      conv: conversation.id
    })
    return true
  }

  function deleteThread(conversation) {
    var uids = mailboxUids(conversation)
    if (!uids || !uids.length) return false
    var account = conversation.accountId
    if (!account || account === "all")
      account = root.accountId !== "all" ? root.accountId : ""
    dropConversation(conversation.id)
    _mutPending += 1
    send("delete", {
      account: account,
      mailbox: conversation.mailbox || root.mailbox,
      uids: uids,
      items: conversation.items || [],
      conv: conversation.id
    })
    return true
  }

  function mergeContacts(incoming, extra) {
    var batch = []
    var i
    for (i = 0; i < (incoming || []).length; i++) batch.push(incoming[i])
    for (i = 0; i < (extra || []).length; i++) batch.push(extra[i])
    contacts = Model.mergeContacts(contacts, batch)
  }

  function harvestParticipants(convs) {
    var incoming = []
    for (var i = 0; i < (convs || []).length; i++) {
      var parts = convs[i] && convs[i].participants ? convs[i].participants : []
      for (var p = 0; p < parts.length; p++) {
        if (parts[p] && !parts[p].mine) incoming.push(parts[p])
      }
    }
    return incoming
  }

  function openAttachment(extra) {
    send("attachment", extra || {})
  }

  function sendMail(extra) {
    sending = true
    sendError = ""
    if (!proc.running) {
      sending = false
      sendError = "mail helper is not running"
      sendFailed(sendError)
      return
    }
    send("send", extra || {})
  }

  function noteInbox(convs) {
    var next = {}
    var fresh = []
    for (var i = 0; i < (convs || []).length; i++) {
      var row = convs[i]
      if (!row || !row.id) continue
      var stamp = String(row.when || "")
      next[row.id] = stamp
      if (_booted && row.unread && !row.latestMine && _seen[row.id] !== stamp)
        fresh.push(row)
    }
    _seen = next
    if (!_booted) {
      _booted = true
      return
    }
    if (fresh.length) notifyNewMail(fresh)
  }

  function notifyNewMail(convs) {
    var headline
    var body
    if (convs.length === 1) {
      headline = Model.participantLabel(convs[0]) || "New mail"
      body = String(convs[0].subject || "(no subject)")
    } else {
      headline = convs.length + " new messages"
      var bits = []
      for (var i = 0; i < convs.length && i < 3; i++)
        bits.push(String(convs[i].subject || "(no subject)"))
      body = bits.join(" · ")
    }
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "Mail",
      "-g", "󰇮",
      "-u", "normal",
      "--exec", "omarchy-shell shell summon io.github.roymckenzie.omarchy-mail",
      headline,
      body
    ])
  }

  function saveDraft(extra) {
    saving = true
    sendError = ""
    if (!proc.running) {
      saving = false
      sendError = "mail helper is not running"
      sendFailed(sendError)
      return
    }
    send("draft", extra || {})
  }

  function dropConversation(id) {
    if (!id) return
    var next = []
    for (var i = 0; i < conversations.length; i++) {
      if (conversations[i].id !== id) next.push(conversations[i])
    }
    if (next.length !== conversations.length) conversations = next
    var dropped = _dropped || {}
    if (dropped[id] === root.mailbox) return
    dropped = Model.copy(dropped)
    dropped[id] = root.mailbox
    _dropped = dropped
    _epoch += 1
  }

  function finishMutation(id, ok) {
    _mutPending = Math.max(0, _mutPending - 1)
    if (!ok && id) {
      var dropped = Model.copy(_dropped || {})
      delete dropped[id]
      _dropped = dropped
    }
    scheduleRefresh()
  }

  function withoutDropped(convs) {
    var dropped = _dropped || {}
    var box = root.mailbox
    var out = []
    for (var i = 0; i < (convs || []).length; i++) {
      var row = convs[i]
      if (row && row.id && dropped[row.id] === box) continue
      out.push(row)
    }
    return out
  }

  function clearDropped(box) {
    var dropped = _dropped || {}
    var next = {}
    var changed = false
    for (var id in dropped) {
      if (dropped[id] === box) {
        changed = true
        continue
      }
      next[id] = dropped[id]
    }
    if (changed) _dropped = next
  }

  function patchMessages(id, messages, preview) {
    if (!id || !messages) return
    var bodies = Model.copy(_bodies)
    bodies[id] = messages
    _bodies = bodies
    rememberPreview(id, preview)
    var next = []
    for (var i = 0; i < conversations.length; i++) {
      var row = conversations[i]
      if (row.id === id) {
        row = Model.copy(row)
        row.messages = messages
        if (preview) row.preview = preview
      }
      next.push(row)
    }
    conversations = next
  }

  function rememberPreview(id, snippet) {
    if (!id || !snippet) return
    var next = Model.copy(_previews)
    next[id] = snippet
    _previews = next
  }

  function cachedMessages(id) {
    if (!id) return null
    var bodies = _bodies
    return bodies && bodies[id] ? bodies[id] : null
  }

  function mergeSearchHits(incoming, previous, query) {
    var q = String(query || "").replace(/^\s+|\s+$/g, "")
    var out = []
    var seen = {}
    var list = incoming || []
    for (var i = 0; i < list.length; i++) {
      var row = list[i]
      if (!row || !row.id || seen[row.id]) continue
      seen[row.id] = true
      out.push(row)
    }
    if (q === "") return out
    var old = previous || []
    for (var j = 0; j < old.length; j++) {
      var keep = old[j]
      if (!keep || !keep.id || seen[keep.id]) continue
      if (!Model.matchesQuery(keep, q)) continue
      seen[keep.id] = true
      out.push(keep)
    }
    return out
  }

  function hydrateConversations(convs) {
    var previews = Model.copy(_previews)
    var out = []
    for (var i = 0; i < convs.length; i++) {
      var row = convs[i]
      var msgs = cachedMessages(row.id)
      if (msgs && msgs.length) row.messages = msgs
      var snippet = previews[row.id] || Model.previewFromMessages(row.messages)
      if (snippet) {
        row.preview = snippet
        previews[row.id] = snippet
      }
      out.push(row)
    }
    _previews = previews
    syncUnreadFlags(out)
    return out
  }

  function send(cmd, extra) {
    var req = {
      id: "r" + (++_seq),
      cmd: cmd,
      account: root.accountId,
      mailbox: root.mailbox,
      query: root.query,
      limit: 50
    }
    if (extra) {
      var keys = Object.keys(extra)
      for (var i = 0; i < keys.length; i++) req[keys[i]] = extra[keys[i]]
    }
    var pending = Model.copy(_pending)
    pending[req.id] = {
      cmd: cmd,
      conv: extra && extra.conv ? extra.conv : "",
      mailbox: req.mailbox,
      account: req.account,
      query: req.query,
      epoch: root._epoch,
      action: extra && extra.action ? extra.action : ""
    }
    _pending = pending
    if (!proc.running) {
      lastError = "mail helper is not running"
      fetchingId = ""
      return
    }
    proc.write(JSON.stringify(req) + "\n")
  }

  function handleLine(line) {
    var text = String(line || "").replace(/^\s+|\s+$/g, "")
    if (text === "") return
    var msg
    try { msg = JSON.parse(text) } catch (e) {
      lastError = "bad helper output"
      fetchingId = ""
      return
    }
    if (msg.event === "exists") {
      idleDebounce.restart()
      return
    }
    var pending = _pending[msg.id] || {}
    var listCurrent = pending.mailbox === root.mailbox
      && pending.account === root.accountId
      && pending.query === root.query
      && pending.epoch === root._epoch
    if (msg.ok === false) {
      if (pending.cmd === "attachment") return
      if (pending.cmd === "send" || pending.cmd === "draft") {
        sending = false
        saving = false
        sendError = String(msg.error || (pending.cmd === "draft" ? "couldn't save draft" : "couldn't send"))
        sendFailed(sendError)
        return
      }
      lastError = String(msg.error || "request failed")
      if (pending.cmd === "fetch") fetchingId = ""
      if (pending.cmd === "seen") {
        _quietUnread = false
        if (pending.conv) {
          var pendingFlags = Model.copy(_pendingUnread)
          delete pendingFlags[pending.conv]
          _pendingUnread = pendingFlags
        }
      }
      if (pending.cmd === "list" && listCurrent) loading = false
      if (pending.cmd === "move" || pending.cmd === "delete")
        finishMutation(pending.conv, false)
      return
    }
    if (pending.cmd === "attachment") {
      if (msg.path) attached(String(msg.path), String(msg.name || ""), pending.action || "")
      return
    }
    if (pending.cmd === "send") {
      sending = false
      sendError = ""
      sent()
      return
    }
    if (pending.cmd === "draft") {
      saving = false
      sendError = ""
      drafted()
      return
    }
    if (pending.cmd !== "list") lastError = ""
    if (msg.contacts)
      mergeContacts(msg.contacts, pending.cmd === "list" ? harvestParticipants(msg.conversations) : [])
    if (msg.conversations && (pending.cmd !== "list" || listCurrent)) {
      var incoming = msg.conversations
      if (pending.cmd === "list") {
        if (String(pending.query || "").replace(/^\s+|\s+$/g, "") !== "")
          incoming = mergeSearchHits(incoming, conversations, pending.query)
        incoming = withoutDropped(incoming)
      }
      conversations = hydrateConversations(incoming)
      if (pending.cmd === "list" && listCurrent && _mutPending === 0)
        clearDropped(pending.mailbox || root.mailbox)
      if (!msg.contacts) mergeContacts([], harvestParticipants(msg.conversations))
    }
    if (pending.cmd === "list" && listCurrent && pending.mailbox === "inbox" && msg.conversations)
      noteInbox(msg.conversations)
    if (msg.unread !== undefined && (pending.cmd !== "list" || listCurrent)) {
      var nextUnread = Number(msg.unread) || 0
      var grew = nextUnread > unread
      unread = nextUnread
      if (_quietUnread && pending.cmd === "status") {
        _quietUnread = false
        grew = false
      }
      if (grew && pending.cmd === "status") {
        if (mutating()) scheduleRefresh()
        else send("list", { mailbox: "inbox" })
      } else if (grew && pending.cmd === "list" && pending.mailbox !== "inbox") {
        if (mutating()) scheduleRefresh()
        else send("list", { mailbox: "inbox" })
      }
    }
    if (msg.messages && pending.conv) {
      var bodies = Model.copy(_bodies)
      bodies[pending.conv] = msg.messages
      _bodies = bodies
      var snippet = Model.previewFromMessages(msg.messages)
      rememberPreview(pending.conv, snippet)
      var next = []
      for (var c = 0; c < conversations.length; c++) {
        var row = conversations[c]
        if (row.id === pending.conv) {
          row = Model.copy(row)
          row.messages = msg.messages
          if (snippet) row.preview = snippet
          row.unread = false
        }
        next.push(row)
      }
      conversations = next
      if (pending.conv) {
        var flags = Model.copy(unreadFlags)
        flags[pending.conv] = false
        unreadFlags = flags
      }
      if (fetchingId === pending.conv) fetchingId = ""
      send("status", {})
    }
    if (pending.cmd === "seen") {
      if (pending.conv) {
        var pendingFlags = Model.copy(_pendingUnread)
        delete pendingFlags[pending.conv]
        _pendingUnread = pendingFlags
      }
      send("status", {})
    }
    if (pending.cmd === "move" || pending.cmd === "delete")
      finishMutation(pending.conv, true)
    if (pending.cmd === "list" && listCurrent && !msg.cached) loading = false
  }

  Process {
    id: proc
    command: [root.helperPath]
    stdinEnabled: true
    running: false
    stdout: SplitParser {
      onRead: function(data) { root.handleLine(data) }
    }
    stderr: SplitParser {
      onRead: function(data) { console.warn("mail-helper:", data) }
    }
    onStarted: {
      root.available = true
      root.live = true
      root.loadList()
    }
    onExited: function() {
      root.available = false
      root.live = false
      if (root._stopping) {
        root._stopping = false
        root.lastError = ""
        Qt.callLater(root.start)
        return
      }
      if (root.lastError === "") root.lastError = "mail helper exited"
    }
  }

  Timer {
    id: mutDebounce
    interval: 350
    repeat: false
    onTriggered: {
      if (root._mutPending > 0) {
        restart()
        return
      }
      root.refresh(true)
    }
  }

  Timer {
    id: idleDebounce
    interval: 400
    repeat: false
    onTriggered: {
      if (String(root.query || "").replace(/^\s+|\s+$/g, "") !== "") return
      if (root.mutating()) {
        root.scheduleRefresh()
        return
      }
      root.refresh(true)
    }
  }

  Timer {
    interval: root.watchList ? 20000 : 60000
    running: proc.running
    repeat: true
    onTriggered: {
      if (root.watchList && String(root.query || "").replace(/^\s+|\s+$/g, "") === "") {
        if (root.mutating()) root.scheduleRefresh()
        else root.refresh(true)
      } else {
        root.send("status", {})
      }
    }
  }
}
