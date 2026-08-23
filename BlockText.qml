import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  property var host
    property var block
    property bool quoteOpen: false
    spacing: Style.space(4)

    readonly property string bodyText: block.type === "list"
      ? String(block.text).split("\n").map(function(line) { return "·  " + line }).join("\n")
      : String(block.text || "")
    readonly property bool isQuote: block.type === "quote" || block.type === "history"
    readonly property bool quoteCollapsible: block.type === "history"
    readonly property bool quoteExpanded: isQuote && (!quoteCollapsible || quoteOpen)

    CursorSurface {
      visible: isQuote && quoteCollapsible && !quoteOpen
      width: parent.width
      hasCursor: quoteMouse.containsMouse
      current: false
      foreground: host.contentForeground
      implicitHeight: Math.max(quoteChevron.implicitHeight, quoteLabel.implicitHeight) + Style.space(10)

      MouseArea {
        id: quoteMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: quoteOpen = true
      }

      Text {
        id: quoteChevron
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "󰅂"
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: quoteLabel
        anchors.left: quoteChevron.right
        anchors.leftMargin: Style.space(6)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "Quoted text  ·  " + Model.previewSnippet(block.text)
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.NoWrap
        maximumLineCount: 1
        elide: Text.ElideRight
      }
    }

    Item {
      visible: isQuote && quoteExpanded && quoteCollapsible
      width: parent.width
      height: Math.max(hideChevron.implicitHeight, hideLabel.implicitHeight)

      Text {
        id: hideChevron
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "󰅀"
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: hideLabel
        anchors.left: hideChevron.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: "Quoted text"
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: quoteOpen = false
      }
    }

    Row {
      visible: isQuote && quoteExpanded
      width: parent.width
      spacing: Style.space(10)

      Rectangle {
        width: Style.space(2)
        height: quoteText.implicitHeight
        color: Color.accent
      }

      Text {
        id: quoteText
        width: parent.width - Style.space(12)
        text: Model.formatBlock(bodyText)
        textFormat: Text.StyledText
        color: host.dim
        linkColor: Color.accent
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        onLinkActivated: function(link) { host.openLink(link) }
        HoverHandler { cursorShape: quoteText.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
      }
    }

    Text {
      visible: !isQuote
      width: parent.width
      text: Model.formatBlock(bodyText)
      textFormat: Text.StyledText
      color: host.contentForeground
      linkColor: Color.accent
      font.family: host.contentFontFamily
      font.pixelSize: block.type === "heading" ? Style.font.title : Style.font.body
      font.bold: block.type === "heading"
      wrapMode: Text.WordWrap
      onLinkActivated: function(link) { host.openLink(link) }
      HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
  }
