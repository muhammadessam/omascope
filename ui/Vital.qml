import QtQuick
import qs.Commons
import qs.Commons as Commons

// One reading in the vitals strip: a label, the number that matters, the
// context under it, and the last couple of minutes as a line.
Rectangle {
    id: root

    property string label: ""
    property string value: ""
    property string detail: ""
    property var values: []
    property real maximum: 100
    property color lineColor: Commons.Color.accent

    implicitHeight: Commons.Style.space(68)
    color: Commons.Util.alpha(Commons.Color.foreground, 0.03)
    radius: Math.min(6, Commons.Style.cornerRadius)
    border.width: 1
    border.color: Commons.Util.alpha(Commons.Color.foreground, 0.07)
    clip: true

    Column {
        anchors.fill: parent
        anchors.margins: Commons.Style.spacing.lg
        spacing: Commons.Style.spacing.xxs

        Item {
            width: parent.width
            height: Math.max(labelText.implicitHeight, valueText.implicitHeight)

            Text {
                id: labelText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                color: Commons.Util.alpha(Commons.Color.foreground, 0.5)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
                font.letterSpacing: 0.6
            }
            Text {
                id: valueText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.value
                color: Commons.Color.foreground
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.title
                font.weight: Font.DemiBold
            }
        }

        Text {
            width: parent.width
            text: root.detail
            color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            elide: Text.ElideRight
        }

        Sparkline {
            width: parent.width
            height: Commons.Style.space(18)
            values: root.values
            maximum: root.maximum
            lineColor: root.lineColor
        }
    }
}
