.pragma library
// Pure helpers for the QML UI (addresses, filters, reply-all). No widget state.

function copy(value) {
  return JSON.parse(JSON.stringify(value))
}

function accountById(accounts, id) {
  for (var i = 0; i < accounts.length; i++) {
    if (accounts[i].id === id) return accounts[i]
  }
  return null
}

function accountName(accounts, id) {
  var account = accountById(accounts, id)
  return account ? account.name : id
}

function resolvedComposeAccountId(accounts, fromId, filterId, selectedId, defaultId) {
  if (fromId && accountById(accounts, fromId)) return fromId
  if (filterId && filterId !== "all") return filterId
  if (defaultId && accountById(accounts, defaultId)) return defaultId
  if (selectedId && selectedId !== "all") return selectedId
  if (accounts && accounts.length) return accounts[0].id
  return ""
}

function decodeMailtoPart(value) {
  var s = String(value || "").replace(/\+/g, " ")
  try { return decodeURIComponent(s) } catch (e) { return s }
}

function parseMailto(url) {
  var raw = String(url || "").replace(/^\s+|\s+$/g, "")
  if (raw.toLowerCase().indexOf("mailto:") === 0) raw = raw.slice(7)
  var q = raw.indexOf("?")
  var path = q < 0 ? raw : raw.slice(0, q)
  var query = q < 0 ? "" : raw.slice(q + 1)
  var to = []
  var pathTo = decodeMailtoPart(path).replace(/^\s+|\s+$/g, "")
  if (pathTo !== "") to.push(pathTo)
  var cc = "", bcc = "", subject = "", body = ""
  if (query !== "") {
    var parts = query.split("&")
    for (var i = 0; i < parts.length; i++) {
      var bit = parts[i]
      var eq = bit.indexOf("=")
      var key = decodeMailtoPart(eq < 0 ? bit : bit.slice(0, eq)).toLowerCase()
      var val = decodeMailtoPart(eq < 0 ? "" : bit.slice(eq + 1))
      if (key === "to" && val) to.push(val)
      else if (key === "cc") cc = cc ? cc + ", " + val : val
      else if (key === "bcc") bcc = bcc ? bcc + ", " + val : val
      else if (key === "subject") subject = val
      else if (key === "body") body = val
    }
  }
  return { to: to.join(", "), cc: cc, bcc: bcc, subject: subject, body: body }
}

function mailboxOf(conversation) {
  return conversation && conversation.mailbox ? conversation.mailbox : "inbox"
}

function queryHaystack(conversation) {
  if (!conversation) return ""
  var bits = [
    conversation.subject || "",
    conversation.preview || "",
    participantLabel(conversation) || ""
  ]
  function addPeople(list) {
    for (var i = 0; i < (list || []).length; i++) {
      var part = list[i]
      if (!part) continue
      if (typeof part === "string") {
        bits.push(part)
        continue
      }
      bits.push(part.name || "")
      bits.push(part.email || "")
    }
  }
  addPeople(conversation.participants)
  addPeople(conversation.to)
  var messages = conversation.messages || []
  for (var m = 0; m < messages.length; m++) {
    var msg = messages[m]
    if (!msg) continue
    bits.push(msg.from || "")
    bits.push(msg.fromEmail || "")
    var blocks = msg.blocks || []
    for (var b = 0; b < blocks.length; b++) bits.push(blocks[b] && blocks[b].text || "")
  }
  return bits.join("\n").toLowerCase()
}

function matchesQuery(conversation, query) {
  var q = String(query || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  if (q === "") return true
  if (!conversation) return false
  var hay = queryHaystack(conversation)
  var tokens = q.split(/\s+/)
  for (var i = 0; i < tokens.length; i++) {
    if (hay.indexOf(tokens[i]) < 0) return false
  }
  return true
}

function filtered(inbox, accountId, mailboxId, query) {
  if (!inbox) return []
  var box = mailboxId || "inbox"
  var out = []
  for (var i = 0; i < inbox.length; i++) {
    if (mailboxOf(inbox[i]) !== box) continue
    if (accountId && accountId !== "all" && inbox[i].accountId !== accountId) continue
    if (!matchesQuery(inbox[i], query)) continue
    out.push(inbox[i])
  }
  return out
}

function unreadCount(inbox, accountId) {
  var list = filtered(inbox, accountId, "inbox")
  var n = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i].unread) n += 1
  }
  return n
}

