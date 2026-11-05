import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// The bottom line: how many processes, how busy the machine is, and the one
// sentence that explains the last thing that happened.
Rectangle {
    id: root

    property var strings
    property int count: 0
    property int running: 0
    property int cores: 0
    property real load: 0
    property double age: 0
    property string notice: ""
    property bool urgent: false
    property bool down: false

    signal helpRequested()

    implicitHeight: Math.max(24, Commons.Style.font.caption * 2.2)
    color: "transparent"

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: Commons.Util.alpha(Commons.Color.foreground, 0.1)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Commons.Style.spacing.rowPaddingX
        anchors.rightMargin: Commons.Style.spacing.rowPaddingX
        spacing: Commons.Style.spacing.lg

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.strings.tn("%1 processes", root.count).replace("%1", Commons.I18n.formatNumber(root.count, 0))
            color: Commons.Util.alpha(Commons.Color.foreground, 0.6)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.strings.tn("%1 running", root.running).replace("%1", Commons.I18n.formatNumber(root.running, 0))
            color: root.running > 0 ? Commons.Color.accent : Commons.Util.alpha(Commons.Color.foreground, 0.45)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: root.cores > 0
            text: root.strings.t("%1 cores").replace("%1", Commons.I18n.formatNumber(root.cores, 0))
            color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: root.cores > 0
            text: root.strings.t("Load %1").replace("%1", Commons.I18n.formatNumber(root.load, 2))
            color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
        }

        Item { Layout.fillWidth: true }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: root.width * 0.5
            text: root.notice.length > 0
                ? root.notice
                : root.down
                    ? root.strings.t("Sampler stopped")
                    : root.strings.t("%1 s ago").replace("%1", Commons.I18n.formatNumber(root.age, 0))
            color: root.urgent || root.down ? Commons.Color.urgent : Commons.Util.alpha(Commons.Color.foreground, 0.45)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            elide: Text.ElideLeft
            horizontalAlignment: Text.AlignRight
        }

        // The key map belongs where a first-time reader looks for help.
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.strings.t("? keys")
            color: helpHover.hovered ? Commons.Color.accent : Commons.Util.alpha(Commons.Color.foreground, 0.35)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption

            HoverHandler { id: helpHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.helpRequested()
            }
        }
    }
}
