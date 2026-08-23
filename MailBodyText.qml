import QtQuick
import qs.Commons

// Read-only selectable body. Qt Text cannot select; TextEdit can.
TextEdit {
  id: body
  property var host
  property string html
  property string plain
  height: contentHeight
  readOnly: true
  selectByMouse: true
  persistentSelection: true
  cursorVisible: false
  activeFocusOnPress: false
  activeFocusOnTab: false
  wrapMode: TextEdit.Wrap
  textFormat: html !== "" ? TextEdit.RichText : TextEdit.PlainText
  textMargin: 0
  color: host ? host.contentForeground : Color.foreground
  selectedTextColor: host ? host.contentForeground : Color.foreground
  selectionColor: Qt.alpha(Color.accent, 0.4)
  font.family: host ? host.contentFontFamily : Style.font.family
  font.pixelSize: Style.font.body
  // RichText ignores Text.linkColor and falls back to default blue.
  text: html !== ""
    ? ("<style>a, a:visited { color: " + Color.accent + "; }</style>" + html)
    : plain
  onLinkActivated: function(link) { if (host) host.openLink(link) }

  HoverHandler {
    cursorShape: body.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
  }

  Shortcut {
    enabled: body.selectedText !== ""
    sequences: [StandardKey.Copy]
    context: Qt.WindowShortcut
    onActivated: body.copy()
  }
}
