import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Flickable {
    id: flick
    property real scrollScale: 3
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    maximumFlickVelocity: 4000 * scrollScale
    flickDeceleration: 900
    pixelAligned: true

    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) {
        var dy = event.pixelDelta.y !== 0
          ? event.pixelDelta.y * flick.scrollScale
          : event.angleDelta.y * 0.27 * flick.scrollScale
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy))
        event.accepted = true
      }
    }
  }
