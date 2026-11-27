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

    readonly property int statusWidth: 130
    readonly property int numberWidth: 92
    readonly property int pidWidth: 74
    // Less important columns step aside when the window is narrow, so the
    // name always stays readable.
    readonly property bool showStatus: width >= 840
    readonly property bool showPid: width >= 720
    readonly property bool showDisk: width >= 600
    readonly property bool showGpu: width >= 520

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
    function move(delta) {
        let row = list.currentIndex
        do { row += delta } while (row >= 0 && row < list.count && list.itemAtIndex(row) && list.itemAtIndex(row).kind === 0)
        if (row < 0 || row >= list.count) return
        list.currentIndex = row
        const item = list.itemAtIndex(row)
        if (item) select(item.key)
    }
    function heat(value, max) {
        return Qt.alpha(theme.accent, Math.min(0.42, value / max * 0.42))
    }

    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Delete) { endSelected(event.modifiers & Qt.ShiftModifier); event.accepted = true }
        else if (event.key === Qt.Key_Slash) { search.forceActiveFocus(); event.accepted = true }
        else if ((event.key === Qt.Key_Right || event.key === Qt.Key_Left || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                 && selectedKey.startsWith("g:")) {
            const item = list.itemAtIndex(list.currentIndex)
            const open = item && item.expanded
            if ((event.key === Qt.Key_Right && !open) || (event.key === Qt.Key_Left && open) || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                processes.toggle(selectedKey)
            event.accepted = true
        } else if (event.key === Qt.Key_G && !(event.modifiers & Qt.ControlModifier)) {
            processes.grouped = !processes.grouped
            event.accepted = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PageHeader {
            Layout.fillWidth: true
            title: qsTr("Processes")
            subtitle: qsTr("%n processes", "", processes.processCount)

            FilterField {
                id: search
                Layout.preferredWidth: page.width < 760 ? 160 : 260
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
            }
            ActionButton {
                kind: "danger"
                icon: "\uf00d"
                text: page.width < 620 ? "" : qsTr("End task")
                tip: text.length ? "" : qsTr("End task")
                enabled: page.selected.pid !== undefined && !page.selected.kernel
                onClicked: page.endSelected(false)
            }
        }

        // Column headers: click to sort, totals on top as in Windows.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: theme.colors.darkBackground
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 0
                HeaderCell { Layout.fillWidth: true; Layout.minimumWidth: 120; title: qsTr("Name"); column: "name"; alignRight: false }
                HeaderCell { visible: page.showStatus; Layout.preferredWidth: page.statusWidth; title: qsTr("Status"); column: ""; alignRight: false }
                HeaderCell { visible: page.showPid; Layout.preferredWidth: page.pidWidth; title: qsTr("PID"); column: "pid" }
                HeaderCell { Layout.preferredWidth: page.numberWidth; title: qsTr("CPU"); column: "cpu"; total: monitor.cpuPercent }
                HeaderCell { Layout.preferredWidth: page.numberWidth + 10; title: qsTr("Memory"); column: "mem"; total: monitor.memPercent }
                HeaderCell { visible: page.showDisk; Layout.preferredWidth: page.numberWidth; title: qsTr("Disk"); column: "disk"; total: monitor.diskPercent }
                HeaderCell { visible: page.showGpu; Layout.preferredWidth: page.numberWidth - 16; title: qsTr("GPU"); column: "gpu"; total: monitor.gpuPercent }
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

            delegate: Rectangle {
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
                height: kind === 0 ? 40 : 32
                color: isSelected ? theme.colors.selection : hover.hovered && kind !== 0 ? Qt.alpha(theme.colors.lighterBackground, 0.7) : "transparent"

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

                // Section heading: "Apps (12)".
                Label {
                    visible: row.kind === 0
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: row.name + "  (" + row.count + ")"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: theme.accent
                }

                RowLayout {
                    visible: row.kind !== 0
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 120
                        Layout.fillHeight: true
                        spacing: 8
                        Item { Layout.preferredWidth: row.depth * 34 }
                        Label {
                            Layout.preferredWidth: 14
                            text: row.expandable ? (row.expanded ? "" : "") : ""
                            font.family: win.iconFont
                            font.pixelSize: 10
                            color: theme.colors.lightForeground
                            TapHandler { onTapped: processes.toggle(row.key) }
                        }
                        Rectangle {
                            width: 20; height: 20
                            radius: row.depth > 0 ? 3 : Math.min(5, theme.radius + 2)
                            color: row.depth > 0 ? theme.colors.lighterBackground : Qt.alpha(theme.accent, 0.22)
                            Label {
                                anchors.centerIn: parent
                                text: row.name.length ? row.name.charAt(0).toUpperCase() : "?"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: row.depth > 0 ? theme.colors.lightForeground : theme.accent
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: row.expandable ? row.name + "  (" + row.count + ")" : row.name
                            elide: Text.ElideRight
                            font.pixelSize: 13
                            color: theme.colors.brightForeground
                        }
                    }
                    Label {
                        visible: page.showStatus
                        Layout.preferredWidth: page.statusWidth
                        text: row.status
                        elide: Text.ElideRight
                        font.pixelSize: 12
                        color: row.status === qsTr("Suspended") ? theme.colors.yellow : theme.colors.mutedForeground
                    }
                    Label {
                        visible: page.showPid
                        Layout.preferredWidth: page.pidWidth
                        horizontalAlignment: Text.AlignRight
                        rightPadding: 10
                        text: row.kind === 2 || !row.expandable ? row.pid : ""
                        font.family: win.mono
                        font.pixelSize: 12
                        color: theme.colors.mutedForeground
                    }
                    ValueCell { Layout.preferredWidth: page.numberWidth; text: row.cpuText; tint: page.heat(row.cpu, 50) }
                    ValueCell { Layout.preferredWidth: page.numberWidth + 10; text: row.memText; tint: page.heat(row.mem, 4 * 1024 * 1024 * 1024) }
                    ValueCell { visible: page.showDisk; Layout.preferredWidth: page.numberWidth; text: row.diskText; tint: page.heat(row.disk, 50 * 1024 * 1024) }
                    ValueCell { visible: page.showGpu; Layout.preferredWidth: page.numberWidth - 16; text: row.gpuText; tint: page.heat(row.gpu, 60) }
                }
            }
        }

        // What the selected row is, without opening anything.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: details.implicitHeight + 20
            visible: page.selected.pid !== undefined
            color: theme.colors.darkBackground
            Rectangle { width: parent.width; height: 1; color: theme.colors.border }
            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 4
                RowLayout {
                    spacing: 18
                    Label {
                        text: page.selected.name || ""
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: theme.colors.brightForeground
                    }
                    Label {
                        text: page.selected.isGroup ? qsTr("%n processes", "", page.selected.count || 0) : qsTr("PID %1").arg(page.selected.pid)
                        font.pixelSize: 12
                        color: theme.colors.lightForeground
                    }
                    Label { text: qsTr("User: %1").arg(page.selected.user || ""); font.pixelSize: 12; color: theme.colors.lightForeground }
                    Label { visible: page.width >= 700; text: qsTr("Threads: %1").arg(page.selected.threads || 0); font.pixelSize: 12; color: theme.colors.lightForeground }
                    Label { visible: page.width >= 800; text: qsTr("Priority: %1").arg(page.selected.nice || 0); font.pixelSize: 12; color: theme.colors.lightForeground }
                    Label {
                        visible: (page.selected.started || "").length > 0 && page.width >= 900
                        text: qsTr("Started: %1").arg(page.selected.started || "")
                        font.pixelSize: 12
                        color: theme.colors.lightForeground
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: page.selected.command || ""
                    elide: Text.ElideMiddle
                    font.family: win.mono
                    font.pixelSize: 11
                    color: theme.colors.mutedForeground
                }
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
