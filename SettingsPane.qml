import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: pane
  property var host
  visible: host && host.settingsOpen
  readonly property bool accountsTab: host && host.settingsTab === "accounts"
  readonly property bool generalTab: host && host.settingsTab === "general"
  readonly property bool aboutTab: host && host.settingsTab === "about"
  readonly property var accNameField: accNameFieldImpl
  readonly property var accFromNameField: accFromNameFieldImpl
  readonly property var accEmailField: accEmailFieldImpl
  readonly property var imapHostField: imapHostFieldImpl
  readonly property var imapPortField: imapPortFieldImpl
  readonly property var smtpHostField: smtpHostFieldImpl
  readonly property var smtpPortField: smtpPortFieldImpl
  readonly property var accUserField: accUserFieldImpl
  readonly property var accPassField: accPassFieldImpl
  readonly property var defaultFromDropdown: defaultFromDropdownImpl

Column {
  visible: host.settingsOpen
  anchors.fill: parent
  spacing: Style.space(10)

  Item {
    width: parent.width
    height: Math.max(settingsTitle.implicitHeight, doneBtn.height)

    Text {
      id: settingsTitle
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "SETTINGS"
      color: host.dim
      font.family: host.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
    }

    Button {
      id: doneBtn
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Done"
      foreground: host.contentForeground
      onClicked: host.closeSettings()
    }
  }

  Row {
    width: parent.width
    height: host.filterChipHeight
    spacing: Style.spacing.md

    FilterChip {
      host: pane.host
      value: "accounts"
      chipLabel: "Accounts"
      hint: ""
      selected: pane.accountsTab
      onPicked: host.setSettingsTab(value)
    }

    FilterChip {
      host: pane.host
      value: "general"
      chipLabel: "General"
      hint: ""
      selected: pane.generalTab
      onPicked: host.setSettingsTab(value)
    }

    FilterChip {
      host: pane.host
      value: "about"
      chipLabel: "About"
      hint: ""
      selected: pane.aboutTab
      onPicked: host.setSettingsTab(value)
    }
  }

  Item {
    width: parent.width
    height: parent.height - y

    Row {
      id: settingsPanes
      visible: pane.accountsTab
      anchors.fill: parent
      spacing: 0

  Item {
    id: settingsListPane
    width: Math.round(Math.min(Style.space(280), settingsPanes.width * 0.34))
    height: parent.height

    Column {
      anchors.fill: parent
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(10)

      BorderSurface {
        width: parent.width
        height: parent.height - y - addAccountBtn.height - Style.space(10)
        color: Style.normalFillFor(host.contentForeground, Color.accent)
        borderSpec: Border.controlSpec("normal", host.contentForeground, Color.accent)
        radius: Style.cornerRadius

        Flickable {
          id: accountFlick
          anchors.fill: parent
          anchors.margins: Style.space(6)
          contentWidth: width
          contentHeight: accountColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: accountColumn
            width: accountFlick.width
            spacing: Style.space(4)

            Repeater {
              model: host.settingsAccounts

              AccountWellRow {
                host: pane.host
                required property var modelData
                required property int index
                width: accountColumn.width
                account: modelData
                rowIndex: index
              }
            }
          }
        }

        Text {
          visible: host.settingsAccounts.length === 0
          anchors.centerIn: parent
          text: "No accounts yet."
          color: host.dim
          font.family: host.contentFontFamily
          font.pixelSize: Style.font.body
        }
      }

      Button {
        id: addAccountBtn
        width: parent.width
        text: "Add account"
        foreground: host.contentForeground
        onClicked: host.addAccount()
      }
    }
  }

  Rectangle {
    width: Style.space(1)
    height: parent.height
    color: Util.alpha(host.contentForeground, 0.12)
  }

  Item {
    width: settingsPanes.width - settingsListPane.width - Style.space(1)
    height: parent.height

    Flickable {
      id: settingsFormFlick
      visible: host.settingsSelected
      anchors.fill: parent
      anchors.leftMargin: Style.space(16)
      contentWidth: width
      contentHeight: settingsForm.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: settingsForm
        width: settingsFormFlick.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: host.editing.name || "New account"
            color: host.contentForeground
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
            width: parent.width - unsavedLabel.implicitWidth - Style.space(8)
          }

          Text {
            id: unsavedLabel
            visible: host.editingDirty
            anchors.verticalCenter: parent.verticalCenter
            text: "Unsaved"
            color: host.dim
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        FieldLabel {
          host: pane.host
          text: "Account name"
        }
        TextField {
          id: accNameFieldImpl
          width: parent.width
          placeholderText: "Work"
          foreground: host.contentForeground
          font.family: host.contentFontFamily
          onTextChanged: host.patchEditing("name", text)
          Keys.onPressed: host.handleSettingsKey(event)
        }

        FieldLabel {
          host: pane.host
          text: "From name"
        }
        TextField {
          id: accFromNameFieldImpl
          width: parent.width
          placeholderText: "Your name"
          foreground: host.contentForeground
          font.family: host.contentFontFamily
          onTextChanged: host.patchEditing("fromName", text)
          Keys.onPressed: host.handleSettingsKey(event)
        }

        FieldLabel {
          host: pane.host
          text: "Email"
        }
        TextField {
          id: accEmailFieldImpl
          width: parent.width
          placeholderText: "you@example.com"
          foreground: host.contentForeground
          font.family: host.contentFontFamily
          onTextChanged: host.patchEditing("email", text)
          Keys.onPressed: host.handleSettingsKey(event)
        }

        PanelSeparator {
          width: parent.width
          foreground: host.contentForeground
        }

        FieldLabel {
          host: pane.host
          text: "IMAP"
        }
        TextField {
          id: imapHostFieldImpl
          width: parent.width
          placeholderText: "imap.example.com"
          foreground: host.contentForeground
          font.family: host.contentFontFamily
          onTextChanged: host.patchEditing("imapHost", text)
          Keys.onPressed: host.handleSettingsKey(event)
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: imapPortFieldImpl
            width: Style.space(88)
            placeholderText: "993"
            foreground: host.contentForeground
            font.family: host.contentFontFamily
            onTextChanged: host.patchEditing("imapPort", text)
            Keys.onPressed: host.handleSettingsKey(event)
          }

          FilterChip {
            host: pane.host
            value: "imap-tls"
            chipLabel: "TLS"
            hint: "Use TLS for IMAP"
            selected: host.editing.imapTls !== false
            onPicked: host.patchEditing("imapTls", !selected)
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: host.contentForeground
        }

        FieldLabel {
          host: pane.host
          text: "SMTP"
        }
        TextField {
          id: smtpHostFieldImpl
          width: parent.width
          placeholderText: "smtp.example.com"
          foreground: host.contentForeground
          font.family: host.contentFontFamily
          onTextChanged: host.patchEditing("smtpHost", text)
          Keys.onPressed: host.handleSettingsKey(event)
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: smtpPortFieldImpl
            width: Style.space(88)
            placeholderText: "465"
            foreground: host.contentForeground
            font.family: host.contentFontFamily
            onTextChanged: host.patchEditing("smtpPort", text)
            Keys.onPressed: host.handleSettingsKey(event)
          }

          FilterChip {
            host: pane.host
            value: "smtp-tls"
            chipLabel: "TLS"
            hint: "Use TLS for SMTP"
            selected: host.editing.smtpTls !== false
            onPicked: host.patchEditing("smtpTls", !selected)
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: host.contentForeground
        }

        FieldLabel {
          host: pane.host
          text: "Username"
        }
        TextField {
          id: accUserFieldImpl
          width: parent.width
          placeholderText: "Same as email, usually"
          foreground: host.contentForeground
          font.family: host.contentFontFamily
          onTextChanged: host.patchEditing("username", text)
          Keys.onPressed: host.handleSettingsKey(event)
        }

        FieldLabel {
          host: pane.host
          text: "Password"
        }
        TextField {
          id: accPassFieldImpl
          width: parent.width
          password: true
          placeholderText: "App password"
          foreground: host.contentForeground
          font.family: host.contentFontFamily
          onTextChanged: host.patchEditing("password", text)
          Keys.onPressed: host.handleSettingsKey(event)
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Save"
            enabled: host.editingCanSave
            foreground: host.contentForeground
            onClicked: host.saveAccount()
          }

          Button {
            text: "Remove"
            foreground: host.contentForeground
            onClicked: host.removeSettingsAccount()
          }

          Text {
            visible: host.editingDirty && !Model.accountCanSave(host.editing)
            anchors.verticalCenter: parent.verticalCenter
            text: "Name, email, IMAP, and SMTP are required."
            color: host.dim
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Text {
      visible: !host.settingsSelected
      anchors.centerIn: parent
      text: "Select an account"
      color: host.dim
      font.family: host.contentFontFamily
      font.pixelSize: Style.font.body
    }
  }
    }

    Item {
      visible: pane.generalTab
      anchors.fill: parent

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.space(8)
        spacing: Style.space(20)

        Item {
          width: parent.width
          height: Math.max(handlerCopy.implicitHeight, defaultMailBtn.height)

          Column {
            id: handlerCopy
            anchors.left: parent.left
            anchors.right: defaultMailBtn.left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: String(host.mailtoHandlerName || "") !== ""
                ? "Default mail handler: " + host.mailtoHandlerName
                : "Default mail handler"
              color: host.contentForeground
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: "Open compose in this panel when you click a mailto: link."
              color: host.dim
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Button {
            id: defaultMailBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: host.mailIsMailtoHandler ? "Mail is the default" : "Set Mail as default"
            bordered: true
            enabled: !host.mailIsMailtoHandler
            foreground: host.contentForeground
            fontFamily: host.contentFontFamily
            onClicked: host.setDefaultMailHandler()
          }
        }

        Item {
          width: parent.width
          height: Math.max(notifyCopy.implicitHeight, notifySwitch.height)

          Column {
            id: notifyCopy
            anchors.left: parent.left
            anchors.right: notifySwitch.left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: "Notifications"
              color: host.contentForeground
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Notify when new mail arrives."
              color: host.dim
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          ToggleSwitch {
            id: notifySwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: host.notifications
            interactive: false
            cursorRing: false
            foreground: host.contentForeground
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: host.setNotifications(!host.notifications)
          }
        }

        Item {
          visible: host.accounts.length > 1
          width: parent.width
          height: visible ? Math.max(fromCopy.implicitHeight, defaultFromDropdownImpl.height) : 0

          Column {
            id: fromCopy
            anchors.left: parent.left
            anchors.right: defaultFromDropdownImpl.left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: "Default send-from account"
              color: host.contentForeground
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Used for new messages when All accounts are showing."
              color: host.dim
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Dropdown {
            id: defaultFromDropdownImpl
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(220)
            showLabel: false
            foreground: host.contentForeground
            fontFamily: host.contentFontFamily
            value: host.settingsDefaultAccountId
            options: host.defaultAccountOptions
            onChanged: host.setDefaultAccount(value)
          }
        }
      }
    }

    Item {
      visible: pane.aboutTab
      anchors.fill: parent

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.space(8)
        spacing: Style.space(20)

        Item {
          width: parent.width
          height: aboutNameLabel.implicitHeight

          Text {
            id: aboutNameLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Name"
            color: host.contentForeground
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: host.pluginName
            color: host.dim
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.body
          }
        }

        Item {
          width: parent.width
          height: aboutVersionLabel.implicitHeight

          Text {
            id: aboutVersionLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Version"
            color: host.contentForeground
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: host.pluginVersion || "—"
            color: host.dim
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.body
          }
        }

        Item {
          width: parent.width
          height: Math.max(supportCopy.implicitHeight, supportBtn.height)

          Column {
            id: supportCopy
            anchors.left: parent.left
            anchors.right: supportBtn.left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: "Support"
              color: host.contentForeground
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Report bugs and ask questions on GitHub."
              color: host.dim
              font.family: host.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Button {
            id: supportBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Open issues"
            bordered: true
            foreground: host.contentForeground
            fontFamily: host.contentFontFamily
            onClicked: host.openSupport()
          }
        }
      }
    }
  }
}
}
