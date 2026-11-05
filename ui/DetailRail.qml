import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// The selected process, laid out like Flea's preview column: identity first,
// then the numbers, then the two ways to end it. The action bar has a fixed
// height and the facts scroll above it, so neither can squeeze the other out
// of the window.
Rectangle {
    id: root

    property var strings
    property var process: null
    property var history: []

    signal killRequested(var target, string signal)

    color: Commons.Util.alpha(Commons.Color.foreground, 0.02)
    clip: true

    component Fact: Item {
        id: fact
        property string label: ""
        property string value: ""
        width: parent ? parent.width : 0
        implicitHeight: Math.max(factLabel.implicitHeight, factValue.implicitHeight) + Commons.Style.spacing.md
        height: implicitHeight

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

    // ------------------------------------------------------------- identity

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: headerColumn.height + Commons.Style.spacing.rowPaddingX * 2

        Column {
            id: headerColumn
            x: Commons.Style.spacing.rowPaddingX
            y: Commons.Style.spacing.rowPaddingX
            width: header.width - Commons.Style.spacing.rowPaddingX * 2
            spacing: Commons.Style.spacing.xxs

            Text {
                width: parent.width
                text: root.process ? root.process.name : ""
                color: Commons.Color.foreground
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.title
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
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
    }

    Rectangle {
        id: headerRule
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Commons.Util.alpha(Commons.Color.foreground, 0.08)
    }

    // --------------------------------------------------------------- actions

    Rectangle {
        id: actionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Commons.Style.spacing.controlHeight + Commons.Style.spacing.lg * 2
        color: Commons.Color.background

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: Commons.Util.alpha(Commons.Color.foreground, 0.08)
        }

        Row {
            id: actions
            anchors.fill: parent
            anchors.margins: Commons.Style.spacing.lg
            spacing: Commons.Style.spacing.sm

            Ui.Button {
                width: (actions.width - actions.spacing) / 2
                text: root.strings.t("Terminate")
                bordered: true
                fontSize: Commons.Style.font.bodySmall
                enabled: root.process !== null && root.process.pid > 1
                onClicked: root.killRequested(root.process, "TERM")
            }
            Ui.Button {
                width: (actions.width - actions.spacing) / 2
                text: root.strings.t("Kill")
                foreground: Commons.Color.urgent
                bordered: true
                fontSize: Commons.Style.font.bodySmall
                enabled: root.process !== null && root.process.pid > 1
                onClicked: root.killRequested(root.process, "KILL")
            }
        }
    }

    // ----------------------------------------------------------------- facts

    Flickable {
        id: scroller
        anchors.top: headerRule.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: actionBar.top
        contentHeight: content.height + Commons.Style.spacing.rowPaddingX * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            x: Commons.Style.spacing.rowPaddingX
            y: Commons.Style.spacing.rowPaddingX
            width: scroller.width - Commons.Style.spacing.rowPaddingX * 2
            spacing: Commons.Style.spacing.md

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

            // The process's own CPU over the same two minutes as the vitals.
            Column {
                width: parent.width
                spacing: Commons.Style.spacing.xs

                Text {
                    text: root.strings.t("CPU history")
                    color: Commons.Util.alpha(Commons.Color.foreground, 0.45)
                    font.family: Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.caption
                }
                Sparkline {
                    width: parent.width
                    height: Commons.Style.space(30)
                    values: root.history
                    maximum: 100
                    lineColor: Commons.Color.accent
                }
            }

            // Command line, wrapped; a process can have a very long one.
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
    }

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0"
        var units = ["B", "K", "M", "G", "T"]
        var value = bytes, unit = 0
        while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++ }
        return Commons.I18n.formatNumber(value, unit === 0 ? 0 : 1) + units[unit]
    }
}