function indexOfId(list, id) {
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === id) return i
  }
  return -1
}

function conversationById(inbox, id) {
  var index = indexOfId(inbox, id)
  return index >= 0 ? inbox[index] : null
}

function participantName(part) {
  if (!part) return ""
  if (typeof part === "string") return part
  return String(part.name || part.email || "")
}

function selfEmailMap(accounts, accountId) {
  var mine = {}
  for (var i = 0; i < (accounts || []).length; i++) {
    if (accountId && accountId !== "all" && accounts[i].id !== accountId) continue
    var email = String(accounts[i] && accounts[i].email ? accounts[i].email : "").toLowerCase()
    if (email !== "") mine[email] = true
  }
  return mine
}

function isSelfEmail(email, selfEmails) {
  var addr = String(email || "").toLowerCase()
  return addr !== "" && selfEmails && selfEmails[addr] === true
}

function participantParts(conversation, selfEmails) {
  var out = []
  var seen = {}
  function add(name, email, mine) {
    var label = String(name || "").replace(/^\s+|\s+$/g, "")
    var addr = String(email || "").replace(/^\s+|\s+$/g, "")
    if (label === "" && addr === "") return
    if (isSelfEmail(addr, selfEmails)) mine = true
    if (mine) label = "You"
    if (label === "") label = addr
    var key = addr !== "" ? addr.toLowerCase() : label.toLowerCase()
    if (seen[key]) return
    seen[key] = true
    out.push({ name: label, email: addr, mine: mine === true })
  }

  function addList(list) {
    for (var i = 0; i < (list || []).length; i++) {
      var part = list[i]
      if (!part) continue
      if (typeof part === "string") add(part, "", part === "You")
      else add(participantName(part), part.email, part.mine)
    }
  }

  var messages = conversation && conversation.messages ? conversation.messages : []
  if (messages.length) {
    for (var m = 0; m < messages.length; m++) {
      var msg = messages[m]
      if (!msg) continue
      var name = msg.mine ? "You" : (msg.from || msg.fromEmail || "")
      add(name, msg.fromEmail || "", msg.mine === true)
    }
  } else {
    addList(conversation && conversation.participants)
  }
  return out
}

function listParticipantParts(conversation, selfEmails) {
  var sent = conversation && conversation.latestMine === true
  var messages = conversation && conversation.messages ? conversation.messages : []
  for (var i = 0; i < messages.length; i++) {
    if (messages[i] && messages[i].mine) sent = true
  }
  var parts = participantParts(conversation, selfEmails)
  var out = []
  var addedYou = false
  for (var p = 0; p < parts.length; p++) {
    if (parts[p].mine) {
      if (sent && !addedYou) {
        out.push({ name: "You", email: parts[p].email, mine: true })
        addedYou = true
      }
      continue
    }
    out.push(parts[p])
  }
  return out
}

function participantLabel(conversation) {
  var parts = participantParts(conversation)
  var names = []
  for (var i = 0; i < parts.length; i++) names.push(parts[i].name)
  return names.join(", ")
}

function formatBytes(n) {
  var size = Number(n) || 0
  if (size < 1000) return size + " B"
  if (size < 1000 * 1000) {
    var kb = size / 1000
    return (kb < 10 ? kb.toFixed(1) : Math.round(kb)) + " KB"
  }
  var mb = size / 1000000
  return (mb < 10 ? mb.toFixed(1) : Math.round(mb)) + " MB"
}

function conversationHasFiles(conversation) {
  var msgs = conversation && conversation.messages ? conversation.messages : []
  for (var i = 0; i < msgs.length; i++) {
    if (msgs[i] && msgs[i].attachments && msgs[i].attachments.length) return true
  }
  return false
}

function threadCount(conversation) {
  if (!conversation) return 0
  var messages = conversation.messages
  if (messages && messages.length) return messages.length
  var items = conversation.items
  if (items && items.length) return items.length
  var uids = conversation.uids
  if (uids && uids.length) return uids.length
  return 0
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear()
    && a.getMonth() === b.getMonth()
    && a.getDate() === b.getDate()
}

