import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: threadMessage
  property var host
    property var message
    property int messageIndex: 0
    property int messageCount: 1
    readonly property bool isLatest: messageCount <= 1 || messageIndex === messageCount - 1
    readonly property bool expanded: {
      var ids = host.expandedIds
      return isLatest || ids[host.messageKey(message, messageIndex)] === true
    }
    readonly property string address: host.messageAddress(message)
    readonly property bool showAddress: address !== ""
      && address.toLowerCase() !== String(message.from || "").toLowerCase()
    readonly property string toLabel: Model.formatAddressList(message && message.to, true)
    readonly property string ccLabel: Model.formatAddressList(message && message.cc, true)
    property bool toOpen: false
    property bool ccOpen: false
    spacing: expanded ? Style.space(10) : Style.space(4)

    onMessageChanged: {
      toOpen = false
      ccOpen = false
    }

    CursorSurface {
      visible: !expanded
      width: parent.width
      hasCursor: collapsedMouse.containsMouse
      current: false
      foreground: host.contentForeground
      implicitHeight: Math.max(collapsedFrom.implicitHeight, collapsedWhen.implicitHeight) + Style.space(12)

      MouseArea {
        id: collapsedMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: host.toggleMessageExpanded(message, messageIndex)
      }

      Text {
        id: collapsedChevron
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "󰅂"
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: collapsedWhen
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.formatStamp(message.when)
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: collapsedFrom
        anchors.left: collapsedChevron.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(Style.space(72), parent.width * 0.28))
        text: message.from
        color: host.senderColor(message)
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        anchors.left: collapsedFrom.right
        anchors.leftMargin: Style.space(10)
        anchors.right: collapsedWhen.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.messageSnippet(message)
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.NoWrap
        maximumLineCount: 1
        elide: Text.ElideRight
      }

      PanelToolTip {
        visible: collapsedMouse.containsMouse && showAddress
        text: address
        fontFamily: host.contentFontFamily
      }
    }

    Column {
      visible: expanded
      width: parent.width
      spacing: Style.space(2)

      Item {
        width: parent.width
        height: Math.max(fromText.implicitHeight, stampText.implicitHeight)

        Text {
          id: expandChevron
          visible: !isLatest
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰅀"
          color: host.dim
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: fromText
          anchors.left: isLatest ? parent.left : expandChevron.right
          anchors.leftMargin: isLatest ? 0 : Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width - stampText.implicitWidth - Style.space(12) - (isLatest ? 0 : expandChevron.implicitWidth + Style.space(6)))
          text: message.from
          color: host.senderColor(message)
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight

          MouseArea {
            id: fromMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
          }

          PanelToolTip {
            visible: isLatest && showAddress && fromMouse.containsMouse
            text: address
            fontFamily: host.contentFontFamily
            x: 0
            y: fromText.height + Style.space(4)
          }
        }

        Text {
          id: stampText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: Model.formatStamp(message.when)
          color: host.dim
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          anchors.fill: parent
          enabled: !isLatest
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: host.toggleMessageExpanded(message, messageIndex)
        }
      }

      Text {
        id: toText
        visible: toLabel !== ""
        width: parent.width
        text: toOpen ? Model.formatAddressMultiline("To", message && message.to, true) : ("To  " + toLabel)
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: toOpen ? Text.Wrap : Text.NoWrap
        elide: toOpen ? Text.ElideNone : Text.ElideRight

        MouseArea {
          anchors.fill: parent
          enabled: toText.truncated || toOpen || (message.to && message.to.length > 1)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: toOpen = !toOpen
        }
      }

      Text {
        id: ccText
        visible: ccLabel !== ""
        width: parent.width
        text: ccOpen ? Model.formatAddressMultiline("Cc", message && message.cc, true) : ("Cc  " + ccLabel)
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: ccOpen ? Text.Wrap : Text.NoWrap
        elide: ccOpen ? Text.ElideNone : Text.ElideRight

        MouseArea {
          anchors.fill: parent
          enabled: ccText.truncated || ccOpen || (message.cc && message.cc.length > 1)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: ccOpen = !ccOpen
        }
      }
    }

    Flow {
      visible: expanded && message.attachments && message.attachments.length
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: expanded ? (message.attachments || []) : []

        Rectangle {
          required property var modelData
          implicitWidth: attachLabel.implicitWidth + Style.space(14)
          implicitHeight: Math.max(Style.space(22), attachLabel.implicitHeight + Style.space(8))
          radius: Style.cornerRadius
          color: attachMouse.containsMouse
            ? Style.hoverFillFor(host.contentForeground, Color.accent)
            : Style.normalFillFor(host.contentForeground, Color.accent)

          Text {
            id: attachLabel
            anchors.centerIn: parent
            text: "󰁦  " + modelData.name + "  " + Model.formatBytes(modelData.size)
            color: host.contentForeground
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: attachMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
              host.openAttachment(message, modelData, mouse.button === Qt.RightButton ? "save" : "open")
            }
          }

          PanelToolTip {
            visible: attachMouse.containsMouse
            text: "Open · click   Save · right-click"
            fontFamily: host.contentFontFamily
          }
        }
      }
    }

    Repeater {
      model: expanded ? (message.blocks || []) : []

      BlockText {
        required property var modelData
        host: threadMessage.host
        width: parent.width
        block: modelData
      }
    }

    PanelSeparator {
      visible: messageIndex < messageCount - 1
      width: parent.width
      foreground: host.contentForeground
      strength: 0.10
    }
  }
