import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: pane
  property var host
  visible: host && host.settingsOpen
  readonly property var accNameField: accNameFieldImpl
  readonly property var accFromNameField: accFromNameFieldImpl
  readonly property var accEmailField: accEmailFieldImpl
  readonly property var imapHostField: imapHostFieldImpl
  readonly property var imapPortField: imapPortFieldImpl
  readonly property var smtpHostField: smtpHostFieldImpl
  readonly property var smtpPortField: smtpPortFieldImpl
  readonly property var accUserField: accUserFieldImpl
  readonly property var accPassField: accPassFieldImpl

Row {
  id: settingsPanes
  visible: host.settingsOpen
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

      Item {
        width: parent.width
        height: Math.max(settingsTitle.implicitHeight, doneBtn.height)

        Column {
          id: settingsTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "SETTINGS"
            color: host.dim
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          Text {
            text: "Accounts"
            color: host.contentForeground
            font.family: host.contentFontFamily
            font.pixelSize: Style.font.title
          }
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
}