function previewSnippet(text) {
  var s = String(text || "")
  s = s.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  s = s.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
  s = s.replace(/\s+/g, " ")
  return s.replace(/^\s+|\s+$/g, "")
}

function messageSnippet(message) {
  if (!message) return ""
  return previewFromMessages([message])
}

function previewFromMessages(messages) {
  if (!messages || !messages.length) return ""
  var last = messages[messages.length - 1]
  var blocks = last && last.blocks ? last.blocks : []
  var parts = []
  for (var i = 0; i < blocks.length; i++) {
    if (blocks[i] && blocks[i].type === "history") continue
    var bit = previewSnippet(blocks[i] && blocks[i].text)
    if (bit === "") continue
    parts.push(bit)
    if (parts.join(" ").length >= 180) break
  }
  return previewSnippet(parts.join(" "))
}

function filterByAccount(list, accountId) {
  if (!list) return []
  if (!accountId || accountId === "all") return list
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].accountId === accountId) out.push(list[i])
  }
  return out
}

function filterByMailbox(list, mailboxId) {
  if (!list) return []
  if (!mailboxId) return list
  var out = []
  for (var i = 0; i < list.length; i++) {
    var box = list[i].mailbox ? list[i].mailbox : "inbox"
    if (box === mailboxId) out.push(list[i])
  }
  return out
}

function formatWhen(iso, nowMs) {
  if (!iso) return ""
  var date = new Date(iso)
  if (isNaN(date.getTime())) return ""
  var now = new Date(nowMs || Date.now())
  if (sameDay(date, now)) return pad2(date.getHours()) + ":" + pad2(date.getMinutes())

  var yesterday = new Date(now)
  yesterday.setDate(now.getDate() - 1)
  if (sameDay(date, yesterday)) return "Yesterday"

  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[date.getMonth()] + " " + date.getDate()
}

function formatStamp(iso) {
  if (!iso) return ""
  var date = new Date(iso)
  if (isNaN(date.getTime())) return ""
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[date.getMonth()] + " " + date.getDate() + "  " + pad2(date.getHours()) + ":" + pad2(date.getMinutes())
}

function nextId(prefix) {
  return prefix + "-" + Date.now().toString(36)
}

function replaceConversation(inbox, conversation) {
  var next = inbox.slice()
  var index = indexOfId(next, conversation.id)
  if (index < 0) return next
  next[index] = conversation
  return next
}

function removeConversation(inbox, id) {
  var next = []
  for (var i = 0; i < (inbox || []).length; i++) {
    if (inbox[i].id !== id) next.push(inbox[i])
  }
  return next
}

function moveToMailbox(inbox, id, mailbox) {
  var conversation = conversationById(inbox, id)
  if (!conversation) return inbox
  var box = mailbox || "inbox"
  if (mailboxOf(conversation) === box) return inbox
  var nextConv = copy(conversation)
  nextConv.mailbox = box
  if (box !== "inbox") nextConv.unread = false
  var next = replaceConversation(inbox, nextConv)
  var index = indexOfId(next, id)
  if (index > 0) {
    var moved = next.splice(index, 1)[0]
    next.unshift(moved)
  }
  return next
}

function markRead(inbox, id, unread) {
  var conversation = conversationById(inbox, id)
  if (!conversation) return inbox
  var nextConv = copy(conversation)
  nextConv.unread = unread === true
  return replaceConversation(inbox, nextConv)
}

function appendReply(inbox, id, text, fromEmail) {
  var body = String(text || "").replace(/^\s+|\s+$/g, "")
  if (body === "") return inbox
  var conversation = conversationById(inbox, id)
  if (!conversation) return inbox
  var nextConv = copy(conversation)
  if (!nextConv.messages) nextConv.messages = []
  var now = new Date().toISOString()
  nextConv.messages.push({
    id: nextId("m"),
    from: "You",
    fromEmail: fromEmail || "",
    mine: true,
    when: now,
    text: body,
    blocks: [{ type: "p", text: body }]
  })
  nextConv.preview = previewSnippet(body)
  nextConv.when = now
  nextConv.unread = false
  var next = replaceConversation(inbox, nextConv)
  var index = indexOfId(next, id)
  if (index > 0) {
    var moved = next.splice(index, 1)[0]
    next.unshift(moved)
  }
  return next
}

