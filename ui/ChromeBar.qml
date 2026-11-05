import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// The one bar at the top: name, search, and the two choices that decide what
// the list shows. Every control is a keyboard target; the mouse just mirrors it.
Rectangle {
    id: root

    property var strings
    property string searchText: ""
    property string sortKey: "cpu"
    property bool treeView: false

    signal searchEdited(string text)
    signal searchAccepted()
    signal searchDismissed()
    signal sortRequested(string key)
    signal viewRequested(bool tree)

    function focusSearch() { searchInput.forceActiveFocus() }
    function clearSearch() { searchInput.text = "" }

    implicitHeight: Commons.Style.spacing.controlHeight + Commons.Style.spacing.md * 2
    color: "transparent"

    component Chip: Item {
        id: chip
        property string label: ""
        property bool active: false
        signal clicked()

        implicitWidth: chipLabel.implicitWidth + Commons.Style.spacing.controlPaddingX * 2
        implicitHeight: Commons.Style.spacing.controlHeight

        Rectangle {
            anchors.fill: parent
            color: chipHover.hovered ? Commons.Util.alpha(Commons.Color.foreground, 0.06) : "transparent"
            radius: Math.min(4, Commons.Style.cornerRadius)
        }
        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            color: chip.active ? Commons.Color.accent : Commons.Color.muted
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            font.letterSpacing: 0.5
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(1, Math.round(Commons.Style.space(2)))
            color: chip.active ? Commons.Color.accent : "transparent"
        }
        HoverHandler { id: chipHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Commons.Style.spacing.rowPaddingX
        anchors.rightMargin: Commons.Style.spacing.rowPaddingX
        spacing: Commons.Style.spacing.lg

        Text {
            text: "omascope"
            color: Commons.Color.accent
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.title
            font.weight: Font.DemiBold
        }

        // The search line. Typing filters; Enter keeps the results and hands
        // the keyboard back to the list; Escape clears and returns as well.
        Rectangle {
            Layout.preferredWidth: Math.max(220, Math.min(360, Math.round(Commons.Style.space(300))))
            Layout.preferredHeight: Commons.Style.spacing.controlHeight
            color: Commons.Util.alpha(Commons.Color.foreground, 0.05)
            radius: Math.min(4, Commons.Style.cornerRadius)
            border.width: searchInput.activeFocus ? 1 : 0
            border.color: Commons.Util.alpha(Commons.Color.accent, 0.7)

            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin: Commons.Style.spacing.controlPaddingX
                anchors.rightMargin: Commons.Style.spacing.controlPaddingX
                verticalAlignment: TextInput.AlignVCenter
                color: Commons.Color.foreground
                selectionColor: Commons.Util.alpha(Commons.Color.accent, 0.35)
                selectedTextColor: Commons.Color.foreground
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.body
                clip: true
                selectByMouse: true
                text: root.searchText
                onTextEdited: root.searchEdited(text)
                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Escape) {
                        searchInput.text = ""
                        root.searchDismissed()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.searchAccepted()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        root.searchAccepted()
                        event.accepted = true
                    }
                }
            }

            Text {
                anchors.fill: parent
                anchors.leftMargin: Commons.Style.spacing.controlPaddingX
                anchors.rightMargin: Commons.Style.spacing.controlPaddingX
                verticalAlignment: Text.AlignVCenter
                visible: searchInput.text.length === 0
                text: root.strings ? root.strings.t("Search name, user, or PID") : ""
                color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.body
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillWidth: true }

        Row {
            spacing: Commons.Style.spacing.xs

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.strings ? root.strings.t("View") : ""
                color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
            }
            Chip {
                label: root.strings ? root.strings.t("List") : ""
                active: !root.treeView
                onClicked: root.viewRequested(false)
            }
            Chip {
                label: root.strings ? root.strings.t("Tree") : ""
                active: root.treeView
                onClicked: root.viewRequested(true)
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: Commons.Style.spacing.controlHeight * 0.6
            color: Commons.Util.alpha(Commons.Color.foreground, 0.15)
        }

        Row {
            spacing: Commons.Style.spacing.xs

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.strings ? root.strings.t("Sort") : ""
                color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
            }
            Chip { label: "CPU"; active: root.sortKey === "cpu"; onClicked: root.sortRequested("cpu") }
            Chip { label: root.strings ? root.strings.t("Memory") : ""; active: root.sortKey === "mem"; onClicked: root.sortRequested("mem") }
            Chip { label: root.strings ? root.strings.t("Name") : ""; active: root.sortKey === "name"; onClicked: root.sortRequested("name") }
            Chip { label: "PID"; active: root.sortKey === "pid"; onClicked: root.sortRequested("pid") }
        }
    }
}
