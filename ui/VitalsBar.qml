import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// The machine at a glance, above the table: CPU, memory, and the first GPU
// when the driver reports one. Each line is the last ninety seconds.
Item {
    id: root

    property var strings
    property var meta: ({})
    property var cpuHistory: []
    property var memHistory: []
    property var gpuHistory: []
    property int cores: 0
    property real cpuTemp: -1

    readonly property var gpu: meta.gpus && meta.gpus.length > 0 ? meta.gpus[0] : null
    readonly property real memPercent: meta.memTotal > 0 ? meta.memUsed / meta.memTotal * 100 : 0

    implicitHeight: cards.height + Commons.Style.spacing.lg * 2
    visible: meta.cores > 0
    height: visible ? implicitHeight : 0

    function bytes(value) {
        if (!value || value <= 0) return "0"
        var units = ["B", "K", "M", "G", "T"]
        var number = value, unit = 0
        while (number >= 1024 && unit < units.length - 1) { number /= 1024; unit++ }
        return Commons.I18n.formatNumber(number, unit === 0 ? 0 : 1) + units[unit]
    }

    RowLayout {
        id: cards
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Commons.Style.spacing.rowPaddingX
        anchors.topMargin: Commons.Style.spacing.lg
        spacing: Commons.Style.spacing.lg

        Vital {
            Layout.fillWidth: true
            label: "CPU"
            value: Commons.I18n.formatNumber(root.meta.cpu || 0, 1) + "%"
            detail: {
                var parts = []
                if (root.cores > 0) parts.push(root.strings.t("%1 cores").replace("%1", Commons.I18n.formatNumber(root.cores, 0)))
                if (root.cpuTemp > 0) parts.push(Commons.I18n.formatNumber(root.cpuTemp, 0) + " °C")
                return parts.join("  ·  ")
            }
            values: root.cpuHistory
            maximum: 100
            lineColor: Commons.Color.accent
        }

        Vital {
            Layout.fillWidth: true
            label: root.strings.t("Memory")
            value: Commons.I18n.formatNumber(root.memPercent, 0) + "%"
            detail: {
                var text = root.bytes(root.meta.memUsed) + " " + root.strings.t("of %1").replace("%1", root.bytes(root.meta.memTotal))
                if (root.meta.swapUsed > 0)
                    text += "  ·  " + root.strings.t("Swap %1").replace("%1", root.bytes(root.meta.swapUsed))
                return text
            }
            values: root.memHistory
            maximum: 100
            lineColor: Commons.Util.alpha(Commons.Color.foreground, 0.7)
        }

        Vital {
            Layout.fillWidth: true
            visible: root.gpu !== null
            label: "GPU"
            value: Commons.I18n.formatNumber(root.gpu ? root.gpu.util : 0, 0) + "%"
            detail: root.gpu
                ? root.bytes(root.gpu.memUsed) + " / " + root.bytes(root.gpu.memTotal)
                    + (root.gpu.temp != null ? "  ·  " + Commons.I18n.formatNumber(root.gpu.temp, 0) + " °C" : "")
                : ""
            values: root.gpuHistory
            maximum: 100
            lineColor: Commons.Util.alpha(Commons.Color.accent, 0.72)
        }
    }
}
