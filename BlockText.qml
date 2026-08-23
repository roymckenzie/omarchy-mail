import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: pane
  property var host
    property var run
    property bool quoteOpen: false
    spacing: Style.space(4)

    readonly property var block: run && run.block ? run.block : null
    readonly property string bodyText: Model.blockPlainText(block)
    readonly property bool isQuote: run && run.kind === "quote"
    readonly property bool quoteCollapsible: !!(block && block.type === "history")
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
        height: quoteText.height
        color: Color.accent
      }

      MailBodyText {
        id: quoteText
        host: pane.host
        width: parent.width - Style.space(12)
        html: Model.formatBlock(bodyText)
        color: pane.host ? pane.host.dim : Color.foreground
      }
    }

    MailBodyText {
      visible: !isQuote
      host: pane.host
      width: parent.width
      html: Model.formatBodyRun(run && run.blocks ? run.blocks : [])
    }
  }
