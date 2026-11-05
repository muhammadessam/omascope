//@ pragma AppId omascope
//@ pragma ShellId omascope

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

// The window, the keyboard, and the one connection to the Rust backend. The
// backend streams a JSON snapshot per second and accepts one line per action;
// the window never reads /proc itself.
FloatingWindow {
    id: win

    title: "omascope"
    implicitWidth: 1200
    implicitHeight: 740
    minimumSize: Qt.size(860, 520)
    color: Commons.Color.background
    visible: true

    // Every visible string goes through the catalog in ui/i18n, which follows
    // Setup > Language live.
    property var strings: translations
    property var meta: ({})
    property var processes: []
    property var rows: []
    property var lastTarget: null
    property string filterText: ""
    property string sortKey: "cpu"
    property bool sortAscending: false
    property bool treeView: false
    property var folded: ({})
    property int selectedPid: -1
    property var pendingKill: null
    property string notice: ""
    property bool noticeUrgent: false
    property double updatedAt: 0
    property double age: 0
    property string backendError: ""
    property bool backendReady: false

    readonly property var selectedProcess: {
        for (var i = 0; i < processes.length; i++)
            if (processes[i].pid === selectedPid) return processes[i]
        return null
    }
    readonly property int runningCount: {
        var count = 0
        for (var i = 0; i < processes.length; i++)
            if (processes[i].state === "R") count++
        return count
    }

    function fill(text, values) {
        var out = String(text)
        for (var i = 0; i < values.length; i++) out = out.replace("%" + (i + 1), values[i])
        return out
    }


    function compare(a, b) {
        var primary = 0
        if (sortKey === "name") {
            var left = a.name.toLowerCase(), right = b.name.toLowerCase()
            primary = left < right ? -1 : left > right ? 1 : 0
        } else if (sortKey === "mem") primary = a.rss - b.rss
        else if (sortKey === "pid") primary = a.pid - b.pid
        else primary = a.cpu - b.cpu
        if (primary === 0) return a.pid - b.pid
        return sortAscending ? primary : -primary
    }

    function matches(process, needle) {
        if (needle.length === 0) return true
        return process.name.toLowerCase().indexOf(needle) >= 0
            || process.cmd.toLowerCase().indexOf(needle) >= 0
            || process.user.toLowerCase().indexOf(needle) >= 0
            || String(process.pid).indexOf(needle) === 0
    }

    // The rows the list draws: filtered, then either a flat sorted list or a
    // tree of the matches plus the ancestors that give them their shape.
    function rebuild() {
        var needle = filterText.trim().toLowerCase()
        var byPid = ({})
        for (var i = 0; i < processes.length; i++) byPid[processes[i].pid] = processes[i]

        var matched = []
        for (var m = 0; m < processes.length; m++)
            if (matches(processes[m], needle)) matched.push(processes[m])

        var built = []
        if (!treeView) {
            matched.sort(compare)
            for (var f = 0; f < matched.length; f++) built.push(makeRow(matched[f], 0, false))
        } else {
            // A matching child without its parent would float, so keep every
            // ancestor of a match even when the ancestor itself does not match.
            var included = ({})
            for (var k = 0; k < matched.length; k++) {
                var walker = matched[k], guard = 0
                while (walker && !included[walker.pid] && guard++ < 256) {
                    included[walker.pid] = true
                    walker = byPid[walker.ppid]
                }
            }
            var ids = []
            for (var key in included) ids.push(Number(key))
            ids.sort(function (x, y) { return compare(byPid[x], byPid[y]) })

            var children = ({})
            var roots = []
            for (var r = 0; r < ids.length; r++) {
                var entry = byPid[ids[r]]
                if (included[entry.ppid]) {
                    if (!children[entry.ppid]) children[entry.ppid] = []
                    children[entry.ppid].push(entry)
                } else {
                    roots.push(entry)
                }
            }
            roots.sort(compare)

            var visit = function (process, depth) {
                var kids = children[process.pid] || []
                built.push(makeRow(process, depth, kids.length > 0))
                if (!folded[process.pid])
                    for (var c = 0; c < kids.length; c++) visit(kids[c], depth + 1)
            }
            for (var root = 0; root < roots.length; root++) visit(roots[root], 0)
        }

        rows = built
        if (built.length > 0 && indexOfPid(built, selectedPid) < 0) selectedPid = built[0].pid
        syncModel()
    }

    function makeRow(process, depth, hasChildren) {
        return {
            pid: process.pid,
            ppid: process.ppid,
            name: process.name,
            cpu: process.cpu,
            rss: process.rss,
            user: process.user,
            threads: process.threads,
            procState: process.state,
            cmd: process.cmd,
            started: process.started,
            depth: depth,
            kidCount: hasChildren ? 1 : 0,
            folded: folded[process.pid] ? 1 : 0
        }
    }

    function indexOfPid(list, pid) {
        for (var i = 0; i < list.length; i++) if (list[i].pid === pid) return i
        return -1
    }

    // Reconcile the ListModel in place instead of clearing it: clearing would
    // throw away the scroll position and the selected row every second.
    function syncModel() {
        var wanted = ({})
        for (var w = 0; w < rows.length; w++) wanted[rows[w].pid] = true
        for (var existing = rowModel.count - 1; existing >= 0; existing--)
            if (!wanted[rowModel.get(existing).pid]) rowModel.remove(existing)

        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]
            if (i >= rowModel.count) { rowModel.append(row); continue }
            if (rowModel.get(i).pid !== row.pid) {
                var from = -1
                for (var j = i + 1; j < rowModel.count; j++)
                    if (rowModel.get(j).pid === row.pid) { from = j; break }
                if (from < 0) { rowModel.insert(i, row); continue }
                rowModel.move(from, i, 1)
            }
            var current = rowModel.get(i)
            for (var key in row)
                if (current[key] !== row[key]) rowModel.setProperty(i, key, row[key])
        }
    }

    function setSort(key) {
        if (sortKey === key) {
            sortAscending = !sortAscending
        } else {
            sortKey = key
            sortAscending = key === "name" || key === "pid"
        }
        rebuild()
        revealSelection()
    }

    function setTree(tree) {
        treeView = tree
        rebuild()
        revealSelection()
    }

    function revealSelection() {
        var index = indexOfPid(rows, selectedPid)
        if (index >= 0) processList.positionViewAtIndex(index, ListView.Contain)
    }

    function selectAt(index) {
        if (rows.length === 0) return
        index = Math.max(0, Math.min(rows.length - 1, index))
        selectedPid = rows[index].pid
        processList.positionViewAtIndex(index, ListView.Contain)
    }

    function moveSelection(delta) {
        var index = indexOfPid(rows, selectedPid)
        if (index < 0) index = delta > 0 ? -1 : rows.length
        selectAt(index + delta)
    }

    function toggleFolded(pid) {
        var next = ({})
        for (var key in folded) next[key] = folded[key]
        if (next[pid]) delete next[pid]
        else next[pid] = true
        folded = next
        rebuild()
        revealSelection()
    }

    function foldSelected(open) {
        var index = indexOfPid(rows, selectedPid)
        if (index < 0 || !treeView) return
        var row = rows[index]
        if (!row.kidCount) return
        if (open ? row.folded : !row.folded) toggleFolded(row.pid)
    }

    function requestRefresh() {
        if (sampler.running) sampler.write("refresh\n")
    }

    function showNotice(text, urgent) {
        notice = text
        noticeUrgent = !!urgent
        noticeTimer.restart()
    }

    function askKill(process) {
        if (!process) return
        // PID 1 is the init system: signalling it is either refused by the
        // kernel or takes the session down, so the window says no first.
        if (process.pid <= 1) {
            showNotice(strings.t("The init system cannot be ended from here."), true)
            return
        }
        pendingKill = process
        killCard.open = true
    }

    function confirmKill(signal) {
        var target = pendingKill
        killCard.open = false
        pendingKill = null
        if (!target) return
        lastTarget = target
        sampler.write("kill " + target.pid + " " + signal + "\n")
        showNotice(fill(strings.t("Sending %1 to %2"), [signal, target.name]), false)
    }

    function consume(line) {
        var message = null
        try { message = JSON.parse(line) } catch (error) { return }
        if (!message || typeof message !== "object") return

        if (message.type === "snapshot") {
            backendReady = true
            backendError = ""
            meta = message
            processes = message.procs || []
            updatedAt = message.time
            rebuild()
            if (pendingKill) {
                // The target may have exited between the ask and the answer.
                var still = false
                for (var i = 0; i < processes.length; i++)
                    if (processes[i].pid === pendingKill.pid) still = true
                if (!still) {
                    killCard.open = false
                    pendingKill = null
                    showNotice(strings.t("That process has already exited."), false)
                }
            }
        } else if (message.type === "result") {
            var name = lastTarget ? lastTarget.name : String(message.pid)
            if (message.ok) showNotice(fill(strings.t("%1 sent to %2"), [message.signal, name]), false)
            else showNotice(message.message, true)
            requestRefresh()
        } else if (message.type === "error") {
            showNotice(message.message, true)
        } else if (message.type === "hello") {
            backendReady = true
            backendError = ""
        }
    }

    function handleKey(event) {
        if (killCard.open) {
            if (killCard.handleKey(event)) { event.accepted = true; return }
        }
        if (helpCard.open) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_QuestionMark) {
                helpCard.open = false
                event.accepted = true
            }
            return
        }

        switch (event.key) {
        case Qt.Key_J: moveSelection(1); break
        case Qt.Key_K: moveSelection(-1); break
        case Qt.Key_Down: moveSelection(1); break
        case Qt.Key_Up: moveSelection(-1); break
        case Qt.Key_Home: selectAt(0); break
        case Qt.Key_End: selectAt(rows.length - 1); break
        case Qt.Key_G:
            if (event.modifiers & Qt.ShiftModifier) selectAt(rows.length - 1)
            else selectAt(0)
            break
        case Qt.Key_Space: askKill(selectedProcess); break
        case Qt.Key_H: foldSelected(false); break
        case Qt.Key_L: foldSelected(true); break
        case Qt.Key_R: requestRefresh(); break
        case Qt.Key_S: setSort(sortKey); break
        case Qt.Key_Slash: chrome.focusSearch(); break
        case Qt.Key_QuestionMark: helpCard.open = true; break
        case Qt.Key_Escape: filterText = ""; chrome.clearSearch(); rebuild(); break
        case Qt.Key_Q: Qt.quit(); break
        case Qt.Key_1:
            if (event.modifiers & Qt.ControlModifier) setTree(false)
            else setSort("cpu")
            break
        case Qt.Key_2:
            if (event.modifiers & Qt.ControlModifier) setTree(true)
            else setSort("mem")
            break
        case Qt.Key_3: setSort("name"); break
        case Qt.Key_4: setSort("pid"); break
        default: return
        }
        event.accepted = true
    }

    // ------------------------------------------------------------- backend

    Process {
        id: sampler
        // `command` must be assigned before `running`, or Quickshell starts an
        // empty command and the sampler never runs.
        command: [Quickshell.env("OMASCOPE_BIN") || "/usr/bin/omascope", "serve", "--interval", "1000"]
            .concat(Quickshell.env("OMASCOPE_DEMO") ? ["--demo"] : [])
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: function (line) { win.consume(line) }
        }
        stderr: SplitParser {
            onRead: function (line) {
                if (line.trim().length > 0) win.backendError = line
            }
        }
        onExited: function (exitCode) {
            win.backendReady = false
            if (win.backendError.length === 0)
                win.backendError = win.strings.t("The process sampler stopped. Restart omascope.")
        }
    }

    // Quickshell does not expose a start-failure signal on Process, so a
    // sampler that never says hello is reported by a watchdog rather than
    // leaving a window that looks empty for no stated reason.
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            if (!win.backendReady && win.backendError.length === 0)
                win.backendError = win.strings.t("Could not start the omascope sampler. Is the binary installed?")
        }
    }

    // The catalogs follow Omarchy's language file, live. English lives in
    // en.json for the plural forms; other languages layer over it per string.
    Commons.Translations {
        id: translations
        directory: Quickshell.shellDir + "/i18n"
    }

    ListModel { id: rowModel }

    Timer {
        id: noticeTimer
        interval: 6000
        onTriggered: win.notice = ""
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: win.age = Math.max(0, Date.now() / 1000 - win.updatedAt)
    }

    // -------------------------------------------------------------- surface

    Rectangle {
        anchors.fill: parent
        color: Commons.Color.background
    }

    Item {
        id: keyRoot
        anchors.fill: parent
        focus: true
        Keys.onPressed: function (event) { win.handleKey(event) }
        LayoutMirroring.enabled: Commons.I18n.rightToLeft
        LayoutMirroring.childrenInherit: true

        QtObject {
            id: cols
            property real available: processList.width
            readonly property real pid: Math.max(Commons.Style.space(48), available * 0.055)
            readonly property real cpu: Math.max(Commons.Style.space(52), available * 0.065)
            readonly property real mem: Math.max(Commons.Style.space(62), available * 0.075)
            readonly property real user: Math.max(Commons.Style.space(74), available * 0.09)
            readonly property real name: Math.max(Commons.Style.space(120), available * 0.18)
            readonly property real command: Math.max(80, available - pid - cpu - mem - user - name)
        }

        Column {
            anchors.fill: parent
            spacing: 0

            ChromeBar {
                id: chrome
                width: parent.width
                strings: win.strings
                searchText: win.filterText
                sortKey: win.sortKey
                treeView: win.treeView
                onSearchEdited: function (text) { win.filterText = text; win.rebuild() }
                onSearchAccepted: { keyRoot.forceActiveFocus(); win.selectAt(0) }
                onSearchDismissed: { win.filterText = ""; win.rebuild(); keyRoot.forceActiveFocus() }
                onSortRequested: function (key) { win.setSort(key) }
                onViewRequested: function (tree) { win.setTree(tree) }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Commons.Util.alpha(Commons.Color.foreground, 0.12)
            }

            ColumnHeader {
                id: header
                width: parent.width
                columns: cols
                strings: win.strings
                sortKey: win.sortKey
                sortAscending: win.sortAscending
                onSortRequested: function (key) { win.setSort(key) }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Commons.Util.alpha(Commons.Color.foreground, 0.08)
            }

            Item {
                id: body
                width: parent.width
                height: parent.height - chrome.height - header.height - status.height - 2
                clip: true

                ListView {
                    id: processList
                    anchors.fill: parent
                    anchors.rightMargin: detail.visible ? detail.width + 1 : 0
                    model: rowModel
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 600
                    delegate: ProcessRow {
                        row: model
                        columns: cols
                        strings: win.strings
                        selected: model.pid === win.selectedPid
                        onPicked: win.selectedPid = model.pid
                        onActivated: win.askKill(win.selectedProcess)
                        onFoldRequested: function (pid) { win.toggleFolded(pid) }
                    }
                }

                // Empty states explain themselves: no rows is either a filter
                // that matched nothing or a backend that has not answered yet.
                Column {
                    visible: processList.count === 0
                    anchors.centerIn: processList
                    width: Math.min(parent.width - 80, 520)
                    spacing: Commons.Style.spacing.md

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: win.backendError.length > 0 ? win.backendError
                            : win.filterText.length > 0 ? win.fill(win.strings.t("No process matches “%1”"), [win.filterText])
                            : win.strings.t("Reading the process table…")
                        color: win.backendError.length > 0 ? Commons.Color.urgent : Commons.Color.muted
                        font.family: Commons.Style.font.family
                        font.pixelSize: Commons.Style.font.body
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        visible: win.filterText.length > 0
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: win.strings.t("Press Esc to clear the search.")
                        color: Commons.Color.muted
                        font.family: Commons.Style.font.family
                        font.pixelSize: Commons.Style.font.caption
                    }
                }

                DetailRail {
                    id: detail
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.round(Commons.Style.space(300))
                    visible: win.width >= 1000
                    strings: win.strings
                    process: win.selectedProcess
                    onKillRequested: function (target) { win.askKill(target) }
                }

                Rectangle {
                    visible: detail.visible
                    anchors.right: detail.left
                    width: 1
                    height: parent.height
                    color: Commons.Util.alpha(Commons.Color.foreground, 0.08)
                }
            }

            StatusBar {
                id: status
                width: parent.width
                strings: win.strings
                count: win.processes.length
                running: win.runningCount
                cores: win.meta.cores || 0
                load: win.meta.load1 || 0
                age: win.age
                notice: win.notice
                urgent: win.noticeUrgent
                down: win.backendError.length > 0
                onHelpRequested: helpCard.open = true
            }
        }

        KillCard {
            id: killCard
            anchors.fill: parent
            strings: win.strings
            target: win.pendingKill
            onCanceled: { win.pendingKill = null; keyRoot.forceActiveFocus() }
            onConfirmed: function (signal) { win.confirmKill(signal); keyRoot.forceActiveFocus() }
        }

        HelpCard {
            id: helpCard
            anchors.fill: parent
            strings: win.strings
            onClosed: keyRoot.forceActiveFocus()
        }
    }

    Component.onCompleted: keyRoot.forceActiveFocus()
}
