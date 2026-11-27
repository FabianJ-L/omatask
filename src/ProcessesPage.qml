import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Every running process, grouped by app, with live CPU, memory, disk and GPU
// use. The busier a cell, the stronger its tint, like Windows' heat map.
FocusScope {
    id: page
    property string selectedKey: ""
    property var selected: ({})

    readonly property int numberWidth: 92
    readonly property int pidWidth: 74
    // Less important columns step aside when the window is narrow, so the
    // name always stays readable.
    readonly property real tableWidth: width - 2 * ui.xl - (sidePanel && hasSelection ? 290 + ui.l : 0)
    readonly property bool showPid: tableWidth >= 680
    readonly property bool showDisk: tableWidth >= 560
    readonly property bool showGpu: tableWidth >= 470

    function select(key) {
        selectedKey = key
        refreshSelected()
    }
    function refreshSelected() {
        selected = selectedKey.length ? processes.details(selectedKey) : ({})
        const row = processes.rowOf(selectedKey)
        if (row >= 0) list.currentIndex = row
    }
    Connections {
        target: processes
        function onRefreshed() {
            if (page.selectedKey.length && processes.rowOf(page.selectedKey) < 0) page.select("")
            else page.refreshSelected()
        }
    }

    function endSelected(force) {
        if (!selected.pid) return
        if (force || selected.critical) {
            confirm.force = force
            confirm.open()
            return
        }
        processes.endTask(selectedKey, false)
    }
    // Selects the first process row at or after target (in direction dir),
    // scrolling it into view; section headings are skipped. Delegates far
    // off screen don't exist yet, so each candidate is laid out first.
    function jumpTo(target, dir) {
        if (list.count === 0) return
        let row = Math.max(0, Math.min(list.count - 1, target))
        for (let n = 0; n < list.count; ++n) {
            list.positionViewAtIndex(row, ListView.Contain)
            list.forceLayout()
            const item = list.itemAtIndex(row)
            if (item && item.kind !== 0) {
                list.currentIndex = row
                select(item.key)
                return
            }
            row += dir
            if (row < 0 || row >= list.count) { dir = -dir; row += 2 * dir }
        }
    }
    function move(delta) { jumpTo(list.currentIndex + delta, delta < 0 ? -1 : 1) }
    readonly property int halfPage: Math.max(1, Math.floor(list.height / ui.row / 2))
    function setExpanded(open) {
        if (!selectedKey.startsWith("g:")) return
        const item = list.itemAtIndex(list.currentIndex)
        if (item && item.expanded !== open) processes.toggle(selectedKey)
    }

    VimKeys {
        id: vim
        down: () => page.move(1)
        up: () => page.move(-1)
        left: () => page.setExpanded(false)
        right: () => page.setExpanded(true)
        top: () => page.jumpTo(0, 1)
        bottom: () => page.jumpTo(list.count - 1, -1)
        halfDown: () => page.move(page.halfPage)
        halfUp: () => page.move(-page.halfPage)
    }

    // How full a cell's meter is: the same scales the heat map used.
    function load(value, max) { return Math.min(1, value / max) }

    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onPressed: event => {
        if (vim.handle(event)) { event.accepted = true; return }
        if (event.text === "x" || event.text === "X") { endSelected(event.text === "X"); event.accepted = true }
        else if (event.text === "a") { processes.grouped = !processes.grouped; event.accepted = true }
        else if (event.key === Qt.Key_Delete) { endSelected(event.modifiers & Qt.ShiftModifier); event.accepted = true }
        else if (event.key === Qt.Key_Slash) { search.forceActiveFocus(); event.accepted = true }
        else if ((event.key === Qt.Key_Right || event.key === Qt.Key_Left || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                 && selectedKey.startsWith("g:")) {
            const item = list.itemAtIndex(list.currentIndex)
            const open = item && item.expanded
            if ((event.key === Qt.Key_Right && !open) || (event.key === Qt.Key_Left && open) || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                processes.toggle(selectedKey)
            event.accepted = true
        }
    }

    // The selected row as label/value pairs for the inspector.
    readonly property var selectedStats: {
        const s = page.selected
        if (s.pid === undefined) return []
        const out = []
        out.push(s.isGroup ? [qsTr("Processes"), String(s.count || 0)] : [qsTr("PID"), String(s.pid)])
        out.push([qsTr("User"), s.user || "–"])
        out.push([qsTr("Threads"), String(s.threads || 0)])
        out.push([qsTr("Priority"), String(s.nice || 0)])
        if ((s.started || "").length) out.push([qsTr("Started"), s.started])
        return out
    }
    readonly property bool hasSelection: selected.pid !== undefined
    readonly property bool sidePanel: width >= 980

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PageHeader {
            Layout.fillWidth: true
            title: qsTr("Processes")
            subtitle: qsTr("%n processes", "", processes.processCount)

            FilterField {
                id: search
                Layout.preferredWidth: page.width < 560 ? 140 : page.width < 760 ? 190 : 260
                placeholderText: qsTr("Search name, command or PID")
                text: processes.filter
                onTextChanged: processes.filter = text
                Keys.onEscapePressed: { text = ""; page.forceActiveFocus() }
                Keys.onDownPressed: page.forceActiveFocus()
            }
            Toggle {
                text: page.width < 760 ? "" : qsTr("Group by app")
                checked: processes.grouped
                onToggled: processes.grouped = checked
                ToolTip.visible: text.length === 0 && groupHover.hovered
                ToolTip.text: qsTr("Group by app")
                HoverHandler { id: groupHover }
            }
            ActionButton {
                visible: !(page.sidePanel && page.hasSelection)
                kind: "danger"
                icon: "\u{F0156}"
                text: page.width < 620 ? "" : qsTr("End task")
                tip: text.length ? "" : qsTr("End task")
                enabled: page.selected.pid !== undefined && !page.selected.kernel
                onClicked: page.endSelected(false)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: ui.xl
            Layout.rightMargin: ui.xl
            Layout.bottomMargin: ui.xl
            spacing: ui.l

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                flush: true
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Column titles: click to sort.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ui.l + 6
                            anchors.rightMargin: 6
                            spacing: 0
                            HeaderCell { Layout.fillWidth: true; Layout.minimumWidth: 120; title: qsTr("Name"); column: "name"; alignRight: false }
                            HeaderCell { visible: page.showPid; Layout.preferredWidth: page.pidWidth; title: qsTr("PID"); column: "pid" }
                            HeaderCell { Layout.preferredWidth: page.numberWidth; title: qsTr("CPU"); column: "cpu" }
                            HeaderCell { Layout.preferredWidth: page.numberWidth + 10; title: qsTr("Memory"); column: "mem" }
                            HeaderCell { visible: page.showDisk; Layout.preferredWidth: page.numberWidth; title: qsTr("Disk"); column: "disk" }
                            HeaderCell { visible: page.showGpu; Layout.preferredWidth: page.numberWidth - 16; title: qsTr("GPU"); column: "gpu" }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.colors.border }
                    }

                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: processes
                        boundsBehavior: Flickable.StopAtBounds
                        highlightFollowsCurrentItem: false
                        ScrollBar.vertical: ScrollBar {}
                        currentIndex: -1
                        topMargin: 4
                        bottomMargin: 6

                        delegate: Item {
                            id: row
                            required property int index
                            required property int kind
                            required property string key
                            required property string name
                            required property string command
                            required property int pid
                            required property double cpu
                            required property string cpuText
                            required property double mem
                            required property string memText
                            required property double disk
                            required property string diskText
                            required property double gpu
                            required property string gpuText
                            required property string status
                            required property int depth
                            required property bool expandable
                            required property bool expanded
                            required property int count
                            readonly property bool isSelected: page.selectedKey === key

                            width: ListView.view.width
                            height: kind === 0 ? 36 : ui.row

                            // The row as a pill, inset from the card's edges.
                            Rectangle {
                                visible: row.kind !== 0
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                anchors.topMargin: 1
                                anchors.bottomMargin: 1
                                radius: ui.rMed
                                color: row.isSelected ? Qt.alpha(theme.accent, 0.16) : hover.hovered ? ui.raised : "transparent"
                                Rectangle {
                                    visible: row.isSelected
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3; height: 16; radius: 1.5
                                    color: theme.accent
                                }
                            }

                            HoverHandler { id: hover }
                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onTapped: { if (row.kind !== 0) { page.select(row.key); page.forceActiveFocus() } }
                                onDoubleTapped: if (row.expandable) processes.toggle(row.key)
                            }
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: eventPoint => {
                                    if (row.kind === 0) return
                                    page.select(row.key)
                                    const p = row.mapToItem(page, eventPoint.position.x, eventPoint.position.y)
                                    menu.popup(page, p.x, p.y)
                                }
                            }

                            // Section heading: "APPS · 12".
                            Label {
                                visible: row.kind === 0
                                anchors.left: parent.left
                                anchors.leftMargin: ui.l + 6
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 6
                                text: row.name.toUpperCase() + "  ·  " + row.count
                                font.pixelSize: ui.caption
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.6
                                color: theme.colors.mutedForeground
                            }

                            RowLayout {
                                visible: row.kind !== 0
                                anchors.fill: parent
                                anchors.leftMargin: ui.l + 6
                                anchors.rightMargin: 6
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 120
                                    Layout.fillHeight: true
                                    spacing: ui.s
                                    Item { Layout.preferredWidth: row.depth * 30 }
                                    Label {
                                        Layout.preferredWidth: 14
                                        text: row.expandable ? (row.expanded ? "\u{F0140}" : "\u{F0142}") : ""
                                        font.family: win.iconFont
                                        font.pixelSize: 14
                                        color: theme.colors.mutedForeground
                                        TapHandler { onTapped: processes.toggle(row.key) }
                                    }
                                    Rectangle {
                                        width: 22; height: 22
                                        radius: row.depth > 0 ? ui.rSmall : Math.min(6, theme.radius + 2)
                                        color: row.depth > 0 ? ui.raised : Qt.alpha(theme.accent, 0.18)
                                        Label {
                                            anchors.centerIn: parent
                                            text: row.name.length ? row.name.charAt(0).toUpperCase() : "?"
                                            font.pixelSize: ui.caption
                                            font.weight: Font.DemiBold
                                            color: row.depth > 0 ? theme.colors.lightForeground : theme.accent
                                        }
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: row.name
                                        elide: Text.ElideRight
                                        font.pixelSize: ui.body
                                        color: theme.colors.brightForeground
                                    }
                                    // Only unusual states are worth a word: suspended, zombie, stuck on disk.
                                    Label {
                                        readonly property bool unusual: row.status.length > 0 && row.status !== qsTr("Running")
                                                                        && row.status !== qsTr("Sleeping") && row.status !== qsTr("Idle")
                                        visible: unusual
                                        text: row.status
                                        font.pixelSize: ui.caption
                                        color: row.status === qsTr("Suspended") ? theme.colors.yellow : theme.colors.red
                                        leftPadding: 6; rightPadding: 6; topPadding: 1; bottomPadding: 1
                                        background: Rectangle { radius: height / 2; color: Qt.alpha(parent.color, 0.15) }
                                    }
                                    Label {
                                        visible: row.expandable
                                        Layout.rightMargin: ui.s
                                        text: row.count
                                        font.pixelSize: ui.caption
                                        color: theme.colors.mutedForeground
                                        leftPadding: 6; rightPadding: 6; topPadding: 1; bottomPadding: 1
                                        background: Rectangle { radius: height / 2; color: ui.raised }
                                    }
                                }
                                Label {
                                    visible: page.showPid
                                    Layout.preferredWidth: page.pidWidth
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: ui.m
                                    text: row.kind === 2 || !row.expandable ? row.pid : ""
                                    font.family: win.mono
                                    font.pixelSize: ui.small
                                    color: theme.colors.mutedForeground
                                }
                                ValueCell { Layout.preferredWidth: page.numberWidth; text: row.cpuText; fraction: page.load(row.cpu, 50) }
                                ValueCell { Layout.preferredWidth: page.numberWidth + 10; text: row.memText; fraction: page.load(row.mem, 4 * 1024 * 1024 * 1024) }
                                ValueCell { visible: page.showDisk; Layout.preferredWidth: page.numberWidth; text: row.diskText; fraction: page.load(row.disk, 50 * 1024 * 1024) }
                                ValueCell { visible: page.showGpu; Layout.preferredWidth: page.numberWidth - 16; text: row.gpuText; fraction: page.load(row.gpu, 60) }
                            }
                        }
                    }
                }
            }

            // Inspector: what the selected row is, beside the list on wide windows.
            Card {
                visible: page.sidePanel && page.hasSelection
                Layout.preferredWidth: 290
                Layout.fillHeight: true
                title: page.selected.name || ""

                ColumnLayout {
                    anchors.fill: parent
                    spacing: ui.l

                    StatGrid {
                        visible: page.selected.pid !== undefined
                        Layout.fillWidth: true
                        stats: page.selectedStats
                        cellWidth: 110
                    }
                    ColumnLayout {
                        visible: (page.selected.command || "").length > 0
                        Layout.fillWidth: true
                        spacing: 2
                        Label { text: qsTr("Command line"); font.pixelSize: ui.small; color: theme.colors.mutedForeground }
                        Label {
                            Layout.fillWidth: true
                            text: page.selected.command || ""
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 6
                            elide: Text.ElideRight
                            font.family: win.mono
                            font.pixelSize: ui.caption
                            color: theme.colors.lightForeground
                        }
                    }
                    Item { Layout.fillHeight: true }
                    ColumnLayout {
                        visible: page.selected.pid !== undefined
                        Layout.fillWidth: true
                        spacing: ui.s
                        ActionButton {
                            Layout.fillWidth: true
                            kind: "danger"
                            icon: "\u{F0156}"
                            text: qsTr("End task")
                            enabled: !page.selected.kernel
                            onClicked: page.endSelected(false)
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            icon: page.selected.suspended ? "\u{F040A}" : "\u{F03E4}"
                            text: page.selected.suspended ? qsTr("Resume") : qsTr("Suspend")
                            enabled: !page.selected.kernel && !page.selected.critical
                            onClicked: processes.suspend(page.selectedKey, !page.selected.suspended)
                        }
                    }
                }
            }
        }

        // The same details under the list when the window is narrow.
        Card {
            Layout.fillWidth: true
            Layout.leftMargin: ui.xl
            Layout.rightMargin: ui.xl
            Layout.bottomMargin: ui.xl
            Layout.topMargin: -ui.s
            visible: !page.sidePanel && page.selected.pid !== undefined
            title: page.selected.name || ""
            subtitle: page.selected.command || ""
            StatGrid {
                width: parent.width
                stats: page.selectedStats
            }
        }
    }

    Menu {
        id: menu
        Material.roundedScale: theme.radius
        MenuEntry { text: qsTr("End task"); enabled: !page.selected.kernel; onTriggered: page.endSelected(false) }
        MenuEntry { text: qsTr("Force end (kill)"); enabled: !page.selected.kernel; onTriggered: page.endSelected(true) }
        MenuSeparator {}
        MenuEntry {
            text: page.selected.suspended ? qsTr("Resume") : qsTr("Suspend")
            enabled: !page.selected.kernel && !page.selected.critical
            onTriggered: processes.suspend(page.selectedKey, !page.selected.suspended)
        }
        Menu {
            title: qsTr("Priority")
            Material.roundedScale: theme.radius
            Repeater {
                model: [
                    { text: qsTr("High"), nice: -10 },
                    { text: qsTr("Above normal"), nice: -5 },
                    { text: qsTr("Normal"), nice: 0 },
                    { text: qsTr("Below normal"), nice: 5 },
                    { text: qsTr("Low"), nice: 15 }
                ]
                delegate: MenuEntry {
                    required property var modelData
                    text: modelData.text
                    checkable: true
                    checked: page.selected.nice === modelData.nice
                    onTriggered: processes.setPriority(page.selectedKey, modelData.nice)
                }
            }
        }
        MenuSeparator {}
        MenuEntry {
            text: page.selected.isGroup ? qsTr("Collapse or expand") : qsTr("Copy command line")
            onTriggered: {
                if (page.selected.isGroup) { processes.toggle(page.selectedKey); return }
                clipboard.text = page.selected.command
                clipboard.selectAll()
                clipboard.copy()
            }
        }
    }
    TextEdit { id: clipboard; visible: false }

    ConfirmDialog {
        id: confirm
        property bool force: false
        title: force ? qsTr("Force “%1” to end?").arg(page.selected.name) : qsTr("End “%1”?").arg(page.selected.name)
        message: page.selected.critical
                 ? qsTr("This is part of your desktop session. Ending it closes every window and logs you out.")
                 : qsTr("Forcing a process to end loses anything it has not saved.")
        acceptText: force ? qsTr("Force end") : qsTr("End task")
        onAccepted: processes.endTask(page.selectedKey, force)
    }
}
