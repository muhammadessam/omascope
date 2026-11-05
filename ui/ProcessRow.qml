import QtQuick
import qs.Commons
import qs.Commons as Commons

// One row of the process table, in either view. The tree indent and the fold
// arrow live inside the name column so every other column stays aligned.
Item {
    id: root

    property var row
    property var columns
    property var strings
    property bool selected: false

    signal picked()
    signal activated()
    signal foldRequested(int pid)

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: Math.max(24, Math.round(Commons.Style.font.body * 2.35))

    readonly property real indent: root.row ? Math.min(root.row.depth * Commons.Style.space(12), columns.name * 0.45) : 0
    readonly property bool hasChildren: root.row ? root.row.kidCount > 0 : false
    readonly property bool folded: root.row ? root.row.folded === 1 : false

    Rectangle {
        anchors.fill: parent
        color: root.selected
            ? Commons.Util.alpha(Commons.Color.accent, 0.16)
            : rowHover.hovered ? Commons.Util.alpha(Commons.Color.foreground, 0.05) : "transparent"
    }

    Rectangle {
        visible: root.selected
        width: Math.max(2, Math.round(Commons.Style.space(2)))
        height: parent.height
        color: Commons.Color.accent
    }

    HoverHandler { id: rowHover }

    // The click target sits behind the content so the fold arrow keeps its own.
    MouseArea {
        anchors.fill: parent
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
        onDoubleClicked: root.activated()
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: Commons.Style.spacing.rowPaddingX
        anchors.rightMargin: Commons.Style.spacing.rowPaddingX

        Text {
            width: root.columns.pid
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            leftPadding: Commons.Style.spacing.sm
            text: root.row ? String(root.row.pid) : ""
            color: Commons.Util.alpha(Commons.Color.foreground, root.selected ? 0.85 : 0.55)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            elide: Text.ElideRight
        }

        Item {
            width: root.columns.name
            height: parent.height

            Item {
                x: root.indent
                width: Commons.Style.space(14)
                height: parent.height
                visible: root.hasChildren

                Text {
                    anchors.centerIn: parent
                    text: Commons.I18n.rightToLeft
                        ? (root.folded ? "◂" : "▾")
                        : (root.folded ? "▸" : "▾")
                    color: Commons.Util.alpha(Commons.Color.foreground, 0.5)
                    font.family: Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.bodySmall
                    rotation: root.folded ? 0 : 0
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.foldRequested(root.row.pid)
                }
            }

            // Running, sleeping, stopped, zombie: the dot says it before the
            // name is read.
            Rectangle {
                x: root.indent + Commons.Style.space(14) + Commons.Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(4, Math.round(Commons.Style.space(6)))
                height: width
                radius: width / 2
                color: {
                    var state = root.row ? root.row.procState : ""
                    if (state === "R") return Commons.Color.accent
                    if (state === "Z") return Commons.Color.urgent
                    if (state === "T" || state === "t") return Commons.Util.alpha(Commons.Color.foreground, 0.35)
                    return Commons.Util.alpha(Commons.Color.muted, 0.7)
                }
            }

            Text {
                x: root.indent + Commons.Style.space(14) + Commons.Style.spacing.xs + Commons.Style.space(6) + Commons.Style.spacing.sm
                width: parent.width - x
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: root.row ? root.row.name : ""
                color: root.selected ? Commons.Color.foreground : Commons.Color.foreground
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.body
                font.weight: root.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
        }

        Text {
            width: root.columns.cpu
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            rightPadding: Commons.Style.spacing.sm
            text: root.row ? Commons.I18n.formatNumber(root.row.cpu, 1) : ""
            color: root.row && root.row.cpu >= 25 ? Commons.Color.accent : Commons.Util.alpha(Commons.Color.foreground, 0.8)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            elide: Text.ElideRight
        }

        Text {
            width: root.columns.mem
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            rightPadding: Commons.Style.spacing.sm
            text: root.row ? Commons.I18n.formatNumber(root.row.rss / 1048576, root.row.rss >= 10485760 ? 0 : 1) + "M" : ""
            color: Commons.Util.alpha(Commons.Color.foreground, 0.75)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            elide: Text.ElideRight
        }

        Text {
            width: root.columns.user
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            leftPadding: Commons.Style.spacing.sm
            text: root.row ? root.row.user : ""
            color: Commons.Util.alpha(Commons.Color.foreground, 0.6)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            elide: Text.ElideRight
        }

        Text {
            width: root.columns.command
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            leftPadding: Commons.Style.spacing.sm
            text: root.row ? root.row.cmd : ""
            color: Commons.Util.alpha(Commons.Color.foreground, 0.42)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            elide: Text.ElideRight
        }
    }
}
