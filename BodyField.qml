import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  property var host
    property alias text: area.text
    property alias placeholderText: area.placeholderText
    readonly property bool editorFocused: area.activeFocus

    function forceActiveFocus() { area.forceActiveFocus() }

    BorderSurface {
      anchors.fill: parent
      color: Style.controlFill(area.activeFocus, area.hovered, host.contentForeground, Color.accent)
      borderSpec: Border.controlSpec(area.activeFocus ? "focus" : (area.hovered ? "hover-cursor" : "normal"), host.contentForeground, Color.accent)
      radius: Style.cornerRadius
    }

    TextArea {
      id: area
      anchors.fill: parent
      anchors.margins: Style.space(8)
      wrapMode: TextEdit.Wrap
      color: host.contentForeground
      placeholderTextColor: host.dim
      font.family: host.contentFontFamily
      font.pixelSize: Style.font.body
      background: null
    }
  }
