import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

BorderSurface {
  property var host
    property string value
    property string chipLabel
    property string hint
    property bool selected: false
    readonly property bool hovered: chipMouse.containsMouse
    readonly property int borderPad: Math.max(Style.hoverBorderWidth, Style.normalBorderWidth)

    signal picked(string value)

    readonly property int horizontalPad: Style.spacing.controlPaddingX * 2 + borderPad * 2
    implicitWidth: Math.min(Style.space(128), chipMeasure.implicitWidth + horizontalPad)
    implicitHeight: host.filterChipHeight
    radius: Style.cornerRadius
    color: hovered
      ? Style.hoverFillFor(host.contentForeground, Color.accent)
      : (selected ? Style.selectedFillFor(host.contentForeground, Color.accent) : "transparent")
    borderSpec: Border.controlSpec(hovered ? "hover-cursor" : "normal", host.contentForeground, Color.accent)

    Text {
      id: chipMeasure
      visible: false
      text: chipLabel
      font.family: host.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: selected
    }

    Text {
      id: chipText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.controlPaddingX + borderPad
      anchors.rightMargin: Style.spacing.controlPaddingX + borderPad
      anchors.verticalCenter: parent.verticalCenter
      text: chipLabel
      color: selected ? Style.selectedStateColor(host.contentForeground, Color.accent) : host.contentForeground
      font.family: host.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: selected
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: picked(value)
    }

    PanelToolTip {
      visible: chipMouse.containsMouse && (chipText.truncated || (hint !== "" && hint !== chipLabel))
      text: chipText.truncated ? chipLabel : hint
      fontFamily: host.contentFontFamily
    }
  }
