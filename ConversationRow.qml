import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

CursorSurface {
  property var host
    property var conversation
    property int rowIndex: 0
    readonly property bool isSelected: host.selectedId === conversation.id

    hasCursor: rowMouse.containsMouse
    current: isSelected
    foreground: host.contentForeground

    implicitHeight: rowCol.implicitHeight + Style.space(12)

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        host.paneFocus = "list"
        host.composeHold = false
        host.suppressSelection = false
        host.listCursorTouched = true
        host.selectedId = conversation.id
        host.openSelected()
      }
    }

    Column {
      id: rowCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(2)

      Item {
        width: parent.width
        height: Math.max(whoText.implicitHeight, whenText.implicitHeight)

        Rectangle {
          id: unreadDot
          width: Style.space(6)
          height: Style.space(6)
          radius: width / 2
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          color: {
            var flags = host.mailUnreadFlags
            var id = conversation.id
            var unread = (flags && id && flags[id] !== undefined) ? flags[id] === true : conversation.unread
            return unread ? Color.accent : "transparent"
          }
        }

        Text {
          id: whenText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: Model.formatWhen(conversation.when, host.nowMs)
          color: host.dim
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: fileMark
          visible: Model.conversationHasFiles(conversation)
          anchors.right: whenText.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: "󰁦"
          color: host.dim
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          id: whoText
          anchors.left: unreadDot.right
          anchors.leftMargin: Style.space(8)
          anchors.right: fileMark.visible ? fileMark.left : whenText.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: {
            var _fg = host.contentForeground
            var _dim = host.dim
            var _accent = Color.accent
            return host.participantMarkup(conversation)
          }
          textFormat: Text.StyledText
          color: host.contentForeground
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: {
            var flags = host.mailUnreadFlags
            var id = conversation.id
            return (flags && id && flags[id] !== undefined) ? flags[id] === true : conversation.unread
          }
          elide: Text.ElideRight
        }
      }

      Text {
        width: parent.width
        leftPadding: Style.space(14)
        text: conversation.subject
        color: host.contentForeground
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Item {
        width: parent.width
        height: Math.max(previewText.implicitHeight, countBadge.visible ? countBadge.height : 0)

        Rectangle {
          id: countBadge
          visible: Model.threadCount(conversation) > 1
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: Math.max(Style.space(18), countLabel.implicitWidth + Style.space(8))
          implicitHeight: Math.max(Style.space(16), countLabel.implicitHeight + Style.space(2))
          radius: Style.cornerRadius
          color: Style.selectedFillFor(host.contentForeground, Color.accent)

          Text {
            id: countLabel
            anchors.centerIn: parent
            text: String(Model.threadCount(conversation))
            color: host.contentForeground
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          id: previewText
          anchors.left: parent.left
          anchors.leftMargin: Style.space(14)
          anchors.right: countBadge.visible ? countBadge.left : parent.right
          anchors.rightMargin: countBadge.visible ? Style.space(10) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: Model.previewSnippet(conversation.preview)
          color: host.dim
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.NoWrap
          maximumLineCount: 1
          elide: Text.ElideRight
        }
      }
    }
  }