function formatAddressList(parts, includeMine) {
  var bits = []
  for (var i = 0; i < (parts || []).length; i++) {
    var part = parts[i]
    if (!part) continue
    if (part.mine && !includeMine) continue
    var formatted = formatAddress(part.name, part.email)
    if (formatted !== "") bits.push(formatted)
  }
  return bits.join(", ")
}

function formatAddressMultiline(label, parts, includeMine) {
  var bits = []
  for (var i = 0; i < (parts || []).length; i++) {
    var part = parts[i]
    if (!part) continue
    if (part.mine && !includeMine) continue
    var formatted = formatAddress(part.name, part.email)
    if (formatted !== "") bits.push(formatted)
  }
  if (!bits.length) return ""
  var prefix = String(label || "") + "  "
  var pad = Array(prefix.length + 1).join(" ")
  var out = prefix + bits[0]
  for (var b = 1; b < bits.length; b++) out += "\n" + pad + bits[b]
  return out
}

function outboundMessage(conversation) {
  var messages = conversation && conversation.messages ? conversation.messages : []
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i] && messages[i].mine) return messages[i]
  }
  return messages.length ? messages[messages.length - 1] : null
}

function conversationTo(conversation) {
  var msg = outboundMessage(conversation)
  if (msg && msg.to && msg.to.length) return formatAddressList(msg.to, true)
  if (conversation && conversation.to && conversation.to.length)
    return formatAddressList(conversation.to, true)
  return formatAddressList(participantParts(conversation), false)
}

function conversationCc(conversation) {
  var msg = outboundMessage(conversation)
  if (msg && msg.cc && msg.cc.length) return formatAddressList(msg.cc, true)
  return ""
}

function conversationBcc(conversation) {
  var msg = outboundMessage(conversation)
  if (msg && msg.bcc && msg.bcc.length) return formatAddressList(msg.bcc, true)
  return ""
}

function messagePlainText(message) {
  if (!message) return ""
  if (String(message.text || "") !== "") return String(message.text)
  var blocks = message.blocks || []
  var parts = []
  for (var i = 0; i < blocks.length; i++) {
    if (!blocks[i] || blocks[i].type === "history") continue
    var t = String(blocks[i].text || "")
    if (t === "") continue
    if (blocks[i].type === "quote") {
      t = t.split("\n").map(function(line) { return "> " + line }).join("\n")
    }
    parts.push(t)
  }
  return parts.join("\n\n")
}

function conversationBody(conversation) {
  return messagePlainText(outboundMessage(conversation))
}

function formatAddress(name, email) {
  var addr = String(email || "").replace(/^\s+|\s+$/g, "")
  var label = String(name || "").replace(/^\s+|\s+$/g, "")
  if (addr === "") return label
  if (label === "" || label.toLowerCase() === addr.toLowerCase() || label === "You") return addr
  return label + " <" + addr + ">"
}

function splitAddresses(text) {
  var s = String(text || "")
  var out = []
  var cur = ""
  var depth = 0
  for (var i = 0; i < s.length; i++) {
    var ch = s.charAt(i)
    if (ch === "<") depth += 1
    else if (ch === ">" && depth > 0) depth -= 1
    if ((ch === "," || ch === ";") && depth === 0) {
      var token = cur.replace(/^\s+|\s+$/g, "")
      if (token !== "") out.push(token)
      cur = ""
      continue
    }
    cur += ch
  }
  var last = cur.replace(/^\s+|\s+$/g, "")
  if (last !== "") out.push(last)
  return out
}

function addressPrefix(text) {
  var s = String(text || "")
  var depth = 0
  var last = 0
  for (var i = 0; i < s.length; i++) {
    var ch = s.charAt(i)
    if (ch === "<") depth += 1
    else if (ch === ">" && depth > 0) depth -= 1
    if ((ch === "," || ch === ";") && depth === 0) last = i + 1
  }
  return s.slice(0, last)
}

function addressDraft(text) {
  return String(text || "").slice(addressPrefix(text).length).replace(/^\s+|\s+$/g, "")
}

