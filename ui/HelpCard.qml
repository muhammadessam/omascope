import QtQuick
import qs.Commons
import qs.Commons as Commons

// Every shortcut in the app, because a keyboard-first app that hides its keys
// is just a list of guesses.
Item {
    id: root

    property var strings
    property bool open: false

    signal closed()

    visible: open
    z: 30

    component KeyRow: Item {
        id: keyRow
        property string keys: ""
        property string action: ""
        width: parent ? parent.width : 0
        height: Math.max(keyLabel.implicitHeight, actionLabel.implicitHeight) + Commons.Style.spacing.sm

        Text {
            id: keyLabel
            width: Math.round(parent.width * 0.42)
            text: keyRow.keys
            color: Commons.Color.accent
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            elide: Text.ElideRight
        }
        Text {
            id: actionLabel
            x: Math.round(parent.width * 0.42) + Commons.Style.spacing.md
            width: parent.width - x
            text: keyRow.action
            color: Commons.Util.alpha(Commons.Color.foreground, 0.8)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            elide: Text.ElideRight
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Commons.Util.alpha(Commons.Color.background, 0.88)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closed()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(620, root.width - Commons.Style.spacing.xxl * 2)
        height: Math.min(root.height - Commons.Style.spacing.xxl * 2, layout.implicitHeight + Commons.Style.spacing.panelPadding * 2)
        color: Commons.Color.background
        radius: Commons.Style.cornerRadius
        border.width: Math.max(1, Math.round(Commons.Style.space(2)))
        border.color: Commons.Util.alpha(Commons.Color.foreground, 0.25)
        clip: true

        MouseArea { anchors.fill: parent }

        Flickable {
            anchors.fill: parent
            contentHeight: layout.implicitHeight + Commons.Style.spacing.panelPadding * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: layout
                x: Commons.Style.spacing.panelPadding
                y: Commons.Style.spacing.panelPadding
                width: card.width - Commons.Style.spacing.panelPadding * 2
                spacing: Commons.Style.spacing.lg

                Text {
                    text: root.strings.t("Keyboard")
                    color: Commons.Color.foreground
                    font.family: Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.heading
                    font.weight: Font.DemiBold
                }

                KeyRow { keys: "j  k  ↑  ↓"; action: root.strings.t("Move the selection") }
                KeyRow { keys: "g  G"; action: root.strings.t("First / last process") }
                KeyRow { keys: "Space"; action: root.strings.t("End the selected process…") }
                KeyRow { keys: "x"; action: root.strings.t("Force kill the selection") }
                KeyRow { keys: "h  l"; action: root.strings.t("Fold / unfold a tree branch") }
                KeyRow { keys: "/"; action: root.strings.t("Search name, user, or PID") }
                KeyRow { keys: "Esc"; action: root.strings.t("Clear the search or close a card") }
                KeyRow { keys: "Ctrl+1  Ctrl+2"; action: root.strings.t("List / tree") }
                KeyRow { keys: "1  2  3  4"; action: root.strings.t("Sort by CPU, memory, name, or PID") }
                KeyRow { keys: "s"; action: root.strings.t("Reverse the current order") }
                KeyRow { keys: "r"; action: root.strings.t("Refresh now") }
                KeyRow { keys: "?"; action: root.strings.t("This list") }
                KeyRow { keys: "q"; action: root.strings.t("Quit") }

                Text {
                    width: parent.width
                    text: root.strings.t("The same keys work in every view. Enter on a row, or a double-click, asks to end it. The detail rail has a Terminate and a Kill button for the selected process.")
                    color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
                    font.family: Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.caption
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
