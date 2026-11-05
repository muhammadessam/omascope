import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

// Ending a process asks first, and the two signals say what will happen:
// TERM lets it save and exit, KILL cannot be caught. The card owns its own
// keys so the list under it cannot move while the question is open.
Item {
    id: root

    property var strings
    property var target: null
    property string preferred: "TERM"
    property bool open: false
    property int choice: 0

    signal canceled()
    signal confirmed(string signal)

    visible: open
    z: 20

    function signalFor(index) { return index === 1 ? "KILL" : "TERM" }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            root.canceled()
            return true
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_K
                || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.choice = root.choice === 0 ? 1 : 0
            return true
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.confirmed(root.signalFor(root.choice))
            return true
        }
        return false
    }

    // The rail's two buttons open the same card, already on the signal the
    // user asked for, so a force kill is one Enter away rather than a toggle.
    onOpenChanged: if (open) choice = preferred === "KILL" ? 1 : 0

    component Option: Rectangle {
        id: option
        property string label: ""
        property string detail: ""
        property bool chosen: false
        property bool dangerous: false
        signal picked()

        width: parent ? parent.width : 0
        height: optionBody.implicitHeight + Commons.Style.spacing.md * 2
        radius: Math.min(4, Commons.Style.cornerRadius)
        color: option.chosen
            ? Commons.Util.alpha(option.dangerous ? Commons.Color.urgent : Commons.Color.accent, 0.16)
            : Commons.Util.alpha(Commons.Color.foreground, 0.03)
        border.width: option.chosen ? 1 : 0
        border.color: option.dangerous ? Commons.Color.urgent : Commons.Color.accent

        Column {
            id: optionBody
            anchors.fill: parent
            anchors.margins: Commons.Style.spacing.md
            spacing: Commons.Style.spacing.xxs

            Text {
                text: option.label
                color: option.dangerous ? Commons.Color.urgent : Commons.Color.foreground
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.body
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: option.detail
                color: Commons.Util.alpha(Commons.Color.foreground, 0.5)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
                wrapMode: Text.WordWrap
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: option.picked()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Commons.Util.alpha(Commons.Color.background, 0.82)

        MouseArea {
            anchors.fill: parent
            onClicked: root.canceled()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(460, root.width - Commons.Style.spacing.xxl * 2)
        height: layout.implicitHeight + Commons.Style.spacing.panelPadding * 2
        color: Commons.Color.background
        radius: Commons.Style.cornerRadius
        border.width: Math.max(1, Math.round(Commons.Style.space(2)))
        border.color: Commons.Util.alpha(Commons.Color.accent, 0.85)

        MouseArea { anchors.fill: parent }

        Column {
            id: layout
            x: Commons.Style.spacing.panelPadding
            y: Commons.Style.spacing.panelPadding
            width: card.width - Commons.Style.spacing.panelPadding * 2
            spacing: Commons.Style.spacing.md

            Text {
                width: parent.width
                text: root.strings.t("End process?")
                color: Commons.Color.foreground
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.heading
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                text: root.target
                    ? root.target.name + "  ·  PID " + Commons.I18n.formatNumber(root.target.pid, 0)
                    : ""
                color: Commons.Util.alpha(Commons.Color.foreground, 0.65)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.body
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.target !== null && root.target.user !== Quickshell.env("USER")
                text: root.target
                    ? root.strings.t("Owned by %1. You may not have permission to signal it.").replace("%1", root.target.user)
                    : ""
                color: Commons.Color.urgent
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
                wrapMode: Text.WordWrap
            }

            Option {
                label: root.strings.t("Terminate")
                detail: root.strings.t("Sends SIGTERM, so the process can save its work and exit.")
                chosen: root.choice === 0
                onPicked: root.choice = 0
            }
            Option {
                label: root.strings.t("Force kill")
                detail: root.strings.t("Sends SIGKILL. The process cannot clean up, and unsaved work is lost.")
                chosen: root.choice === 1
                dangerous: true
                onPicked: root.choice = 1
            }

            Row {
                width: parent.width
                height: Commons.Style.spacing.controlHeight
                spacing: Commons.Style.spacing.sm

                Text {
                    width: parent.width * 0.55
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.strings.t("Enter confirms · Esc cancels")
                    color: Commons.Util.alpha(Commons.Color.foreground, 0.4)
                    font.family: Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.caption
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width * 0.45 - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: root.choice === 0
                        ? root.strings.t("Enter to terminate")
                        : root.strings.t("Enter to force kill")
                    color: root.choice === 0 ? Commons.Color.accent : Commons.Color.urgent
                    font.family: Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.caption
                    elide: Text.ElideRight
                }
            }
        }
    }
}