function completeAddress(text, contact) {
  var prefix = addressPrefix(text).replace(/^\s+|\s+$/g, "").replace(/[,;]+$/, "")
  var formatted = formatAddress(contact && contact.name, contact && contact.email)
  if (formatted === "") return String(text || "")
  if (prefix === "") return formatted + ", "
  return prefix + ", " + formatted + ", "
}

function mergeContacts(existing, incoming) {
  var out = []
  var seen = {}
  function add(c) {
    if (!c) return
    var email = String(c.email || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    if (email === "" || email.indexOf("@") < 0) return
    var name = String(c.name || "").replace(/^\s+|\s+$/g, "")
    if (name.toLowerCase() === email || name === "You") name = email
    if (seen[email]) {
      if (name && name !== email && (!seen[email].name || seen[email].name === email))
        seen[email].name = name
      return
    }
    var row = { name: name || email, email: email }
    seen[email] = row
    out.push(row)
  }
  for (var i = 0; i < (incoming || []).length; i++) add(incoming[i])
  for (var j = 0; j < (existing || []).length; j++) add(existing[j])
  if (out.length > 400) out = out.slice(0, 400)
  return out
}

function filterContacts(list, query, limit) {
  var q = String(query || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  var cap = limit || 8
  var out = []
  for (var i = 0; i < (list || []).length && out.length < cap; i++) {
    var c = list[i]
    if (!c) continue
    if (q === "") {
      out.push(c)
      continue
    }
    var name = String(c.name || "").toLowerCase()
    var email = String(c.email || "").toLowerCase()
    if (name.indexOf(q) >= 0 || email.indexOf(q) >= 0) out.push(c)
  }
  return out
}

function contactsFromInbox(inbox, accounts) {
  var mine = {}
  for (var a = 0; a < (accounts || []).length; a++) {
    var email = String(accounts[a] && accounts[a].email ? accounts[a].email : "").toLowerCase()
    if (email !== "") mine[email] = true
  }
  var incoming = []
  for (var i = 0; i < (inbox || []).length; i++) {
    var parts = participantParts(inbox[i])
    for (var p = 0; p < parts.length; p++) {
      if (!parts[p] || parts[p].mine) continue
      var em = String(parts[p].email || "").toLowerCase()
      if (mine[em]) continue
      incoming.push(parts[p])
    }
  }
  return mergeContacts([], incoming)
}

function replyAddress(conversation, accountEmail) {
  var messages = conversation && conversation.messages ? conversation.messages : []
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i] && !messages[i].mine && messages[i].fromEmail)
      return formatAddress(messages[i].from, messages[i].fromEmail)
  }
  var msg = outboundMessage(conversation)
  if (msg && msg.to && msg.to.length) {
    var to = formatAddressList(msg.to, true)
    if (to !== "") return to
  }
  if (conversation && conversation.to && conversation.to.length) {
    var envelopeTo = formatAddressList(conversation.to, true)
    if (envelopeTo !== "") return envelopeTo
  }
  var parts = participantParts(conversation)
  for (var j = 0; j < parts.length; j++) {
    if (!parts[j].mine && parts[j].email)
      return formatAddress(parts[j].name, parts[j].email)
  }
  for (var k = 0; k < parts.length; k++) {
    if (parts[k] && parts[k].email)
      return formatAddress(parts[k].name, parts[k].email)
  }
  if (msg && msg.fromEmail)
    return formatAddress(msg.from, msg.fromEmail)
  var self = String(accountEmail || "").replace(/^\s+|\s+$/g, "")
  return self
}

