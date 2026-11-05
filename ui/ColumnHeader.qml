import QtQuick
import qs.Commons
import qs.Commons as Commons

// Column labels, and the mouse shortcut for the sort keys. The widths come
// from the same Columns object the rows use, so the header cannot drift.
Item {
    id: root

    property var columns
    property var strings
    property string sortKey: "cpu"
    property bool sortAscending: false

    signal sortRequested(string key)

    implicitHeight: Math.max(20, Math.round(Commons.Style.font.caption * 2.1))
    height: implicitHeight

    Row {
        anchors.fill: parent
        anchors.leftMargin: Commons.Style.spacing.rowPaddingX
        anchors.rightMargin: Commons.Style.spacing.rowPaddingX

        component Header: Text {
            id: headerLabel
            property string columnKey: ""
            property bool numeric: false
            property var strings
            property string sortKey: ""
            property bool sortAscending: false
            property int columnWidth: 0

            width: columnWidth
            height: root.height
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: numeric ? Text.AlignRight : Text.AlignLeft
            text: headerLabel.caption + (root.sortKey === headerLabel.columnKey && headerLabel.columnKey !== "" ? (root.sortAscending ? "  ↑" : "  ↓") : "")
            property string caption: ""
            color: sortKey === columnKey ? Commons.Color.accent : Commons.Util.alpha(Commons.Color.foreground, 0.5)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            font.letterSpacing: 0.6
            elide: Text.ElideRight
            rightPadding: numeric ? Commons.Style.spacing.sm : 0
            leftPadding: numeric ? 0 : Commons.Style.spacing.sm

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.sortRequested(headerLabel.columnKey)
            }
        }

        Header {
            columnKey: "pid"; columnWidth: columns.pid; caption: "PID"
            strings: root.strings; sortKey: root.sortKey; sortAscending: root.sortAscending
        }
        Header {
            columnKey: "name"; columnWidth: columns.name; caption: root.strings ? root.strings.t("Name") : ""
            strings: root.strings; sortKey: root.sortKey; sortAscending: root.sortAscending
        }
        Header {
            columnKey: "cpu"; columnWidth: columns.cpu; caption: "CPU"; numeric: true
            strings: root.strings; sortKey: root.sortKey; sortAscending: root.sortAscending
        }
        Header {
            columnKey: "mem"; columnWidth: columns.mem; caption: root.strings ? root.strings.t("Memory") : ""; numeric: true
            strings: root.strings; sortKey: root.sortKey; sortAscending: root.sortAscending
        }
        Header {
            columnWidth: columns.user; caption: root.strings ? root.strings.t("User") : ""
            strings: root.strings; sortKey: root.sortKey; sortAscending: root.sortAscending
        }
        Header {
            columnWidth: columns.command; caption: root.strings ? root.strings.t("Command") : ""
            strings: root.strings; sortKey: root.sortKey; sortAscending: root.sortAscending
        }
    }
}
