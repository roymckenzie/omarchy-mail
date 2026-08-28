import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: pane
  property var host
  visible: host && host.composePane
  readonly property var composeToField: composeToFieldImpl
  readonly property var composeCcField: composeCcFieldImpl
  readonly property var composeBccField: composeBccFieldImpl
  readonly property var composeSubjectField: composeSubjectFieldImpl
  readonly property var composeBodyField: composeBodyFieldImpl
  readonly property var composeSuggestPopup: composeSuggestPopupImpl
  readonly property var composeFromPopup: composeFromPopupImpl
  readonly property var addrBlock: addrBlockImpl

Column {
  visible: host.composePane
  anchors.fill: parent
  anchors.leftMargin: Style.space(16)
  spacing: Style.space(10)

  Item {
    width: parent.width
    height: Math.max(composeHeading.implicitHeight, composeActionRow.height)

    Text {
      id: composeHeading
      anchors.left: parent.left
      anchors.right: composeActionRow.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: host.composeTitle
      color: host.dim
      font.family: host.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
    }

    Row {
      id: composeActionRow
      visible: !host.composing && host.selected
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      PanelActionButton {
        iconText: host.mailboxId === "archive" ? "󰻪" : "󰀼"
        tooltipText: host.mailboxId === "archive" ? "Move to inbox · e" : "Archive · e"
        foreground: host.contentForeground
        fontFamily: host.contentFontFamily
        onClicked: host.archiveSelected()
      }
      PanelActionButton {
        iconText: host.mailboxId === "junk" ? "󰻪" : "󰯈"
        tooltipText: host.mailboxId === "junk" ? "Not junk · !" : "Junk · !"
        foreground: host.contentForeground
        fontFamily: host.contentFontFamily
        onClicked: host.junkSelected()
      }
      PanelActionButton {
        iconText: "󰩹"
        tooltipText: (host.mailboxId === "sent" || host.mailboxId === "trash" || host.mailboxId === "junk")
          ? "Delete forever · x"
          : "Trash · x"
        foreground: host.contentForeground
        hoverColor: host.urgent
        fontFamily: host.contentFontFamily
        onClicked: host.trashSelected()
      }
    }
  }

  Item {
    id: fromRow
    visible: host.liveMail && host.composeFromLabel !== ""
    width: parent.width
    height: fromLine.implicitHeight
    z: 3

    Row {
      id: fromLine
      width: parent.width
      spacing: Style.space(6)

      Text {
        id: fromPrefix
        text: "From"
        color: host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: fromLabel
        width: parent.width - fromPrefix.width - (fromChevron.visible ? fromChevron.width + parent.spacing : 0)
          - parent.spacing
        text: host.composeFromLabel
        color: (fromMouse.containsMouse || composeFromPopupImpl.opened)
          ? host.contentForeground
          : host.dim
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        id: fromChevron
        visible: host.composeFromCanPick
        text: "󰅀"
        color: fromLabel.color
        font.family: host.contentFontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: fromMouse
      anchors.fill: parent
      enabled: host.composeFromCanPick
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: composeFromPopupImpl.opened ? composeFromPopupImpl.close() : composeFromPopupImpl.open()
    }

    PanelToolTip {
      visible: fromMouse.containsMouse && host.composeFromCanPick && !composeFromPopupImpl.opened
      text: "Send as this account"
      fontFamily: host.contentFontFamily
    }

    Popup {
      id: composeFromPopupImpl
      parent: fromRow
      x: 0
      y: fromRow.height + Style.spacing.xxs
      width: fromRow.width
      padding: Style.spacing.hairline
      focus: true
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

      background: BorderSurface {
        color: Color.popups.background
        borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
        radius: Style.cornerRadius
      }

      onOpened: {
        fromList.currentIndex = Model.indexOfId(host.accounts, host.composeAccountId)
        fromList.forceActiveFocus()
      }

      contentItem: ListView {
        id: fromList
        implicitHeight: Math.min(contentHeight, Style.space(220))
        clip: true
        spacing: Style.spacing.labelGap
        boundsBehavior: Flickable.StopAtBounds
        model: host.accounts
        currentIndex: -1
        interactive: contentHeight > Style.space(220)
        height: Math.min(contentHeight, Style.space(220))

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            composeFromPopupImpl.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.text === "j") {
            fromList.currentIndex = Math.min(host.accounts.length - 1, fromList.currentIndex + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            fromList.currentIndex = Math.max(0, fromList.currentIndex - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            fromList.selectCurrent()
            event.accepted = true
          }
        }

        function selectCurrent() {
          var acc = fromList.currentIndex >= 0 && fromList.currentIndex < host.accounts.length
            ? host.accounts[fromList.currentIndex]
            : null
          if (!acc) return
          host.setComposeFrom(acc.id)
          composeFromPopupImpl.close()
        }

        delegate: Item {
          required property var modelData
          required property int index
          readonly property bool isFrom: String(modelData.id || "") === String(host.composeAccountId || "")
          width: fromList.width
          height: Style.spacing.popupRowHeight

          Rectangle {
            anchors.fill: parent
            color: isFrom
              ? Style.selectedFillFor(host.contentForeground, Color.accent)
              : (index === fromList.currentIndex
                ? Style.hoverFillFor(host.contentForeground, Color.accent)
                : "transparent")
          }

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            spacing: 0

            Text {
              width: parent.width
              text: modelData.name || modelData.email || "Account"
              color: isFrom
                ? Style.selectedStateColor(host.contentForeground, Color.accent)
                : host.contentForeground
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: isFrom
              elide: Text.ElideRight
            }

            Text {
              visible: String(modelData.email || "") !== ""
                && String(modelData.name || "").toLowerCase() !== String(modelData.email || "").toLowerCase()
              width: parent.width
              text: modelData.email
              color: host.dim
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: fromList.currentIndex = parent.index
            onClicked: fromList.selectCurrent()
          }
        }
      }
    }
  }

  Column {
    id: addrBlockImpl
    width: parent.width
    spacing: Style.space(10)
    z: 2

    Row {
      id: toRow
      width: parent.width
      spacing: Style.space(8)

      Item {
        width: parent.width - ccBccBtns.width - (ccBccBtns.visible ? parent.spacing : 0)
        height: composeToFieldImpl.implicitHeight

        TextField {
          id: composeToFieldImpl
          width: parent.width
          placeholderText: "To"
          text: host.composeTo
          foreground: host.contentForeground
          font.family: host.contentFontFamily
          onTextChanged: {
            host.composeTo = text
            host.composeSuggestHidden = false
            host.markComposeDirty()
          }
          onAccepted: {
            if (host.composeSuggestCanAccept()) host.acceptComposeSuggest()
            else host.focusComposeAddrNext("to")
          }
          Keys.onPressed: function(event) { host.handleComposeAddrKey(event) }
        }
      }

      Row {
        id: ccBccBtns
        visible: !host.composeShowCc || !host.composeShowBcc
        spacing: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          visible: !host.composeShowCc
          text: "Cc"
          color: ccBtnMouse.containsMouse ? host.contentForeground : host.dim
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.body
          MouseArea {
            id: ccBtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: host.openComposeCc()
          }
        }

        Text {
          visible: !host.composeShowBcc
          text: "Bcc"
          color: bccBtnMouse.containsMouse ? host.contentForeground : host.dim
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.body
          MouseArea {
            id: bccBtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: host.openComposeBcc()
          }
        }
      }
    }

    Item {
      id: ccWrap
      visible: host.composeShowCc
      width: parent.width
      height: visible ? composeCcFieldImpl.implicitHeight : 0

      TextField {
        id: composeCcFieldImpl
        width: parent.width
        placeholderText: "Cc"
        text: host.composeCc
        foreground: host.contentForeground
        font.family: host.contentFontFamily
        onTextChanged: {
          host.composeCc = text
          host.composeSuggestHidden = false
          host.markComposeDirty()
        }
        onAccepted: {
          if (host.composeSuggestCanAccept()) host.acceptComposeSuggest()
          else host.focusComposeAddrNext("cc")
        }
        Keys.onPressed: function(event) { host.handleComposeAddrKey(event) }
      }
    }

    Item {
      id: bccWrap
      visible: host.composeShowBcc
      width: parent.width
      height: visible ? composeBccFieldImpl.implicitHeight : 0

      TextField {
        id: composeBccFieldImpl
        width: parent.width
        placeholderText: "Bcc"
        text: host.composeBcc
        foreground: host.contentForeground
        font.family: host.contentFontFamily
        onTextChanged: {
          host.composeBcc = text
          host.composeSuggestHidden = false
          host.markComposeDirty()
        }
        onAccepted: {
          if (host.composeSuggestCanAccept()) host.acceptComposeSuggest()
          else host.focusComposeAddrNext("bcc")
        }
        Keys.onPressed: function(event) { host.handleComposeAddrKey(event) }
      }
    }

    Popup {
      id: composeSuggestPopupImpl
      parent: addrBlockImpl
      x: 0
      y: {
        var gap = Style.spacing.xxs
        if (composeCcFieldImpl.activeFocus)
          return toRow.height + addrBlockImpl.spacing + ccWrap.height + gap
        if (composeBccFieldImpl.activeFocus) {
          var top = toRow.height + addrBlockImpl.spacing
          if (ccWrap.visible) top += ccWrap.height + addrBlockImpl.spacing
          return top + bccWrap.height + gap
        }
        return toRow.height + gap
      }
      width: composeToFieldImpl.activeFocus ? composeToFieldImpl.width : addrBlockImpl.width
      padding: Style.spacing.hairline
      focus: false
      modal: false
      visible: host.composePane && !host.composeSuggestHidden && host.composeMatches.length > 0
        && (composeToFieldImpl.activeFocus || composeCcFieldImpl.activeFocus || composeBccFieldImpl.activeFocus)
      closePolicy: Popup.NoAutoClose

      background: BorderSurface {
        color: Color.popups.background
        borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
        radius: Style.cornerRadius
      }

      contentItem: ListView {
        id: composeSuggestList
        implicitHeight: contentHeight
        clip: true
        spacing: Style.spacing.labelGap
        boundsBehavior: Flickable.StopAtBounds
        model: host.composeMatches
        currentIndex: host.composeSuggestIndex
        interactive: contentHeight > Style.space(220)
        height: Math.min(contentHeight, Style.space(220))

        delegate: Item {
          required property var modelData
          required property int index
          width: composeSuggestList.width
          height: Style.spacing.popupRowHeight

          Rectangle {
            anchors.fill: parent
            color: index === host.composeSuggestIndex
              ? Style.hoverFillFor(host.contentForeground, Color.accent)
              : "transparent"
          }

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            spacing: 0

            Text {
              width: parent.width
              text: modelData.name || modelData.email
              color: host.contentForeground
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              visible: String(modelData.name || "") !== ""
                && String(modelData.name || "").toLowerCase() !== String(modelData.email || "").toLowerCase()
              width: parent.width
              text: modelData.email
              color: host.dim
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: host.composeSuggestIndex = index
            onPressed: function(mouse) {
              host.composeSuggestIndex = index
              host.acceptComposeSuggest()
              var field = host.composeAddrField(host.composeAddrRole)
              if (field) field.forceActiveFocus()
              mouse.accepted = true
            }
          }
        }
      }
    }
  }

  TextField {
    id: composeSubjectFieldImpl
    width: parent.width
    placeholderText: "Subject"
    text: host.composeSubject
    foreground: host.contentForeground
    font.family: host.contentFontFamily
    onTextChanged: {
      host.composeSubject = text
      host.markComposeDirty()
    }
    Keys.onPressed: function(event) { host.handleEditorKey(event, host.sendCompose) }
  }

  Flow {
    visible: host.outgoingFiles.length > 0
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: host.outgoingFiles

      Rectangle {
        required property var modelData
        implicitWidth: outAttachLabel.implicitWidth + Style.space(14)
        implicitHeight: Math.max(Style.space(22), outAttachLabel.implicitHeight + Style.space(8))
        radius: Style.cornerRadius
        color: outAttachMouse.containsMouse
          ? Style.hoverFillFor(host.contentForeground, Color.accent)
          : Style.normalFillFor(host.contentForeground, Color.accent)

        Text {
          id: outAttachLabel
          anchors.centerIn: parent
          text: "󰁦  " + modelData.name + "  ×"
          color: host.contentForeground
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: outAttachMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: host.removeOutgoingFile(modelData.path)
        }

        PanelToolTip {
          visible: outAttachMouse.containsMouse
          text: "Remove"
          fontFamily: host.contentFontFamily
        }
      }
    }
  }

  BodyField {
    id: composeBodyFieldImpl
    host: pane.host
    width: parent.width
    height: parent.height - y - sendRow.height - Style.space(10)
    placeholderText: "Write in plain text"
    text: host.composeBody
    onTextChanged: {
      host.composeBody = text
      host.markComposeDirty()
    }
    Keys.onPressed: function(event) { host.handleEditorKey(event, host.sendCompose) }
  }

  Row {
    id: sendRow
    spacing: Style.space(8)

    Button {
      text: host.mailSending ? "Sending…" : "Send"
      foreground: host.contentForeground
      enabled: !host.composeBusy()
      onClicked: host.sendCompose()
    }

    Button {
      text: host.mailSaving ? "Saving…" : "Save Draft"
      foreground: host.contentForeground
      enabled: !host.composeBusy()
      onClicked: host.saveDraft()
    }

    Button {
      text: host.filePickerBusy ? "Attach…" : "Attach"
      foreground: host.contentForeground
      enabled: !host.composeBusy() && !host.filePickerBusy
      onClicked: host.pickOutgoingFiles()
    }

    Button {
      visible: host.composing
      text: "Cancel"
      foreground: host.contentForeground
      enabled: !host.composeBusy()
      onClicked: host.cancelCompose()
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: host.mailSendError !== "" ? host.mailSendError : "Ctrl+Enter send · Ctrl+S draft"
      color: host.mailSendError !== "" ? host.urgent : host.dim
      font.family: host.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
}
