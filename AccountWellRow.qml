import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

CursorSurface {
  property var host
    property var account
    property int rowIndex: 0
    readonly property bool isSelected: host.settingsAccountId === account.id
    readonly property bool dirty: host.accountDirty(account.id)

    hasCursor: isSelected
    current: isSelected
    foreground: host.contentForeground
    implicitHeight: wellCol.implicitHeight + Style.space(12)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: host.selectSettingsAccount(account.id)
      onClicked: host.selectSettingsAccount(account.id)
    }

    Column {
      id: wellCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width - Style.space(16)
          text: account.name || "New account"
          color: host.contentForeground
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: isSelected
          elide: Text.ElideRight
        }

        Rectangle {
          visible: dirty
          width: Style.space(6)
          height: Style.space(6)
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: Color.accent
        }
      }

      Text {
        width: parent.width
        text: account.email || "No address"
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }
