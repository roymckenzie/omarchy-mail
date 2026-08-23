import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  property var host
    id: picker
    readonly property bool popupOpen: mailboxPopup.opened
    readonly property var options: [
      { value: "inbox", label: "Inbox", icon: "󰻪" },
      { value: "sent", label: "Sent", icon: "󰒊" },
      { value: "drafts", label: "Drafts", icon: "󰷈" },
      { value: "archive", label: "Archive", icon: "󰀼" },
      { value: "junk", label: "Junk", icon: "󰯈" },
      { value: "trash", label: "Trash", icon: "󰩹" }
    ]

    function optionAt(index) {
      return index >= 0 && index < options.length ? options[index] : null
    }

    function indexOfValue(v) {
      for (var i = 0; i < options.length; i++) {
        if (options[i].value === v) return i
      }
      return 0
    }

    function currentOption() {
      return options[indexOfValue(host.mailboxId)]
    }

    readonly property string currentIcon: currentOption().icon
    readonly property string currentLabel: currentOption().label

    implicitWidth: height
    implicitHeight: Style.spacing.controlHeight

    function toggle() {
      mailboxPopup.opened ? mailboxPopup.close() : mailboxPopup.open()
    }

    BorderSurface {
      id: trigger
      anchors.fill: parent
      radius: Style.cornerRadius
      color: triggerMouse.containsMouse || mailboxPopup.opened
        ? Style.hoverFillFor(host.contentForeground, Color.accent)
        : "transparent"
      borderSpec: Border.controlSpec(
        (triggerMouse.containsMouse || mailboxPopup.opened) ? "hover-cursor" : "normal",
        host.contentForeground, Color.accent)

      Text {
        anchors.centerIn: parent
        text: picker.currentIcon
        color: host.contentForeground
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.icon
      }

      MouseArea {
        id: triggerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: picker.toggle()
      }

      PanelToolTip {
        visible: triggerMouse.containsMouse && !mailboxPopup.opened
        text: picker.currentLabel
        fontFamily: host.contentFontFamily
        x: 0
        y: trigger.height + Style.space(4)
      }

      Popup {
        id: mailboxPopup
        x: 0
        y: trigger.height + Style.spacing.xxs
        width: Style.space(160)
        padding: Style.spacing.hairline
        focus: true

        background: BorderSurface {
          color: Color.popups.background
          borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
          radius: Style.cornerRadius
        }

        onOpened: {
          optionList.currentIndex = picker.indexOfValue(host.mailboxId)
          optionList.forceActiveFocus()
        }

        contentItem: ListView {
          id: optionList
          implicitHeight: contentHeight
          clip: true
          spacing: Style.spacing.labelGap
          boundsBehavior: Flickable.StopAtBounds
          model: picker.options
          currentIndex: -1

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              mailboxPopup.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.text === "j") {
              optionList.currentIndex = Math.min(picker.options.length - 1, optionList.currentIndex + 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              optionList.currentIndex = Math.max(0, optionList.currentIndex - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              optionList.selectCurrent()
              event.accepted = true
            }
          }

          function selectCurrent() {
            var opt = picker.optionAt(currentIndex)
            if (!opt) return
            host.setMailbox(opt.value)
            mailboxPopup.close()
          }

          delegate: Item {
            required property var modelData
            required property int index
            width: optionList.width
            height: Style.spacing.popupRowHeight

            Rectangle {
              anchors.fill: parent
              color: index === optionList.currentIndex
                ? Style.hoverFillFor(host.contentForeground, Color.accent)
                : "transparent"
            }

            Text {
              id: rowIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.icon
              color: host.contentForeground
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.icon
            }

            Text {
              anchors.left: rowIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: index === optionList.currentIndex
                ? Style.hoverStateColor(host.contentForeground, Color.accent)
                : host.contentForeground
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: optionList.currentIndex = parent.index
              onClicked: optionList.selectCurrent()
            }
          }
        }
      }
    }
  }
