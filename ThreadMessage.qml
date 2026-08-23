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
      var key = host.messageKey(message, messageIndex)
      if (ids[key] === true) return true
      if (ids[key] === false) return false
      return Model.messageOpenByDefault(message, isLatest)
    }
    readonly property string address: host.messageAddress(message)
    readonly property bool showAddress: address !== ""
      && address.toLowerCase() !== String(message.from || "").toLowerCase()
    readonly property string toLabel: Model.formatAddressList(message && message.to, true)
    readonly property string ccLabel: Model.formatAddressList(message && message.cc, true)
    spacing: 0

    Item {
      width: parent.width
      height: messageIndex === 0 ? 0 : Math.max(0, Style.space(12) - 2)
    }

    CursorSurface {
      visible: !expanded
      width: parent.width
      hasCursor: collapsedMouse.containsMouse
      current: true
      foreground: host.contentForeground
      currentFill: Style.normalFillFor(host.contentForeground, Color.accent)
      implicitHeight: Math.max(collapsedFrom.implicitHeight, collapsedWhen.implicitHeight) + Style.space(12)

      MouseArea {
        id: collapsedMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: host.toggleMessageExpanded(message, messageIndex)
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
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
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
      spacing: Style.space(10)

      Column {
        width: parent.width
        spacing: Style.space(2)

        Item {
          width: parent.width
          height: Math.max(fromText.implicitHeight, stampText.implicitHeight)

          Text {
            id: fromText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - stampText.implicitWidth - Style.space(12))
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
              visible: showAddress && fromMouse.containsMouse
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
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: host.toggleMessageExpanded(message, messageIndex)
          }
        }

        MailBodyText {
          visible: toLabel !== ""
          host: threadMessage.host
          width: parent.width
          color: threadMessage.host.dim
          font.pixelSize: Style.font.bodySmall
          plain: Model.formatAddressMultiline("To", message && message.to, true)
        }

        MailBodyText {
          visible: ccLabel !== ""
          host: threadMessage.host
          width: parent.width
          color: threadMessage.host.dim
          font.pixelSize: Style.font.bodySmall
          plain: Model.formatAddressMultiline("Cc", message && message.cc, true)
        }
      }

      Flow {
        visible: message.attachments && message.attachments.length
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: message.attachments || []

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
        model: Model.bodyRuns(message.blocks || [])

        BlockText {
          required property var modelData
          host: threadMessage.host
          width: parent.width
          run: modelData
        }
      }
    }

    Item {
      width: parent.width
      height: Math.max(0, Style.space(12) - 2)
    }

    PanelSeparator {
      visible: messageIndex < messageCount - 1
      width: parent.width
      foreground: host.contentForeground
      strength: 0.10
    }
  }
