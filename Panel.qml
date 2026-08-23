import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Hosted by omarchy-shell (Quickshell), not a standalone QApplication.
// IMAP/SMTP is the Python child in bin/omarchy_mail.py (see ImapService.qml).
Panel {
  id: root
  moduleName: "io.github.roymckenzie.omarchy-mail"
  ipcTarget: "io.github.roymckenzie.omarchy-mail"
  manageIpc: false

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property bool vertical: bar ? bar.vertical : false

  property var inbox: []
  property var accounts: []
  property var accountDrafts: ({})
  property var editing: ({})
  property string accountId: "all"
  property string mailboxId: "inbox"
  property string selectedId: ""
  property string paneFocus: "list"
  property bool gotoPending: false
  property bool listCursorTouched: false
  property string pendingSelectId: ""
  property int pendingSelectIndex: -1
  property var expandedIds: ({})
  property string settingsAccountId: ""
  property bool settingsOpen: false
  property bool settingsHydrating: false
  property bool composing: false
  property bool forwarding: false
  property bool pendingForward: false
  property bool replyOpen: false
  property bool replyAll: false
  property string replyText: ""
  property string composeTo: ""
  property string composeCc: ""
  property string composeBcc: ""
  property bool composeShowCc: false
  property bool composeShowBcc: false
  property string composeSubject: ""
  property string composeBody: ""
  property int composeSuggestIndex: 0
  property bool composeSuggestHidden: false
  property bool composeDirty: false
  property bool composeHydrating: false
  property bool composeHold: false
  property bool suppressSelection: false
  property string composeLoadedId: ""
  property var outgoingFiles: []
  property bool keepCompose: false
  property string searchQuery: ""
  property double nowMs: Date.now()

  readonly property var settingsAccounts: Model.settingsAccountList(accounts, accountDrafts)
  readonly property var settingsSelected: Model.accountById(settingsAccounts, settingsAccountId)
  readonly property int settingsIndex: Model.indexOfId(settingsAccounts, settingsAccountId)
  readonly property bool editingDirty: {
    if (!editing || !editing.id) return false
    var saved = Model.accountById(accounts, editing.id)
    if (!saved) return true
    return !Model.accountsEqual(editing, saved)
  }
  readonly property bool editingCanSave: editingDirty && Model.accountCanSave(editing)
  readonly property bool settingsFieldFocused: settingsOpen && (
    accNameField.activeFocus || accFromNameField.activeFocus || accEmailField.activeFocus
    || imapHostField.activeFocus || imapPortField.activeFocus
    || smtpHostField.activeFocus || smtpPortField.activeFocus
    || accUserField.activeFocus || accPassField.activeFocus
  )
  readonly property bool liveMail: store.foundFile && accounts.length > 0
  readonly property string trimmedQuery: String(searchQuery || "").replace(/^\s+|\s+$/g, "")
  readonly property bool searchBusy: liveMail && trimmedQuery !== "" && (
    searchDebounce.running
    || mail.loading
    || String(mail.query || "").replace(/^\s+|\s+$/g, "") !== trimmedQuery
  )
  readonly property var visibleInbox: {
    if (!liveMail)
      return Model.filtered(inbox, accountId, mailboxId, searchQuery)
    var list = Model.filterByAccount(Model.filterByMailbox(mail.conversations, mailboxId), accountId)
    var liveQ = String(mail.query || "").replace(/^\s+|\s+$/g, "")
    if (trimmedQuery === "" || (liveQ === trimmedQuery && !mail.loading))
      return list
    return Model.filtered(list, "all", mailboxId, searchQuery)
  }
  readonly property int unreadAll: liveMail ? mail.unread : Model.unreadCount(inbox, "all")
  readonly property var mailUnreadFlags: mail.unreadFlags
  readonly property int unreadVisible: {
    if (!liveMail) return Model.unreadCount(inbox, accountId)
    var flags = mail.unreadFlags
    var list = visibleInbox
    var n = 0
    for (var i = 0; i < (list || []).length; i++) {
      var id = list[i] && list[i].id
      if (flags && id && flags[id] !== undefined) {
        if (flags[id]) n += 1
      } else if (list[i] && list[i].unread) n += 1
    }
    return n
  }
  readonly property string heroMeta: {
    if (!liveMail) return "Add an account"
    if (liveMail && mail.lastError !== "" && visibleInbox.length === 0) return "Can't connect"
    if (liveMail && mail.loading && visibleInbox.length === 0)
      return trimmedQuery !== "" ? "Searching…" : "Loading…"
    if (trimmedQuery !== "") {
      if (visibleInbox.length === 0) return "No matches"
      return visibleInbox.length === 1 ? "1 match" : visibleInbox.length + " matches"
    }
    if (mailboxId === "inbox")
      return unreadVisible === 0 ? "Caught up" : (unreadVisible === 1 ? "1 unread" : unreadVisible + " unread")
    if (visibleInbox.length === 0) {
      if (mailboxId === "trash") return "Trash is empty"
      if (mailboxId === "junk") return "No junk"
      if (mailboxId === "sent") return "No sent mail"
      if (mailboxId === "drafts") return "No drafts"
      return "Nothing archived"
    }
    return visibleInbox.length === 1 ? "1 conversation" : visibleInbox.length + " conversations"
  }
  readonly property string emptyLabel: {
    if (!liveMail) return "Add an account in settings to get started."
    if (liveMail && mail.lastError !== "") return "Couldn't load mail."
    if (liveMail && mail.loading) return trimmedQuery !== "" ? "Searching…" : "Loading…"
    if (trimmedQuery !== "" && visibleInbox.length === 0)
      return "No matches."
    if (mailboxId === "trash") return "Trash is empty."
    if (mailboxId === "junk") return "No junk."
    if (mailboxId === "sent") return "No sent mail."
    if (mailboxId === "drafts") return "No drafts."
    if (mailboxId === "archive") return "Nothing archived."
    return "Inbox is empty."
  }
  readonly property int selectedIndex: Model.indexOfId(visibleInbox, selectedId)
  readonly property var selected: selectedIndex >= 0 ? visibleInbox[selectedIndex] : null
  readonly property string barLabel: unreadAll > 0 ? "󰇮  " + unreadAll : "󰇮"
  readonly property string tooltipText: {
    if (!liveMail) return "Add an account"
    if (unreadAll === 0) return "No unread mail"
    return unreadAll === 1 ? "1 unread conversation" : unreadAll + " unread conversations"
  }
  readonly property var composeContactList: liveMail
    ? mail.contacts
    : Model.contactsFromInbox(inbox, accounts)
  readonly property bool outboundMailbox: mailboxId === "drafts"
  readonly property bool composePane: composing || composeHold || (outboundMailbox && !!selected && !replyOpen)
  readonly property string composeAddrRole: {
    if (composeCcField.activeFocus) return "cc"
    if (composeBccField.activeFocus) return "bcc"
    return "to"
  }
  readonly property string composeAddrDraft: {
    if (composeAddrRole === "cc") return composeCc
    if (composeAddrRole === "bcc") return composeBcc
    return composeTo
  }
  readonly property var composeMatches: composePane
    ? Model.filterContacts(composeContactList, Model.addressDraft(composeAddrDraft), 8)
    : []
  readonly property string composeFromLabel: {
    var acc = Model.accountById(accounts, composeAccountId())
    return acc ? Model.formatAddress(Model.accountFromName(acc), acc.email) : ""
  }
  readonly property string composeTitle: {
    if (forwarding) return "FORWARD"
    if (composing) return "NEW MESSAGE"
    if (mailboxId === "drafts") return "DRAFT"
    return "NEW MESSAGE"
  }

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight
  readonly property Item barButton: textButton
  readonly property int chipBorderPad: Math.max(Style.hoverBorderWidth, Style.normalBorderWidth)
  readonly property int filterChipHeight: Math.max(
    Style.spacing.controlHeight,
    chipMetrics.implicitHeight + Style.spacing.controlPaddingY * 2 + chipBorderPad * 2)

  Text {
    id: chipMetrics
    visible: false
    text: "Personal"
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Store {
    id: store
    onReady: root.applyStoredAccounts()
  }

  ImapService {
    id: mail
    accountId: root.accountId
    mailbox: root.mailboxId
    watchList: root.opened && !root.settingsOpen
  }

  readonly property bool mailSending: mail.sending
  readonly property bool mailSaving: mail.saving
  readonly property string mailSendError: mail.sendError
  readonly property bool filePickerBusy: filePicker.running || pickStartTimer.running

  readonly property var composeToField: composePane.composeToField
  readonly property var composeCcField: composePane.composeCcField
  readonly property var composeBccField: composePane.composeBccField
  readonly property var composeSubjectField: composePane.composeSubjectField
  readonly property var composeBodyField: composePane.composeBodyField
  readonly property var composeSuggestPopup: composePane.composeSuggestPopup
  readonly property var addrBlock: composePane.addrBlock
  readonly property var accNameField: settingsPane.accNameField
  readonly property var accFromNameField: settingsPane.accFromNameField
  readonly property var accEmailField: settingsPane.accEmailField
  readonly property var imapHostField: settingsPane.imapHostField
  readonly property var imapPortField: settingsPane.imapPortField
  readonly property var smtpHostField: settingsPane.smtpHostField
  readonly property var smtpPortField: settingsPane.smtpPortField
  readonly property var accUserField: settingsPane.accUserField
  readonly property var accPassField: settingsPane.accPassField

  Process {
    id: filePicker
    command: ["python3", Model.pluginFile(Qt.resolvedUrl("bin/omarchy-mail-pick-files"))]
    stdout: SplitParser {
      onRead: function(line) {
        var path = String(line || "").replace(/^\s+|\s+$/g, "")
        if (path) root.addOutgoingFiles([path])
      }
    }
    onExited: function() {
      if (!root.opened) root.open()
      else root.keepCompose = false
    }
  }

  Timer {
    id: pickStartTimer
    interval: 180
    repeat: false
    onTriggered: filePicker.running = true
  }

  Connections {
    target: mail
    function onSent() { root.finishSend() }
    function onDrafted() { root.finishDraft() }
    function onAttached(path, name, action) {
      if (action === "extract" && path) root.addOutgoingFiles([path])
    }
  }

  function resetInbox() {
    composing = false
    replyOpen = false
    replyText = ""
    clearComposeAddrs()
    composeSubject = ""
    composeBody = ""
    searchQuery = ""
    if (listSearchField) listSearchField.text = ""
    mailboxId = "inbox"
    listCursorTouched = false
    inbox = []
    if (liveMail) mail.refresh(true)
    else ensureSelection()
  }

  function applyAccountList(list) {
    accounts = list || []
    accountDrafts = ({})
    editing = ({})
    settingsAccountId = accounts.length > 0 ? accounts[0].id : ""
    if (settingsAccountId !== "") editing = Model.normalizeAccount(accounts[0])
  }

  function applyStoredAccounts() {
    if (store.foundFile) {
      applyAccountList(store.accountsWithSecrets())
      inbox = []
      mail.start()
    } else {
      applyAccountList([])
    }
  }

  function persistAccounts() {
    store.persist(accounts)
    if (accounts.length) mail.restart()
  }

  function openLink(url) {
    var href = Model.safeUrl(url)
    if (href) Qt.openUrlExternally(href)
  }

  function unreadCount(list) {
    var n = 0
    for (var i = 0; i < (list || []).length; i++) if (list[i].unread) n += 1
    return n
  }

  function syncLive() {
    if (!liveMail) return
    mail.query = searchQuery
    if (String(searchQuery || "").replace(/^\s+|\s+$/g, "") !== "") mail.refresh()
    else mail.loadList()
  }

  function conversationNeedsFetch(conv) {
    if (!liveMail || !conv) return false
    var items = conv.items || []
    var uids = conv.uids || []
    var expected = items.length ? items.length : (uids.length ? uids.length : 0)
    var msgs = conv.messages || []
    if (!msgs.length) return true
    if (!expected) return false
    var have = 0
    for (var i = 0; i < msgs.length; i++) {
      var id = String(msgs[i] && msgs[i].id ? msgs[i].id : "")
      if (id.indexOf(":") >= 0) have += 1
    }
    return expected > have
  }

  function scheduleFetch(conv) {
    if (!conversationNeedsFetch(conv || selected)) {
      fetchDebounce.stop()
      return
    }
    fetchDebounce.restart()
  }

  function neighborAfterRemove(index) {
    if (index < 0 || visibleInbox.length <= 1) return ""
    if (index + 1 < visibleInbox.length) return visibleInbox[index + 1].id
    return visibleInbox[index - 1].id
  }

  function rememberNeighbor(index) {
    pendingSelectId = neighborAfterRemove(index)
    pendingSelectIndex = index
  }

  function takePendingIndex() {
    var id = pendingSelectId
    var idx = pendingSelectIndex
    pendingSelectId = ""
    pendingSelectIndex = -1
    var prefer = id ? Model.indexOfId(visibleInbox, id) : -1
    if (prefer >= 0) return prefer
    if (visibleInbox.length === 0) return -1
    if (idx < 0) return 0
    return Math.min(idx, visibleInbox.length - 1)
  }

  function ensureSelection() {
    if (suppressSelection) {
      selectedId = ""
      pendingSelectId = ""
      pendingSelectIndex = -1
      paneFocus = "list"
      fetchDebounce.stop()
      return
    }
    if (visibleInbox.length === 0) {
      selectedId = ""
      pendingSelectId = ""
      pendingSelectIndex = -1
      paneFocus = "list"
      fetchDebounce.stop()
      return
    }
    var index = Model.indexOfId(visibleInbox, selectedId)
    var pending = pendingSelectId !== "" || pendingSelectIndex >= 0
    if (index < 0) {
      var next = takePendingIndex()
      if (next < 0) next = 0
      selectedId = visibleInbox[next].id
      index = next
    } else if (!listCursorTouched && !pending) {
      selectedId = visibleInbox[0].id
      index = 0
    } else if (pending) {
      pendingSelectId = ""
      pendingSelectIndex = -1
    }
    scheduleFetch(visibleInbox[index])
  }

  function setAccount(id) {
    if (id === accountId) return
    var previous = accountId
    accountId = id
    composing = false
    replyOpen = false
    composeHold = false
    suppressSelection = false
    listCursorTouched = false
    paneFocus = "list"
    if (liveMail && previous === "all" && id !== "all") {
      ensureSelection()
      return
    }
    if (liveMail) mail.clearList()
    ensureSelection()
    syncLive()
  }

  function setMailbox(id) {
    if (id === mailboxId) return
    if (id !== "drafts") composeHold = false
    suppressSelection = false
    listCursorTouched = false
    mailboxId = id
    composing = false
    replyOpen = false
    paneFocus = "list"
    if (liveMail) mail.clearList()
    ensureSelection()
    syncLive()
  }

  function selectAt(index) {
    if (visibleInbox.length === 0) return
    var next = Math.max(0, Math.min(visibleInbox.length - 1, index))
    var conv = visibleInbox[next]
    composeHold = false
    suppressSelection = false
    listCursorTouched = true
    selectedId = conv.id
    replyOpen = false
    composing = false
    scrollSelectedIntoView()
    scheduleFetch(conv)
  }

  function focusPane(which) {
    if (which === "read") {
      if (composing) {
        paneFocus = "read"
        Qt.callLater(function() { composeBodyField.forceActiveFocus() })
        return
      }
      if (!selected) return
      paneFocus = "read"
      openSelected()
      if (composePane)
        Qt.callLater(function() { composeBodyField.forceActiveFocus() })
      return
    }
    paneFocus = "list"
  }

  function scrollReadPane(dy) {
    if (!threadFlick) return
    var step = Math.max(Style.space(48), Math.round(threadFlick.height * 0.22))
    var maxY = Math.max(0, threadFlick.contentHeight - threadFlick.height)
    threadFlick.contentY = Math.max(0, Math.min(maxY, threadFlick.contentY + dy * step))
  }

  function moveCursor(dx, dy) {
    if (dx > 0) focusPane("read")
    else if (dx < 0) focusPane("list")
    if (dy === 0) return
    if (paneFocus === "read") scrollReadPane(dy)
    else selectAt(selectedIndex < 0 ? 0 : selectedIndex + dy)
  }

  function messageKey(message, index) {
    if (message && message.id) return String(message.id)
    return "idx-" + index
  }

  function toggleMessageExpanded(message, index) {
    var key = messageKey(message, index)
    var next = Model.copy(expandedIds)
    if (next[key]) delete next[key]
    else next[key] = true
    expandedIds = next
  }

  function reloadSelected() {
    if (!selected) return
    if (conversationNeedsFetch(selected)) mail.fetchThread(selected)
  }

  function openSelected() {
    if (!selected) return
    if (selected.unread) inbox = Model.markRead(inbox, selected.id, false)
    replyOpen = false
    composing = false
    reloadSelected()
  }

  function toggleUnread() {
    if (!selected) return
    var wantUnread = !selected.unread
    if (liveMail) {
      mail.setSeen(selected, !wantUnread)
      mail.patchUnread(selected.id, wantUnread)
      mail.unread = Math.max(0, (Number(mail.unread) || 0) + (wantUnread ? 1 : -1))
      return
    }
    inbox = Model.markRead(inbox, selected.id, wantUnread)
  }

  function moveSelected(mailbox) {
    if (!selected) return
    if (Model.mailboxOf(selected) === mailbox) return
    rememberNeighbor(selectedIndex)
    if (liveMail) {
      var conv = selected
      if (mail.moveThread(conv, mailbox)) mail.dropConversation(conv.id)
      return
    }
    var id = selected.id
    var nextIndex = selectedIndex
    inbox = Model.moveToMailbox(inbox, id, mailbox)
    if (visibleInbox.length === 0) selectedId = ""
    else selectAt(Math.min(nextIndex, visibleInbox.length - 1))
  }

  function archiveSelected() {
    moveSelected(mailboxId === "archive" ? "inbox" : "archive")
  }

  function junkSelected() {
    moveSelected(mailboxId === "junk" ? "inbox" : "junk")
  }

  function deleteSelected() {
    if (!selected) return
    rememberNeighbor(selectedIndex)
    if (liveMail) {
      var conv = selected
      if (mail.deleteThread(conv)) mail.dropConversation(conv.id)
      return
    }
    var nextIndex = selectedIndex
    inbox = Model.removeConversation(inbox, selected.id)
    if (visibleInbox.length === 0) selectedId = ""
    else selectAt(Math.min(nextIndex, visibleInbox.length - 1))
  }

  function trashSelected() {
    if (mailboxId === "sent" || mailboxId === "trash" || mailboxId === "junk")
      deleteSelected()
    else moveSelected("trash")
  }

  function beginReply(all) {
    if (!selected) return
    composing = false
    replyOpen = true
    replyAll = all === true
    mail.sendError = ""
    clearOutgoingFiles()
    if (selected.unread) inbox = Model.markRead(inbox, selected.id, false)
    Qt.callLater(function() { replyField.forceActiveFocus() })
  }

  function cancelReply() {
    replyOpen = false
    replyAll = false
    replyText = ""
    clearOutgoingFiles()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  readonly property var replyAllRecips: {
    if (!selected || !replyAll) return { to: "", cc: "" }
    var account = Model.accountById(accounts, selected.accountId)
    var email = account ? account.email : ""
    return Model.replyAllRecipients(selected, email)
  }

  readonly property string replyToLabel: {
    if (!selected) return ""
    if (replyAll) return String(replyAllRecips && replyAllRecips.to || "")
    var account = Model.accountById(accounts, selected.accountId)
    var email = account ? account.email : ""
    return Model.replyAddress(selected, email)
  }

  readonly property string replyCcLabel: {
    if (!replyAll) return ""
    return String(replyAllRecips && replyAllRecips.cc || "")
  }

  function composeAccountId() {
    if (accountId && accountId !== "all") return accountId
    if (selected && selected.accountId && selected.accountId !== "all") return selected.accountId
    if (accounts.length) return accounts[0].id
    return ""
  }

  function finishSend() {
    clearOutgoingFiles()
    var wasReply = replyOpen
    var replyBody = replyText
    var replyConv = selected
    if (mailboxId === "drafts") {
      composing = false
      composeHold = false
      composeDirty = false
      composeLoadedId = ""
      composeSuggestIndex = 0
      composeHydrating = true
      clearComposeAddrs()
      composeSubject = ""
      composeBody = ""
      if (composeSubjectField) composeSubjectField.text = ""
      if (composeBodyField) composeBodyField.text = ""
      composeHydrating = false
      selectedId = ""
      pendingSelectId = ""
      pendingSelectIndex = -1
      suppressSelection = true
      paneFocus = "list"
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else if (composing) {
      cancelCompose()
    }
    if (wasReply) {
      cancelReply()
      if (replyConv && replyBody) {
        var account = Model.accountById(accounts, replyConv.accountId)
        var email = account ? account.email : ""
        if (liveMail) {
          var patched = Model.appendReply([Model.copy(replyConv)], replyConv.id, replyBody, email)
          if (patched && patched[0])
            mail.patchMessages(replyConv.id, patched[0].messages, patched[0].preview)
        } else {
          inbox = Model.appendReply(inbox, replyConv.id, replyBody, email)
        }
      }
    }
    if (liveMail) mail.refresh(true)
  }

  function finishDraft() {
    composing = false
    replyOpen = false
    composeHold = true
    composeDirty = true
    composeSuggestIndex = 0
    selectedId = ""
    pendingSelectId = ""
    pendingSelectIndex = 0
    if (!liveMail) {
      mailboxId = "drafts"
      ensureSelection()
      return
    }
    if (mailboxId === "drafts") mail.refresh(true)
    else setMailbox("drafts")
  }

  function composeBusy() {
    return mail.sending || mail.saving
  }

  function clearComposeAddrs() {
    composeTo = ""
    composeCc = ""
    composeBcc = ""
    composeShowCc = false
    composeShowBcc = false
    if (composeToField) composeToField.text = ""
    if (composeCcField) composeCcField.text = ""
    if (composeBccField) composeBccField.text = ""
  }

  function composeAddrText(role) {
    if (role === "cc") return composeCc
    if (role === "bcc") return composeBcc
    return composeTo
  }

  function setComposeAddr(role, value) {
    if (role === "cc") {
      composeCc = value
      if (composeCcField) composeCcField.text = value
    } else if (role === "bcc") {
      composeBcc = value
      if (composeBccField) composeBccField.text = value
    } else {
      composeTo = value
      if (composeToField) composeToField.text = value
    }
  }

  function composeAddrField(role) {
    if (role === "cc") return composeCcField
    if (role === "bcc") return composeBccField
    return composeToField
  }

  function focusComposeAddrNext(role) {
    if (role === "to" && composeShowCc) composeCcField.forceActiveFocus()
    else if ((role === "to" || role === "cc") && composeShowBcc) composeBccField.forceActiveFocus()
    else composeSubjectField.forceActiveFocus()
  }

  function openComposeCc() {
    composeShowCc = true
    Qt.callLater(function() { composeCcField.forceActiveFocus() })
  }

  function openComposeBcc() {
    composeShowBcc = true
    Qt.callLater(function() { composeBccField.forceActiveFocus() })
  }

  function fileUrlPath(u) {
    var s = String(u || "")
    if (s.indexOf("file://") === 0) s = s.slice(7)
    try { s = decodeURIComponent(s) } catch (e) {}
    return s
  }

  function pickOutgoingFiles() {
    if (filePicker.running || pickStartTimer.running) return
    keepCompose = true
    if (opened) close()
    pickStartTimer.restart()
  }

  function hasOpenDraft() {
    if (keepCompose || composing || forwarding || pendingForward || replyOpen) return true
    if (String(replyText || "").replace(/^\s+|\s+$/g, "") !== "") return true
    if (outgoingFiles && outgoingFiles.length) return true
    if (!composeDirty) return false
    return String(composeTo || "").replace(/^\s+|\s+$/g, "") !== ""
      || String(composeCc || "").replace(/^\s+|\s+$/g, "") !== ""
      || String(composeBcc || "").replace(/^\s+|\s+$/g, "") !== ""
      || String(composeSubject || "").replace(/^\s+|\s+$/g, "") !== ""
      || String(composeBody || "").replace(/^\s+|\s+$/g, "") !== ""
  }

  function restoreHeldCompose() {
    keepCompose = false
    if (pendingForward && selected && !conversationNeedsFetch(selected)) {
      startForward()
      return
    }
    paneFocus = "read"
    if (composeToField) composeToField.text = composeTo
    if (composeCcField) composeCcField.text = composeCc
    if (composeBccField) composeBccField.text = composeBcc
    if (composeSubjectField) composeSubjectField.text = composeSubject
    if (composeBodyField) composeBodyField.text = composeBody
    if (replyField) replyField.text = replyText
    composeShowCc = composeShowCc || String(composeCc || "").replace(/^\s+|\s+$/g, "") !== ""
    composeShowBcc = composeShowBcc || String(composeBcc || "").replace(/^\s+|\s+$/g, "") !== ""
    Qt.callLater(function() {
      if (composing && composeToField) composeToField.forceActiveFocus()
      else if (replyOpen && replyField) replyField.forceActiveFocus()
      else if (composePane && composeBodyField) composeBodyField.forceActiveFocus()
      else if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function addOutgoingFiles(urls) {
    var next = (outgoingFiles || []).slice()
    var seen = {}
    var i
    for (i = 0; i < next.length; i++) seen[next[i].path] = true
    var list = urls || []
    for (i = 0; i < list.length; i++) {
      var path = fileUrlPath(list[i])
      if (!path || seen[path]) continue
      seen[path] = true
      next.push({ path: path, name: path.split("/").pop() })
    }
    outgoingFiles = next
    markComposeDirty()
  }

  function removeOutgoingFile(path) {
    var next = []
    for (var i = 0; i < (outgoingFiles || []).length; i++) {
      if (outgoingFiles[i].path !== path) next.push(outgoingFiles[i])
    }
    outgoingFiles = next
    markComposeDirty()
  }

  function outgoingPaths() {
    var out = []
    for (var i = 0; i < (outgoingFiles || []).length; i++) {
      if (outgoingFiles[i] && outgoingFiles[i].path) out.push(outgoingFiles[i].path)
    }
    return out
  }

  function clearOutgoingFiles() {
    outgoingFiles = []
  }

  function openAttachment(message, att, action) {
    if (!liveMail || !message || !att) return
    var uid = Number(message.uid || 0)
    if (!uid) {
      var bits = String(message.id || "").split(":")
      uid = Number(bits[bits.length - 1] || 0)
    }
    mail.openAttachment({
      account: (selected && selected.accountId) ? selected.accountId : accountId,
      mailbox: message.mailbox || mailboxId,
      uid: uid,
      index: Number(att.index || 0),
      action: action || "open"
    })
  }

  function saveDraft() {
    if (composeBusy()) return
    var to = String(composeTo || "").replace(/^\s+|\s+$/g, "")
    var cc = String(composeCc || "").replace(/^\s+|\s+$/g, "")
    var bcc = String(composeBcc || "").replace(/^\s+|\s+$/g, "")
    var subject = String(composeSubject || "").replace(/^\s+|\s+$/g, "")
    var body = String(composeBody || "").replace(/^\s+|\s+$/g, "")
    if (to === "" && cc === "" && bcc === "" && subject === "" && body === "" && outgoingPaths().length === 0) return
    if (!liveMail) return
    var extra = {
      account: composeAccountId(),
      toList: Model.splitAddresses(composeTo),
      ccList: Model.splitAddresses(composeCc),
      bccList: Model.splitAddresses(composeBcc),
      subject: composeSubject,
      body: composeBody,
      files: outgoingPaths()
    }
    if (!composing && mailboxId === "drafts" && selected) {
      extra.uids = mail.mailboxUids(selected)
      extra.items = selected.items || []
      extra.conv = selected.id
    }
    mail.saveDraft(extra)
  }

  function sendReply() {
    if (!selected || composeBusy()) return
    var body = String(replyText || "").replace(/^\s+|\s+$/g, "")
    if (body === "" && outgoingPaths().length === 0) return
    if (!liveMail) return
    var to = replyToLabel
    if (to === "") {
      mail.sendError = "no recipient"
      return
    }
    var headers = Model.replyHeaders(selected)
    mail.sendMail({
      account: selected.accountId,
      mailbox: selected.mailbox || mailboxId,
      toList: Model.splitAddresses(to),
      ccList: Model.splitAddresses(replyCcLabel),
      subject: Model.replySubject(selected.subject),
      body: replyText,
      inReplyTo: headers.inReplyTo,
      references: headers.references,
      files: outgoingPaths(),
      conv: selected.id
    })
  }

  function markComposeDirty() {
    if (composeHydrating) return
    if (composeLoadedId !== "") composeDirty = true
  }

  function fillComposeFrom(conv) {
    if (composing || composeHold || !conv) return
    var nextTo = Model.conversationTo(conv)
    var nextCc = Model.conversationCc(conv)
    var nextBcc = Model.conversationBcc(conv)
    var nextSubject = conv.subject || ""
    var nextBody = Model.conversationBody(conv)
    if (nextBody === "" && String(composeBody || "") !== "") {
      composeLoadedId = conv.id
      return
    }
    composeHydrating = true
    composeTo = nextTo
    composeCc = nextCc
    composeBcc = nextBcc
    composeShowCc = nextCc !== ""
    composeShowBcc = nextBcc !== ""
    composeSubject = nextSubject
    composeBody = nextBody
    if (composeToField) composeToField.text = composeTo
    if (composeCcField) composeCcField.text = composeCc
    if (composeBccField) composeBccField.text = composeBcc
    if (composeSubjectField) composeSubjectField.text = composeSubject
    if (composeBodyField) composeBodyField.text = composeBody
    composeLoadedId = conv.id
    composeDirty = false
    composeSuggestIndex = 0
    composeHydrating = false
  }

  function syncComposeFromSelection() {
    if (composing || !outboundMailbox) return
    if (composeHold) {
      if (selected) composeLoadedId = selected.id
      return
    }
    if (!selected) return
    if (composeDirty && composeLoadedId === selected.id) {
      if (String(composeBody || "") === "") {
        var body = Model.conversationBody(selected)
        if (body !== "") {
          composeHydrating = true
          composeBody = body
          if (composeBodyField) composeBodyField.text = composeBody
          if (composeTo === "") composeTo = Model.conversationTo(selected)
          composeHydrating = false
        }
      }
      return
    }
    fillComposeFrom(selected)
  }

  function beginForward() {
    if (!selected) return
    if (liveMail && conversationNeedsFetch(selected)) {
      pendingForward = true
      mail.fetchThread(selected)
      return
    }
    startForward()
  }

  function startForward() {
    var conv = selected
    if (!conv) return
    pendingForward = false
    composing = true
    forwarding = true
    replyOpen = false
    composeHold = false
    suppressSelection = false
    composeHydrating = true
    clearComposeAddrs()
    composeSubject = Model.forwardSubject(conv.subject)
    composeBody = Model.forwardBody(conv)
    if (composeSubjectField) composeSubjectField.text = composeSubject
    if (composeBodyField) composeBodyField.text = composeBody
    composeSuggestIndex = 0
    composeDirty = true
    composeLoadedId = ""
    composeHydrating = false
    clearOutgoingFiles()
    mail.sendError = ""
    extractForwardFiles(conv)
    Qt.callLater(function() { composeToField.forceActiveFocus() })
  }

  function extractForwardFiles(conv) {
    if (!liveMail || !conv) return
    var msgs = conv.messages || []
    for (var i = 0; i < msgs.length; i++) {
      var msg = msgs[i]
      if (!msg) continue
      var atts = msg.attachments || []
      var uid = Number(msg.uid || 0)
      if (!uid) {
        var bits = String(msg.id || "").split(":")
        uid = Number(bits[bits.length - 1] || 0)
      }
      for (var a = 0; a < atts.length; a++) {
        mail.openAttachment({
          account: conv.accountId,
          mailbox: msg.mailbox || conv.mailbox || mailboxId,
          uid: uid,
          index: Number(atts[a].index || 0),
          action: "extract"
        })
      }
    }
  }

  function beginCompose() {
    if (!liveMail) {
      openSettings()
      return
    }
    composing = true
    forwarding = false
    pendingForward = false
    replyOpen = false
    composeHold = false
    suppressSelection = false
    composeHydrating = true
    clearComposeAddrs()
    composeSubject = ""
    composeBody = ""
    if (composeSubjectField) composeSubjectField.text = ""
    if (composeBodyField) composeBodyField.text = ""
    composeSuggestIndex = 0
    composeDirty = false
    composeLoadedId = ""
    composeHydrating = false
    clearOutgoingFiles()
    mail.sendError = ""
    Qt.callLater(function() { composeToField.forceActiveFocus() })
  }

  function cancelCompose() {
    composing = false
    forwarding = false
    pendingForward = false
    composeHold = false
    composeSuggestIndex = 0
    composeDirty = false
    composeLoadedId = ""
    clearOutgoingFiles()
    if (outboundMailbox && selected) fillComposeFrom(selected)
    else {
      composeHydrating = true
      clearComposeAddrs()
      composeSubject = ""
      composeBody = ""
      composeHydrating = false
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function acceptComposeSuggest() {
    var hit = composeMatches.length ? composeMatches[Math.max(0, Math.min(composeSuggestIndex, composeMatches.length - 1))] : null
    if (!hit) return false
    var role = composeAddrRole
    setComposeAddr(role, Model.completeAddress(composeAddrText(role), hit))
    composeSuggestIndex = 0
    return true
  }

  function composeSuggestCanAccept() {
    if (composeSuggestHidden || !composeMatches.length) return false
    var cur = composeAddrText(composeAddrRole)
    var draft = Model.addressDraft(cur)
    if (draft !== "") return true
    return String(cur || "").replace(/^\s+|\s+$/g, "") === ""
  }

  function handleComposeAddrKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (!composeSuggestHidden && composeMatches.length) {
        composeSuggestHidden = true
        event.accepted = true
        return
      }
    }
    if (event.key === Qt.Key_Down && composeMatches.length) {
      composeSuggestHidden = false
      composeSuggestIndex = Math.min(composeMatches.length - 1, composeSuggestIndex + 1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Up && composeMatches.length) {
      composeSuggestHidden = false
      composeSuggestIndex = Math.max(0, composeSuggestIndex - 1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Tab && composeSuggestCanAccept()) {
      acceptComposeSuggest()
      event.accepted = true
      return
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ControlModifier)) {
      if (composeSuggestCanAccept()) {
        acceptComposeSuggest()
        event.accepted = true
        return
      }
      focusComposeAddrNext(composeAddrRole)
      event.accepted = true
      return
    }
    handleEditorKey(event, sendCompose)
  }

  function sendCompose() {
    if (composeBusy()) return
    var to = String(composeTo || "").replace(/^\s+|\s+$/g, "")
    var cc = String(composeCc || "").replace(/^\s+|\s+$/g, "")
    var bcc = String(composeBcc || "").replace(/^\s+|\s+$/g, "")
    var body = String(composeBody || "").replace(/^\s+|\s+$/g, "")
    var files = outgoingPaths()
    if ((to === "" && cc === "" && bcc === "") || (body === "" && files.length === 0)) return
    if (!liveMail) return
    var recips = Model.splitAddresses(composeTo)
    var ccList = Model.splitAddresses(composeCc)
    var bccList = Model.splitAddresses(composeBcc)
    if (!recips.length && !ccList.length && !bccList.length) return
    var extra = {
      account: composeAccountId(),
      toList: recips,
      ccList: ccList,
      bccList: bccList,
      subject: composeSubject,
      body: composeBody,
      files: files
    }
    if (!composing && mailboxId === "drafts" && selected) {
      extra.uids = mail.mailboxUids(selected)
      extra.items = selected.items || []
      extra.conv = selected.id
    }
    mail.sendMail(extra)
  }

  function openSettings() {
    composing = false
    replyOpen = false
    gotoPending = false
    if (helpPopup.opened) helpPopup.close()
    settingsOpen = true
    if (!settingsAccountId && settingsAccounts.length > 0)
      selectSettingsAccount(settingsAccounts[0].id)
    else if (settingsAccountId)
      selectSettingsAccount(settingsAccountId)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeSettings() {
    settingsOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function loadSettingsFields(account) {
    settingsHydrating = true
    var acc = account || {}
    if (accNameField) accNameField.text = acc.name || ""
    if (accFromNameField) accFromNameField.text = acc.fromName || ""
    if (accEmailField) accEmailField.text = acc.email || ""
    if (imapHostField) imapHostField.text = acc.imapHost || ""
    if (imapPortField) imapPortField.text = acc.imapPort || ""
    if (smtpHostField) smtpHostField.text = acc.smtpHost || ""
    if (smtpPortField) smtpPortField.text = acc.smtpPort || ""
    if (accUserField) accUserField.text = acc.username || ""
    if (accPassField) accPassField.text = acc.password || ""
    settingsHydrating = false
  }

  function selectSettingsAccount(id) {
    settingsAccountId = id
    var next = accountDrafts[id]
      ? Model.copy(accountDrafts[id])
      : (Model.accountById(accounts, id) ? Model.normalizeAccount(Model.accountById(accounts, id)) : ({}))
    editing = next
    Qt.callLater(function() { root.loadSettingsFields(next) })
  }

  function patchEditing(key, value) {
    if (settingsHydrating || !editing || !editing.id) return
    var next = Model.normalizeAccount(editing)
    next[key] = value
    editing = next
    var drafts = Model.copy(accountDrafts)
    drafts[next.id] = next
    accountDrafts = drafts
  }

  function addAccount() {
    var account = Model.emptyAccount()
    account.name = "New account"
    var drafts = Model.copy(accountDrafts)
    drafts[account.id] = account
    accountDrafts = drafts
    selectSettingsAccount(account.id)
    Qt.callLater(function() { if (accNameField) accNameField.forceActiveFocus() })
  }

  function saveAccount() {
    if (!editingCanSave) return
    accounts = Model.upsertAccount(accounts, editing)
    var drafts = Model.copy(accountDrafts)
    delete drafts[editing.id]
    accountDrafts = drafts
    editing = Model.normalizeAccount(Model.accountById(accounts, editing.id))
    loadSettingsFields(editing)
    persistAccounts()
  }

  function removeSettingsAccount() {
    if (!settingsAccountId) return
    var id = settingsAccountId
    accounts = Model.removeAccount(accounts, id)
    var drafts = Model.copy(accountDrafts)
    delete drafts[id]
    accountDrafts = drafts
    if (accountId === id) accountId = "all"
    persistAccounts()
    if (settingsAccounts.length > 0) selectSettingsAccount(settingsAccounts[0].id)
    else {
      settingsAccountId = ""
      editing = ({})
    }
  }

  function selectSettingsAt(index) {
    if (settingsAccounts.length === 0) return
    var next = Math.max(0, Math.min(settingsAccounts.length - 1, index))
    selectSettingsAccount(settingsAccounts[next].id)
  }

  function accountDirty(id) {
    var draft = accountDrafts[id]
    if (!draft) return false
    var saved = Model.accountById(accounts, id)
    if (!saved) return true
    return !Model.accountsEqual(draft, saved)
  }

  function rowAt(index) {
    var kids = listColumn.children
    var rows = []
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] && kids[i].rowIndex !== undefined) rows.push(kids[i])
    }
    return index >= 0 && index < rows.length ? rows[index] : null
  }

  function scrollSelectedIntoView() {
    if (!listFlick || selectedIndex < 0) return
    Qt.callLater(function() {
      var item = root.rowAt(selectedIndex)
      if (!item || !listFlick) return
      var margin = Style.space(6)
      var point = item.mapToItem(listFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = listFlick.contentY
      var viewBottom = viewTop + listFlick.height
      var maxY = Math.max(0, listFlick.contentHeight - listFlick.height)
      if (top < viewTop + margin) listFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) listFlick.contentY = Math.min(maxY, bottom + margin - listFlick.height)
    })
  }

  function messageAddress(message) {
    var email = String(message && message.fromEmail ? message.fromEmail : "").replace(/^\s+|\s+$/g, "")
    if (email !== "") return email
    if (message && message.mine && selected) {
      var account = Model.accountById(accounts, selected.accountId)
      if (account && account.email) return account.email
    }
    return ""
  }

  function cssColor(c) {
    function hex(n) {
      var v = Math.max(0, Math.min(255, Math.round(Number(n) * 255)))
      return (v < 16 ? "0" : "") + v.toString(16)
    }
    if (!c) return "#ffffff"
    return "#" + hex(c.r) + hex(c.g) + hex(c.b)
  }

  function participantMarkup(conversation) {
    var selfEmails = Model.selfEmailMap(accounts, conversation && conversation.accountId)
    var parts = Model.listParticipantParts(conversation, selfEmails)
    if (parts.length === 0) return ""
    var sep = "<font color=\"" + cssColor(dim) + "\">, </font>"
    var bits = []
    for (var i = 0; i < parts.length; i++) {
      var color = senderColor({
        from: parts[i].name,
        fromEmail: parts[i].email,
        mine: parts[i].mine
      })
      bits.push("<font color=\"" + cssColor(color) + "\">" + Model.escapeHtml(parts[i].name) + "</font>")
    }
    return bits.join(sep)
  }

  function senderColor(message) {
    if (!message || message.mine) return contentForeground

    var hash = Model.senderHash(Model.senderKey(message))
    var accent = Color.accent
    var hue = accent.hslHue
    var sat = accent.hslSaturation
    var slots = [0, 0.11, 0.22, 0.36, 0.52, 0.70]
    var shift = slots[hash % slots.length]

    if (!(sat > 0.08) || isNaN(hue)) {
      hue = ((hash % 360) / 360)
      sat = 0.40
    } else {
      hue = (hue + shift) % 1
      sat = Math.max(0.34, Math.min(0.55, sat + 0.06))
    }

    var light = contentForeground.hslLightness
    if (isNaN(light)) light = 0.7
    if (light > 0.5) light = Math.max(0.30, light - 0.10)
    else light = Math.min(0.74, light + 0.14)

    return Qt.hsla(hue, sat, light, 1)
  }

  function handleSettingsKey(event) {
    if (event.key === Qt.Key_Escape) {
      keyCatcher.forceActiveFocus()
      event.accepted = true
    }
  }

  function toggleHelp() {
    if (helpPopup.opened) helpPopup.close()
    else helpPopup.open()
  }

  function handleTextKey(t) {
    var key = String(t || "")
    if (key.length !== 1) return
    var lower = key.toLowerCase()

    if (settingsOpen) {
      if (lower === "a") addAccount()
      else if (lower === "s") saveAccount()
      return
    }

    if (gotoPending) {
      gotoPending = false
      gotoTimer.stop()
      if (lower === "i") { setMailbox("inbox"); return }
      if (lower === "s") { setMailbox("sent"); return }
      if (lower === "d") { setMailbox("drafts"); return }
      if (lower === "t") { setMailbox("trash"); return }
      if (lower === "e") { setMailbox("archive"); return }
      if (lower === "b") { setMailbox("junk"); return }
      if (lower === "g") {
        gotoPending = true
        gotoTimer.restart()
        return
      }
    }

    if (lower === "g") {
      gotoPending = true
      gotoTimer.restart()
      return
    }
    if (key === "?") toggleHelp()
    else if (lower === "r") beginReply(false)
    else if (lower === "a") beginReply(true)
    else if (lower === "c") beginCompose()
    else if (lower === "f") beginForward()
    else if (lower === "e") archiveSelected()
    else if (key === "!") junkSelected()
    else if (lower === "u") toggleUnread()
    else if (lower === "s") openSettings()
    else if (key === "/") {
      listSearchField.forceActiveFocus()
      listSearchField.selectAll()
    }
    else if (key === "0") resetInbox()
  }

  function handleEditorKey(event, onEnter) {
    if (event.key === Qt.Key_Escape) {
      if (composing) cancelCompose()
      else if (replyOpen) cancelReply()
      else {
        paneFocus = "list"
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      }
      event.accepted = true
    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
      if (onEnter) onEnter()
      event.accepted = true
    } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier) && composePane) {
      saveDraft()
      event.accepted = true
    }
  }

  Component.onCompleted: resetInbox()

  onVisibleInboxChanged: ensureSelection()
  onSearchQueryChanged: {
    if (!liveMail) return
    var q = String(searchQuery || "").replace(/^\s+|\s+$/g, "")
    if (q === "") {
      searchDebounce.stop()
      mail.query = ""
      mail.loadList()
    } else {
      searchDebounce.restart()
    }
  }
  onComposeMatchesChanged: {
    if (composeSuggestIndex >= composeMatches.length)
      composeSuggestIndex = 0
  }

  Timer {
    id: searchDebounce
    interval: 250
    repeat: false
    onTriggered: root.syncLive()
  }

  Timer {
    id: fetchDebounce
    interval: 120
    repeat: false
    onTriggered: root.reloadSelected()
  }

  Timer {
    id: gotoTimer
    interval: 800
    repeat: false
    onTriggered: root.gotoPending = false
  }
  onSelectedIdChanged: {
    expandedIds = ({})
    if (threadFlick) threadFlick.contentY = 0
    if (composeHold) {
      composeLoadedId = selectedId
      return
    }
    if (selectedId !== composeLoadedId) composeDirty = false
    syncComposeFromSelection()
  }
  onSelectedChanged: {
    syncComposeFromSelection()
    if (pendingForward && selected && !conversationNeedsFetch(selected)) {
      pendingForward = false
      startForward()
    }
  }
  onMailboxIdChanged: {
    if (composing || composeHold) return
    composeDirty = false
    composeLoadedId = ""
    syncComposeFromSelection()
  }
  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (hasOpenDraft()) {
      restoreHeldCompose()
      if (liveMail) mail.refresh(true)
      return
    }
    composing = false
    replyOpen = false
    paneFocus = "list"
    gotoPending = false
    listCursorTouched = false
    if (helpPopup.opened) helpPopup.close()
    syncComposeFromSelection()
    ensureSelection()
    if (liveMail) mail.refresh(true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function reset(): void { root.resetInbox() }
  }

  function handleBarPress(b) {
    if (b === Qt.MiddleButton) root.resetInbox()
    else root.toggle()
  }

  WidgetButton {
    id: textButton
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.barLabel
    labelVisible: !root.vertical
    hasVisualContent: true
    tooltipText: root.tooltipText
    useActiveColor: false
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function(b) { root.handleBarPress(b) }

    Column {
      visible: root.vertical
      anchors.fill: parent

      OpticalGlyph {
        width: textButton.width
        height: Style.bar.iconSlot
        text: "󰇮"
        fontFamily: textButton.fontFamily
        fontSize: textButton.fontSize
        color: textButton.foreground
      }

      OpticalGlyph {
        width: textButton.width
        height: Style.bar.iconSlot
        text: root.barLabel
        fontFamily: textButton.fontFamily
        fontSize: textButton.fontSize
        color: textButton.active ? textButton.activeColor : textButton.foreground
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(920))
    contentHeight: panel.cappedContentHeight(Style.space(580))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.composing || replyField.editorFocused || composeToField.activeFocus
        || composeCcField.activeFocus || composeBccField.activeFocus
        || composeSubjectField.activeFocus || composeBodyField.editorFocused
        || mailboxPicker.popupOpen || root.settingsFieldFocused
        || listSearchField.activeFocus || helpPopup.opened || composeSuggestPopup.opened
      onMoveRequested: function(dx, dy) {
        if (root.settingsOpen) {
          if (dy !== 0) root.selectSettingsAt(root.settingsIndex + dy)
          return
        }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: {
        if (root.settingsOpen) root.saveAccount()
        else root.focusPane("read")
      }
      onDeleteRequested: {
        if (!root.settingsOpen) root.trashSelected()
      }
      onCloseRequested: {
        if (root.gotoPending) {
          root.gotoPending = false
          return
        }
        if (helpPopup.opened) {
          helpPopup.close()
          return
        }
        if (root.settingsOpen) root.closeSettings()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.handleTextKey(t) }

      Row {
        id: panes
        visible: !root.settingsOpen
        anchors.fill: parent
        spacing: 0

        Item {
          id: listPane
          width: Math.round(Math.min(Style.space(320), panes.width * 0.38))
          height: parent.height

          Column {
            id: listChrome
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(10)

            Item {
              width: parent.width
              height: Math.max(titleCol.height, composeBtn.height)

              Column {
                id: titleCol
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: "MAIL"
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                Text {
                  text: root.heroMeta
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                }
              }

              Button {
                id: composeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Compose"
                foreground: root.contentForeground
                onClicked: root.beginCompose()
              }
            }

            Row {
              width: parent.width
              height: root.filterChipHeight
              spacing: Style.spacing.md

              MailboxPicker {
                host: root
                id: mailboxPicker
                width: root.filterChipHeight
                height: root.filterChipHeight
              }

              Item {
                width: parent.width - mailboxPicker.width - parent.spacing
                height: parent.height

                Flickable {
                  id: accountChipFlick
                  anchors.fill: parent
                  clip: true
                  contentWidth: accountChipRow.implicitWidth
                  contentHeight: height
                  flickableDirection: Flickable.HorizontalFlick
                  boundsBehavior: Flickable.StopAtBounds
                  interactive: contentWidth > width

                  Row {
                    id: accountChipRow
                    spacing: Style.spacing.md
                    height: accountChipFlick.height

                    FilterChip {
                      host: root
                      value: "all"
                      chipLabel: "All"
                      hint: ""
                      selected: root.accountId === "all"
                      onPicked: root.setAccount(value)
                    }

                    Repeater {
                      model: root.accounts

                      FilterChip {
                        host: root
                        required property var modelData
                        required property int index
                        value: modelData.id
                        chipLabel: modelData.name
                        hint: ""
                        selected: root.accountId === modelData.id
                        onPicked: root.setAccount(value)
                      }
                    }
                  }

                  WheelHandler {
                    onWheel: function(event) {
                      var maxX = Math.max(0, accountChipFlick.contentWidth - accountChipFlick.width)
                      if (maxX <= 0) return
                      var delta = event.pixelDelta.x !== 0 ? event.pixelDelta.x : (event.angleDelta.y / 8)
                      accountChipFlick.contentX = Math.max(0, Math.min(maxX, accountChipFlick.contentX - delta))
                      event.accepted = true
                    }
                  }
                }

                Rectangle {
                  visible: accountChipFlick.contentWidth > accountChipFlick.width + 1
                    && accountChipFlick.contentX < accountChipFlick.contentWidth - accountChipFlick.width - 1
                  anchors.right: parent.right
                  width: Style.space(20)
                  height: parent.height
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Color.popups.background }
                  }
                }
              }
            }

            Row {
              visible: root.liveMail && mail.lastError !== ""
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width - retryBtn.width - parent.spacing
                text: mail.lastError
                color: root.urgent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Button {
                id: retryBtn
                text: "Retry"
                foreground: root.contentForeground
                enabled: !mail.loading
                onClicked: mail.retry()
              }
            }

            Item {
              width: parent.width
              height: listSearchField.implicitHeight

              TextField {
                id: listSearchField
                width: parent.width
                placeholderText: "Search this folder"
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                rightPadding: horizontalPadding + (root.searchBusy ? Style.space(18) : 0)
                onTextChanged: root.searchQuery = text
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    if (listSearchField.text !== "") {
                      listSearchField.text = ""
                      root.searchQuery = ""
                    } else {
                      keyCatcher.forceActiveFocus()
                    }
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    keyCatcher.forceActiveFocus()
                    event.accepted = true
                  }
                }
              }

              Text {
                visible: root.searchBusy
                enabled: false
                anchors.right: parent.right
                anchors.rightMargin: listSearchField.horizontalPadding
                anchors.verticalCenter: parent.verticalCenter
                text: "󰑐"
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                transformOrigin: Item.Center

                RotationAnimator on rotation {
                  running: root.searchBusy
                  from: 0
                  to: 360
                  duration: 800
                  loops: Animation.Infinite
                }
              }
            }
          }

          MailFlickable {
            id: listFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.top: listChrome.bottom
            anchors.topMargin: Style.space(10)
            anchors.bottom: listFooter.top
            anchors.bottomMargin: Style.space(8)
            contentWidth: width
            contentHeight: listColumn.implicitHeight
            scrollScale: 2
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: listColumn
              width: listFlick.width
              spacing: Style.space(4)

              Repeater {
                model: root.visibleInbox

                ConversationRow {
                  host: root
                  required property var modelData
                  required property int index
                  width: listColumn.width
                  conversation: modelData
                  rowIndex: index
                }
              }
            }
          }

          Column {
            visible: root.visibleInbox.length === 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: listChrome.bottom
            anchors.topMargin: Style.space(36)
            spacing: Style.space(12)

            Text {
              width: parent.width
              text: root.emptyLabel
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            Button {
              visible: !root.liveMail
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Settings"
              foreground: root.contentForeground
              onClicked: root.openSettings()
            }
          }

          Item {
            id: listFooter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.bottom: parent.bottom
            height: listSettingsBtn.height

            PanelActionButton {
              id: listSettingsBtn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒓"
              tooltipText: "Settings · s"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.openSettings()
            }

            PanelActionButton {
              id: listHelpBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰌌"
              tooltipText: "Shortcuts · ?"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.toggleHelp()
            }

            Popup {
              id: helpPopup
              parent: listHelpBtn
              x: listHelpBtn.width - width
              y: -height - Style.spacing.xxs
              padding: Style.space(10)
              focus: true
              closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

              background: BorderSurface {
                color: Color.popups.background
                borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
                radius: Style.cornerRadius
              }

              onOpened: helpColumn.forceActiveFocus()
              onClosed: keyCatcher.forceActiveFocus()

              contentItem: Column {
                id: helpColumn
                spacing: Style.space(5)
                focus: true

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape || event.text === "?") {
                    helpPopup.close()
                    event.accepted = true
                  }
                }

                Text {
                  text: "SHORTCUTS"
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }

                Repeater {
                  model: [
                    { keys: "j k", action: "Move or scroll" },
                    { keys: "h l", action: "List / message" },
                    { keys: "e", action: "Archive" },
                    { keys: "!", action: "Junk" },
                    { keys: "x", action: "Trash or delete" },
                    { keys: "r", action: "Reply" },
                    { keys: "a", action: "Reply all" },
                    { keys: "c", action: "Compose" },
                    { keys: "f", action: "Forward" },
                    { keys: "Ctrl+S", action: "Save draft" },
                    { keys: "/", action: "Search" },
                    { keys: "s", action: "Settings" },
                    { keys: "g i", action: "Go to inbox" },
                    { keys: "g s", action: "Go to sent" },
                    { keys: "g d", action: "Go to drafts" },
                    { keys: "g e", action: "Go to archive" },
                    { keys: "g b", action: "Go to junk" },
                    { keys: "g t", action: "Go to trash" },
                    { keys: "?", action: "Shortcuts" }
                  ]

                  Row {
                    required property var modelData
                    width: Style.space(220)
                    spacing: Style.space(12)

                    Text {
                      width: Style.space(48)
                      text: modelData.keys
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      text: modelData.action
                      color: root.dim
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }
          }
        }

        Rectangle {
          width: Style.space(1)
          height: parent.height
          color: Util.alpha(root.contentForeground, 0.12)
        }

        Item {
          id: readPane
          width: panes.width - listPane.width - Style.space(1)
          height: parent.height

          Rectangle {
            visible: root.paneFocus === "read" && (root.composing || root.selected)
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Style.space(2)
            color: Color.accent
          }

          MouseArea {
            anchors.fill: parent
            enabled: !root.composing && root.selected && !root.composePane
            acceptedButtons: Qt.LeftButton
            propagateComposedEvents: true
            onPressed: function(mouse) {
              root.focusPane("read")
              mouse.accepted = false
            }
          }

          ComposePane {
            id: composePane
            host: root
            anchors.fill: parent
          }


          Column {
            visible: !root.composePane && root.selected
            anchors.fill: parent
            anchors.leftMargin: Style.space(16)
            spacing: Style.space(10)

            Item {
              width: parent.width
              height: Math.max(threadTitle.implicitHeight, actionRow.implicitHeight)

              Text {
                id: threadTitle
                anchors.left: parent.left
                anchors.right: actionRow.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: root.selected ? root.selected.subject : ""
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                wrapMode: Text.WordWrap
              }

              Row {
                id: actionRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                PanelActionButton {
                  iconText: "󰑚"
                  tooltipText: "Reply · r"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.beginReply(false)
                }
                PanelActionButton {
                  iconText: "󰑛"
                  tooltipText: "Reply all · a"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.beginReply(true)
                }
                PanelActionButton {
                  iconText: "󰒖"
                  tooltipText: "Forward · f"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.beginForward()
                }
                PanelActionButton {
                  iconText: root.mailboxId === "archive" ? "󰻪" : "󰀼"
                  tooltipText: root.mailboxId === "archive" ? "Move to inbox · e" : "Archive · e"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.archiveSelected()
                }
                PanelActionButton {
                  iconText: root.mailboxId === "junk" ? "󰻪" : "󰯈"
                  tooltipText: root.mailboxId === "junk" ? "Not junk · !" : "Junk · !"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.junkSelected()
                }
                PanelActionButton {
                  iconText: "󰩹"
                  tooltipText: (root.mailboxId === "sent" || root.mailboxId === "trash" || root.mailboxId === "junk")
                    ? "Delete forever · x"
                    : "Trash · x"
                  foreground: root.contentForeground
                  hoverColor: root.urgent
                  fontFamily: root.contentFontFamily
                  onClicked: root.trashSelected()
                }
              }
            }

            Item {
              width: parent.width
              height: Math.max(accountMeta.implicitHeight, countMeta.implicitHeight)

              Text {
                id: accountMeta
                anchors.left: parent.left
                anchors.right: countMeta.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: root.selected ? Model.accountName(root.accounts, root.selected.accountId) : ""
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: countMeta
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.selected
                  ? (Model.threadCount(root.selected) + (Model.threadCount(root.selected) === 1 ? " message" : " messages"))
                  : ""
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            MailFlickable {
              id: threadFlick
              width: parent.width
              height: parent.height - y - (root.replyOpen ? replyBox.height + Style.space(10) : 0)
              contentWidth: width
              contentHeight: threadColumn.implicitHeight
              interactive: contentHeight > height
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: threadColumn
                width: threadFlick.width
                spacing: Style.space(12)

                Text {
                  visible: root.liveMail && root.selected && (!root.selected.messages || root.selected.messages.length === 0)
                  width: parent.width
                  text: (mail.lastError !== "" && mail.fetchingId === "" && !fetchDebounce.running)
                    ? "Couldn't load this conversation."
                    : "Loading…"
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                Repeater {
                  model: root.selected ? root.selected.messages : []

                  ThreadMessage {
                    host: root
                    required property var modelData
                    required property int index
                    width: threadColumn.width
                    message: modelData
                    messageIndex: index
                    messageCount: root.selected ? root.selected.messages.length : 0
                  }
                }
              }
            }

            Column {
              id: replyBox
              visible: root.replyOpen
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: parent.width
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: "To  " + root.replyToLabel
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: root.replyCcLabel !== ""
                  width: parent.width
                  text: "Cc  " + root.replyCcLabel
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
              }

              BodyField {
                id: replyField
                host: root
                width: parent.width
                height: Style.space(96)
                placeholderText: root.replyAll ? "Reply all in plain text" : "Reply in plain text"
                text: root.replyText
                onTextChanged: root.replyText = text
                Keys.onPressed: function(event) { root.handleEditorKey(event, root.sendReply) }
              }

              Flow {
                visible: root.outgoingFiles.length > 0
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.outgoingFiles

                  Rectangle {
                    required property var modelData
                    implicitWidth: replyAttachLabel.implicitWidth + Style.space(14)
                    implicitHeight: Math.max(Style.space(22), replyAttachLabel.implicitHeight + Style.space(8))
                    radius: Style.cornerRadius
                    color: replyAttachMouse.containsMouse
                      ? Style.hoverFillFor(root.contentForeground, Color.accent)
                      : Style.normalFillFor(root.contentForeground, Color.accent)

                    Text {
                      id: replyAttachLabel
                      anchors.centerIn: parent
                      text: "󰁦  " + modelData.name + "  ×"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    MouseArea {
                      id: replyAttachMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.removeOutgoingFile(modelData.path)
                    }
                  }
                }
              }

              Row {
                spacing: Style.space(8)

                Button {
                  text: mail.sending ? "Sending…" : "Send"
                  foreground: root.contentForeground
                  enabled: !root.composeBusy()
                  onClicked: root.sendReply()
                }

                Button {
                  text: (filePicker.running || pickStartTimer.running) ? "Attach…" : "Attach"
                  foreground: root.contentForeground
                  enabled: !root.composeBusy() && !filePicker.running && !pickStartTimer.running
                  onClicked: root.pickOutgoingFiles()
                }

                Button {
                  text: "Cancel"
                  foreground: root.contentForeground
                  enabled: !root.composeBusy()
                  onClicked: root.cancelReply()
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: mail.sendError !== "" ? mail.sendError : "Ctrl+Enter to send"
                  color: mail.sendError !== "" ? root.urgent : root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Text {
            visible: !root.composePane && !root.selected
            anchors.centerIn: parent
            text: "Select a conversation"
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      SettingsPane {
        id: settingsPane
        host: root
        anchors.fill: parent
      }
    }
  }
}