function replyAllRecipients(conversation, accountEmail) {
  var self = String(accountEmail || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  var seen = {}
  var to = []
  var cc = []
  function add(bucket, name, email) {
    var em = String(email || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    if (em === "" || em.indexOf("@") < 0) return
    if (self && em === self) return
    if (seen[em]) return
    seen[em] = true
    bucket.push(formatAddress(name, em))
  }
  function addList(bucket, list) {
    for (var i = 0; i < (list || []).length; i++) {
      var part = list[i]
      if (!part) continue
      if (typeof part === "string") add(bucket, part, part)
      else add(bucket, part.name, part.email)
    }
  }
  var messages = conversation && conversation.messages ? conversation.messages : []
  var msg = null
  for (var m = messages.length - 1; m >= 0; m--) {
    if (messages[m]) {
      msg = messages[m]
      break
    }
  }
  if (msg) {
    if (!msg.mine) {
      add(to, msg.from, msg.fromEmail)
      addList(cc, msg.to)
      addList(cc, msg.cc)
    } else {
      addList(to, msg.to)
      addList(cc, msg.cc)
    }
  } else {
    addList(to, conversation && conversation.to)
    addList(cc, conversation && conversation.participants)
  }
  if (!to.length && cc.length) to.push(cc.shift())
  if (!to.length) return { to: replyAddress(conversation, accountEmail), cc: "" }
  return { to: to.join(", "), cc: cc.join(", ") }
}

function replySubject(subject) {
  var s = String(subject || "").replace(/^\s+|\s+$/g, "")
  if (s === "") return ""
  if (/^re\s*:/i.test(s)) return s
  return "Re: " + s
}

function forwardSubject(subject) {
  var s = String(subject || "").replace(/^\s+|\s+$/g, "")
  if (s === "") return "Fwd:"
  if (/^fwd\s*:/i.test(s) || /^fw\s*:/i.test(s)) return s
  return "Fwd: " + s
}

function forwardedMessage(message, subject) {
  if (!message) return ""
  var lines = ["---------- Forwarded message ----------"]
  var from = formatAddress(message.from, message.fromEmail)
  if (from !== "") lines.push("From: " + from)
  var when = formatStamp(message.when)
  if (when === "") when = String(message.when || "")
  if (when !== "") lines.push("Date: " + when)
  var title = String(subject || "").replace(/^\s+|\s+$/g, "")
  if (title !== "") lines.push("Subject: " + title)
  var to = formatAddressList(message.to, true)
  if (to !== "") lines.push("To: " + to)
  var cc = formatAddressList(message.cc, true)
  if (cc !== "") lines.push("Cc: " + cc)
  lines.push("")
  var body = messagePlainText(message)
  if (body !== "") lines.push(body)
  return lines.join("\n")
}

function forwardBody(conversation) {
  var messages = conversation && conversation.messages ? conversation.messages : []
  if (!messages.length) {
    var preview = conversation && conversation.preview ? String(conversation.preview) : ""
    return "---------- Forwarded message ----------\n\n" + preview
  }
  var bits = []
  var subject = conversation && conversation.subject ? conversation.subject : ""
  for (var i = 0; i < messages.length; i++) {
    var block = forwardedMessage(messages[i], subject)
    if (block !== "") bits.push(block)
  }
  return bits.join("\n\n")
}

function replyHeaders(conversation) {
  var messages = conversation && conversation.messages ? conversation.messages : []
  var last = null
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i] && messages[i].messageId) {
      last = messages[i]
      break
    }
  }
  if (!last) return { inReplyTo: "", references: "" }
  var mid = String(last.messageId || "").replace(/^\s+|\s+$/g, "")
  var refs = String(last.references || "").replace(/^\s+|\s+$/g, "")
  if (refs === "") refs = String(last.inReplyTo || "").replace(/^\s+|\s+$/g, "")
  if (mid !== "" && refs.indexOf(mid) < 0) refs = (refs !== "" ? refs + " " : "") + mid
  return { inReplyTo: mid, references: refs }
}

function startConversation(inbox, accountId, to, subject, body, mailbox) {
  var text = String(body || "").replace(/^\s+|\s+$/g, "")
  var title = String(subject || "").replace(/^\s+|\s+$/g, "")
  var who = String(to || "").replace(/^\s+|\s+$/g, "")
  var box = mailbox || "inbox"
  if (box !== "drafts" && (text === "" || who === "")) return inbox
  if (box === "drafts" && text === "" && who === "" && title === "") return inbox
  if (title === "") title = "(no subject)"
  var now = new Date().toISOString()
  var conversation = {
    id: nextId("c"),
    accountId: accountId === "all" ? "work" : accountId,
    mailbox: box,
    unread: false,
    subject: title,
    preview: previewSnippet(text) || who || title,
    when: now,
    participants: who !== "" ? [who] : ["You"],
    messages: [
      {
        id: nextId("m"),
        from: "You",
        fromEmail: "",
        mine: true,
        when: now,
        blocks: [{ type: "p", text: text }]
      }
    ]
  }
  var next = inbox.slice()
  next.unshift(conversation)
  return next
}

