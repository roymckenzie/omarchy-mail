import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Text {
  property var host
  color: host ? host.dim : Color.foreground
  font.family: host ? host.contentFontFamily : Style.font.family
  font.pixelSize: Style.font.bodySmall
  font.letterSpacing: 1
}
