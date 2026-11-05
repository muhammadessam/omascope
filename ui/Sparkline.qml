import QtQuick
import qs.Commons
import qs.Commons as Commons

// A small line chart with a soft fill, used for the vitals strip and the
// selected process's CPU. Values are plain percentages; the canvas redraws
// when the array is replaced, which happens once per snapshot.
Canvas {
    id: canvas

    property var values: []
    property real maximum: 100
    property color lineColor: Commons.Color.accent

    implicitHeight: Commons.Style.space(20)

    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onMaximumChanged: requestPaint()

    onPaint: {
        var context = getContext("2d")
        context.clearRect(0, 0, width, height)
        if (!values || values.length < 2) return

        var peak = Math.max(maximum, 1)
        var step = width / Math.max(1, values.length - 1)
        var top = 1
        var bottom = height - 1

        context.beginPath()
        for (var i = 0; i < values.length; i++) {
            var x = i * step
            var y = bottom - Math.max(0, Math.min(peak, values[i])) / peak * (bottom - top)
            if (i === 0) context.moveTo(x, y)
            else context.lineTo(x, y)
        }
        context.strokeStyle = lineColor
        context.lineWidth = 1.5
        context.lineJoin = "round"
        context.stroke()

        // Close the same path down to the baseline and tint it, so a quiet
        // graph still reads as a filled band rather than a stray line.
        context.lineTo(width, height)
        context.lineTo(0, height)
        context.closePath()
        context.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.12)
        context.fill()
    }
}