function senderKey(message) {
  if (!message) return ""
  var email = String(message.fromEmail || "").toLowerCase()
  if (email !== "") return email
  return String(message.from || "").toLowerCase()
}

function senderHash(key) {
  var s = String(key || "")
  var h = 2166136261
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

var accountKeys = [
  "id", "name", "fromName", "email", "imapHost", "imapPort", "imapTls",
  "smtpHost", "smtpPort", "smtpTls", "username", "password"
]

function accountFromName(account) {
  if (!account) return ""
  var from = String(account.fromName || "").replace(/^\s+|\s+$/g, "")
  if (from !== "") return from
  return String(account.name || "").replace(/^\s+|\s+$/g, "")
}

function accountTemplate() {
  return {
    id: "",
    name: "",
    fromName: "",
    email: "",
    imapHost: "",
    imapPort: "993",
    imapTls: true,
    smtpHost: "",
    smtpPort: "465",
    smtpTls: true,
    username: "",
    password: ""
  }
}

function emptyAccount() {
  var account = accountTemplate()
  account.id = nextId("acct")
  return account
}

function normalizeAccount(account) {
  var out = accountTemplate()
  if (!account) {
    out.id = nextId("acct")
    return out
  }
  for (var i = 0; i < accountKeys.length; i++) {
    var key = accountKeys[i]
    if (account[key] !== undefined && account[key] !== null) out[key] = account[key]
  }
  if (String(out.id) === "") out.id = nextId("acct")
  out.imapTls = out.imapTls !== false
  out.smtpTls = out.smtpTls !== false
  out.imapPort = String(out.imapPort || "993")
  out.smtpPort = String(out.smtpPort || "465")
  return out
}

function accountsEqual(a, b) {
  return JSON.stringify(normalizeAccount(a)) === JSON.stringify(normalizeAccount(b))
}

function upsertAccount(list, account) {
  var next = (list || []).slice()
  var acc = normalizeAccount(account)
  var index = indexOfId(next, acc.id)
  if (index < 0) next.push(acc)
  else next[index] = acc
  return next
}

function removeAccount(list, id) {
  var next = []
  for (var i = 0; i < (list || []).length; i++) {
    if (list[i].id !== id) next.push(list[i])
  }
  return next
}

function settingsAccountList(saved, drafts) {
  var list = []
  var seen = {}
  for (var i = 0; i < (saved || []).length; i++) {
    var acc = saved[i]
    list.push(drafts && drafts[acc.id] ? drafts[acc.id] : acc)
    seen[acc.id] = true
  }
  if (drafts) {
    for (var id in drafts) {
      if (!seen[id]) list.push(drafts[id])
    }
  }
  return list
}

function accountCanSave(account) {
  if (!account) return false
  return String(account.name || "").replace(/^\s+|\s+$/g, "") !== ""
    && String(account.email || "").replace(/^\s+|\s+$/g, "") !== ""
    && String(account.imapHost || "").replace(/^\s+|\s+$/g, "") !== ""
    && String(account.smtpHost || "").replace(/^\s+|\s+$/g, "") !== ""
}

function accountForDisk(account) {
  var out = normalizeAccount(account)
  var hasPassword = String(account && account.password ? account.password : "") !== ""
    || account && account.hasPassword === true
  delete out.password
  out.hasPassword = hasPassword
  return out
}

function defaultPrefs() {
  return { notifications: true, defaultAccountId: "" }
}

function normalizePrefs(prefs) {
  var out = defaultPrefs()
  if (!prefs) return out
  if (prefs.notifications === false) out.notifications = false
  out.defaultAccountId = String(prefs.defaultAccountId || "")
  return out
}

function parsePrefs(raw) {
  var text = String(raw || "").replace(/^\s+|\s+$/g, "")
  if (text === "") return defaultPrefs()
  try {
    var data = JSON.parse(text)
  } catch (e) {
    return defaultPrefs()
  }
  if (!data || Array.isArray(data)) return defaultPrefs()
  return normalizePrefs(data)
}

function serializeConfig(list, prefs) {
  var accounts = []
  for (var i = 0; i < (list || []).length; i++) accounts.push(accountForDisk(list[i]))
  var p = normalizePrefs(prefs)
  return JSON.stringify({
    version: 1,
    accounts: accounts,
    notifications: p.notifications,
    defaultAccountId: p.defaultAccountId
  }, null, 2) + "\n"
}

function serializeAccounts(list) {
  return serializeConfig(list, null)
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

function safeUrl(url) {
  var href = String(url || "").replace(/^\s+|\s+$/g, "")
  if (/^https?:\/\//i.test(href) || /^mailto:/i.test(href)) return href
  return ""
}

function formatBlock(text) {
  var s = String(text || "")
  s = s.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  s = s.replace(/[ \t\u00a0]+\n/g, "\n")
  s = s.replace(/\n[ \t\u00a0]+/g, "\n")
  s = s.replace(/\n{3,}/g, "\n\n")
  s = s.replace(/^\n+|\n+$/g, "")
  s = escapeHtml(s)
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, label, url) {
    var href = safeUrl(url)
    if (!href) return label
    return "<a href=\"" + escapeHtml(href) + "\">" + label + "</a>"
  })
  s = s.replace(/(^|[^"'>=])(https?:\/\/[^\s<]+)/gi, function(_, pre, url) {
    var trail = ""
    var core = url.replace(/[),.:;!?]+$/, function(m) { trail = m; return "" })
    var href = safeUrl(core)
    if (!href) return pre + url
    return pre + "<a href=\"" + escapeHtml(href) + "\">" + core + "</a>" + trail
  })
  s = s.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
  s = s.replace(/`([^`]+)`/g, "<b>$1</b>")
  s = s.replace(/(^|[^\*])\*([^*\n]+)\*(?!\*)/g, "$1<i>$2</i>")
  return s.replace(/\n/g, "<br/>")
}

function isQuoteBlock(block) {
  return !!(block && (block.type === "quote" || block.type === "history"))
}

function blockPlainText(block) {
  var text = String(block && block.text || "")
  if (block && block.type === "list")
    return text.split("\n").map(function(line) { return "·  " + line }).join("\n")
  return text
}

function formatBodyRun(blocks) {
  var parts = []
  for (var i = 0; i < (blocks || []).length; i++) {
    var block = blocks[i]
    if (!block) continue
    var html = formatBlock(blockPlainText(block))
    if (block.type === "heading") html = "<b>" + html + "</b>"
    if (html !== "") parts.push(html)
  }
  return parts.join("<br/><br/>")
}

function messageOpenByDefault(message, isLatest) {
  if (isLatest) return true
  return !!(message && message.unread)
}

function messageKey(message, index) {
  if (message && message.id) return String(message.id)
  return "idx-" + index
}

function defaultExpandedIds(messages) {
  var next = {}
  var list = messages || []
  for (var i = 0; i < list.length; i++) {
    var latest = list.length <= 1 || i === list.length - 1
    next[messageKey(list[i], i)] = messageOpenByDefault(list[i], latest)
  }
  return next
}

function bodyRuns(blocks) {
  var runs = []
  var current = null
  for (var i = 0; i < (blocks || []).length; i++) {
    var block = blocks[i]
    if (!block) continue
    if (isQuoteBlock(block)) {
      if (current) {
        runs.push(current)
        current = null
      }
      runs.push({ kind: "quote", block: block })
    } else {
      if (!current) current = { kind: "body", blocks: [] }
      current.blocks.push(block)
    }
  }
  if (current) runs.push(current)
  return runs
}

function pluginFile(url) {
  var value = String(url || "")
  if (value.indexOf("file://") === 0) {
    value = decodeURIComponent(value.slice(7))
    if (/^\/[A-Za-z]:\//.test(value)) value = value.slice(1)
  }
  return value
}

function parseAccounts(raw) {
  var text = String(raw || "").replace(/^\s+|\s+$/g, "")
  if (text === "") return []
  try {
    var data = JSON.parse(text)
  } catch (e) {
    return []
  }
  var src = []
  if (data && Array.isArray(data.accounts)) src = data.accounts
  else if (Array.isArray(data)) src = data
  var out = []
  for (var i = 0; i < src.length; i++) {
    var acc = normalizeAccount(src[i])
    acc.password = ""
    acc.hasPassword = src[i] && src[i].hasPassword === true
    out.push(acc)
  }
  return out
}
