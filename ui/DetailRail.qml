import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// The selected process, laid out like Flea's preview column: identity first,
// then the numbers, then the action. Reading is cheap; nothing here acts
// without going through the confirmation card.
Rectangle {
    id: root

    property var strings
    property var process: null

    signal killRequested(var target)

    color: Commons.Util.alpha(Commons.Color.foreground, 0.02)

    component Fact: Item {
        id: fact
        property string label: ""
        property string value: ""
        width: parent ? parent.width : 0
        implicitHeight: Math.max(factLabel.implicitHeight, factValue.implicitHeight) + Commons.Style.spacing.md

        Text {
            id: factLabel
            anchors.left: parent.left
            anchors.top: parent.top
            text: fact.label
            color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
        }
        Text {
            id: factValue
            anchors.right: parent.right
            anchors.top: parent.top
            width: Math.max(0, parent.width - factLabel.implicitWidth - Commons.Style.spacing.md)
            horizontalAlignment: Text.AlignRight
            text: fact.value
            color: Commons.Color.foreground
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            elide: Text.ElideRight
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: Commons.Style.spacing.rowPaddingX
        anchors.bottomMargin: actionBar.height + Commons.Style.spacing.lg * 2
        spacing: Commons.Style.spacing.md

        // Identity
        Item {
            width: parent.width
            height: name.implicitHeight + metaLine.implicitHeight + Commons.Style.spacing.sm

            Text {
                id: name
                width: parent.width
                text: root.process ? root.process.name : ""
                color: Commons.Color.foreground
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.title
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                id: metaLine
                anchors.top: name.bottom
                width: parent.width
                text: root.process
                    ? root.strings.t("PID %1").replace("%1", Commons.I18n.formatNumber(root.process.pid, 0))
                    : ""
                color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
                elide: Text.ElideRight
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Commons.Util.alpha(Commons.Color.foreground, 0.08)
        }

        Fact {
            label: root.strings.t("State")
            value: root.process ? stateText(root.process.state) : ""
            function stateText(state) {
                if (state === "R") return root.strings.t("Running")
                if (state === "S") return root.strings.t("Sleeping")
                if (state === "D") return root.strings.t("Waiting")
                if (state === "T" || state === "t") return root.strings.t("Stopped")
                if (state === "Z") return root.strings.t("Zombie")
                if (state === "I") return root.strings.t("Idle")
                return state
            }
        }
        Fact {
            label: root.strings.t("User")
            value: root.process ? root.process.user : ""
        }
        Fact {
            label: root.strings.t("CPU")
            value: root.process ? Commons.I18n.formatNumber(root.process.cpu, 1) + "%" : ""
        }
        Fact {
            label: root.strings.t("Memory")
            value: root.process ? formatBytes(root.process.rss) : ""
        }
        Fact {
            label: root.strings.t("Threads")
            value: root.process ? Commons.I18n.formatNumber(root.process.threads, 0) : ""
        }
        Fact {
            label: root.strings.t("Parent")
            value: root.process ? Commons.I18n.formatNumber(root.process.ppid, 0) : ""
        }
        Fact {
            label: root.strings.t("Started")
            value: root.process
                ? Qt.formatDateTime(new Date(root.process.started * 1000), "yyyy-MM-dd HH:mm")
                : ""
        }

        // Command line, wrapped; a process can have a very long one and the
        // rail scrolls rather than cutting it off silently.
        Column {
            width: parent.width
            spacing: Commons.Style.spacing.xs

            Text {
                text: root.strings.t("Command line")
                color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
            }
            Rectangle {
                width: parent.width
                height: commandText.implicitHeight + Commons.Style.spacing.lg * 2
                color: Commons.Util.alpha(Commons.Color.foreground, 0.04)
                radius: Math.min(4, Commons.Style.cornerRadius)

                Text {
                    id: commandText
                    anchors.fill: parent
                    anchors.margins: Commons.Style.spacing.lg
                    text: root.process ? root.process.cmd : ""
                    color: Commons.Util.alpha(Commons.Color.foreground, 0.8)
                    font.family: Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.bodySmall
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }

    // Actions sit at the bottom, out of the scroll, so they never move under
    // the pointer while the facts above them change.
    Rectangle {
        id: actionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: actions.height + Commons.Style.spacing.lg * 2
        color: Commons.Color.background

        Row {
            id: actions
            anchors.fill: parent
            anchors.margins: Commons.Style.spacing.lg
            spacing: Commons.Style.spacing.sm

            Ui.Button {
                width: actions.width
                text: root.strings.t("End process…")
                bordered: true
                fontSize: Commons.Style.font.bodySmall
                enabled: root.process !== null && root.process.pid > 1
                onClicked: root.killRequested(root.process)
            }
        }
    }

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0"
        var units = ["B", "K", "M", "G", "T"]
        var value = bytes, unit = 0
        while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++ }
        return Commons.I18n.formatNumber(value, unit === 0 ? 0 : 1) + units[unit]
    }

    clip: true
}
