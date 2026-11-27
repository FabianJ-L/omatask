import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Every device as a small tile; the chosen one in detail below, with the
// only graph on the page.
FocusScope {
    id: page
    property string selectedId: "cpu"
    readonly property var device: {
        const list = monitor.devices
        for (let i = 0; i < list.length; ++i)
            if (list[i].id === selectedId) return list[i]
        return list.length ? list[0] : null
    }
    property bool showCores: false

    function colorFor(kind) {
        switch (kind) {
        case "memory": return theme.colors.magenta
        case "disk": return theme.colors.green
        case "network": return theme.colors.orange
        case "gpu": return theme.colors.cyan
        default: return theme.accent
        }
    }
    function step(delta) {
        const list = monitor.devices
        for (let i = 0; i < list.length; ++i)
            if (list[i].id === page.device.id) {
                const next = list[Math.max(0, Math.min(list.length - 1, i + delta))]
                selectedId = next.id
                return
            }
    }
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
    Keys.onUpPressed: step(-tiles.columns)
    Keys.onDownPressed: step(tiles.columns)
    VimKeys {
        id: vim
        left: () => page.step(-1)
        right: () => page.step(1)
        up: () => page.step(-tiles.columns)
        down: () => page.step(tiles.columns)
    }
    Keys.onPressed: event => {
        if (vim.handle(event)) { event.accepted = true; return }
        if (event.key === Qt.Key_C && page.device && page.device.kind === "cpu") { showCores = !showCores; event.accepted = true }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PageHeader {
            Layout.fillWidth: true
            title: qsTr("Performance")
            subtitle: qsTr("%n devices", "", monitor.devices.length)
            // The status strip is hidden on this page, so its controls live here.
            Label {
                visible: monitor.paused
                text: qsTr("Paused")
                font.pixelSize: ui.small
                font.weight: Font.DemiBold
                color: theme.colors.yellow
            }
            SpeedPicker {}
        }

        // Scrolls only when the window is too short for tiles and detail.
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: body.height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: body
                width: flick.width
                height: Math.max(flick.height, implicitHeight)
                spacing: 0

                // One tile per device: a glance at everything, click for detail.
                GridLayout {
                    id: tiles
                    Layout.fillWidth: true
                    Layout.leftMargin: ui.xl
                    Layout.rightMargin: ui.xl
                    // As many columns as fit, then balanced so the last row isn't a lone tile.
                    readonly property int fit: Math.max(2, Math.floor((page.width - 2 * ui.xl + ui.m) / (200 + ui.m)))
                    readonly property int count: Math.max(1, monitor.devices.length)
                    columns: Math.ceil(count / Math.ceil(count / fit))
                    columnSpacing: ui.m
                    rowSpacing: ui.m

                    // By count, so tiles update in place between samples.
                    Repeater {
                        model: monitor.devices.length
                        delegate: Rectangle {
                            id: tile
                            required property int index
                            readonly property var modelData: monitor.devices[index] || ({})
                            readonly property bool current: page.device && page.device.id === modelData.id
                            readonly property color tone: page.colorFor(modelData.kind)
                            Layout.fillWidth: true
                            Layout.preferredWidth: 200
                            readonly property bool network: modelData.kind === "network"
                            implicitHeight: 66
                            radius: ui.rLarge
                            color: current ? Qt.alpha(tone, 0.12) : tileHover.hovered ? ui.raised : ui.card
                            border.width: current ? 1 : 0
                            border.color: Qt.alpha(tone, 0.7)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: ui.m
                                anchors.rightMargin: ui.m
                                anchors.topMargin: ui.s + 2
                                anchors.bottomMargin: ui.s + 2
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ui.s
                                    Rectangle { width: 8; height: 8; radius: 4; color: tile.tone }
                                    Label {
                                        Layout.fillWidth: true
                                        text: tile.modelData.title || ""
                                        font.pixelSize: ui.body
                                        font.weight: Font.DemiBold
                                        color: theme.colors.brightForeground
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        text: tile.network
                                              ? (tile.modelData.stats && tile.modelData.stats.length ? "↓ " + tile.modelData.stats[0][1] : "")
                                              : (tile.modelData.asleep ? qsTr("Sleeping") : Math.round(tile.modelData.value || 0) + " %")
                                        font.family: win.mono
                                        font.pixelSize: ui.small
                                        color: tile.modelData.asleep ? theme.colors.mutedForeground : theme.colors.brightForeground
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 16
                                    text: tile.modelData.subtitle || ""
                                    font.pixelSize: ui.caption
                                    color: theme.colors.mutedForeground
                                    elide: Text.ElideRight
                                }
                                Item { Layout.fillHeight: true }
                                Meter {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 16
                                    implicitHeight: 3
                                    value: (tile.modelData.value || 0) / Math.max(1e-9, tile.modelData.scale || 100)
                                    tone: tile.tone
                                }
                            }
                            HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { page.selectedId = tile.modelData.id; page.forceActiveFocus() } }
                        }
                    }
                }

                // The chosen device in detail.
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: ui.xl
                    Layout.topMargin: ui.l
                    Layout.minimumHeight: implicitHeight
                    visible: page.device !== null
                    title: page.device ? page.device.title : ""
                    subtitle: page.device ? page.device.subtitle : ""
                    actions: [
                        Segmented {
                            visible: page.device !== null && page.device.kind === "cpu"
                            small: true
                            options: [qsTr("Overall"), qsTr("Logical processors")]
                            current: page.showCores ? 1 : 0
                            onPicked: index => page.showCores = index === 1
                        }
                    ]

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: ui.m

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: {
                                    if (!page.device) return ""
                                    switch (page.device.kind) {
                                    case "network": return qsTr("Throughput over the last minute")
                                    case "disk": return qsTr("Active time over the last minute")
                                    default: return qsTr("Utilization over the last minute")
                                    }
                                }
                                font.pixelSize: ui.small
                                color: theme.colors.mutedForeground
                            }
                            Item { Layout.fillWidth: true }
                            // Network has no fixed top; say what the graph's top line means.
                            Label {
                                visible: page.device && page.device.kind === "network"
                                text: page.device && page.device.kind === "network" ? page.device.valueText : ""
                                font.pixelSize: ui.small
                                color: theme.colors.lightForeground
                            }
                        }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 180

                                UsageGraph {
                                    anchors.fill: parent
                                    scrolling: true
                                    visible: !(page.showCores && page.device && page.device.kind === "cpu")
                                    values: page.device ? page.device.history : []
                                    values2: page.device && page.device.history2 ? page.device.history2 : []
                                    scale: page.device ? page.device.scale : 100
                                    color: page.device ? page.colorFor(page.device.kind) : theme.accent
                                    color2: theme.colors.cyan
                                }

                                // One bar per logical processor.
                                Grid {
                                    id: cores
                                    anchors.fill: parent
                                    visible: page.showCores && page.device && page.device.kind === "cpu"
                                    readonly property var values: page.device && page.device.cores ? page.device.cores : []
                                    columns: Math.ceil(Math.sqrt(values.length * 2))
                                    rows: Math.ceil(values.length / Math.max(1, columns))
                                    spacing: 6
                                    Repeater {
                                        model: cores.values.length
                                        delegate: Rectangle {
                                            required property int index
                                            readonly property real modelData: cores.values[index] || 0
                                            width: (cores.width - (cores.columns - 1) * cores.spacing) / cores.columns
                                            height: (cores.height - (cores.rows - 1) * cores.spacing) / cores.rows
                                            color: ui.canvas
                                            border.color: Qt.alpha(theme.accent, 0.5)
                                            radius: Math.min(4, theme.radius)
                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: parent.width - 2
                                                height: (parent.height - 2) * Math.min(1, modelData / 100)
                                                color: Qt.alpha(win.loadColor(modelData), 0.45)
                                                    }
                                            Label {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.margins: 6
                                                text: index
                                                font.pixelSize: ui.caption
                                                color: theme.colors.mutedForeground
                                            }
                                            Label {
                                                anchors.centerIn: parent
                                                text: Math.round(modelData) + " %"
                                                font.pixelSize: ui.body
                                                color: theme.colors.brightForeground
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: page.device && page.device.note !== undefined
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width - 40, noteText.implicitWidth + 40)
                                    height: noteText.implicitHeight + 28
                                    radius: Math.min(8, theme.radius)
                                    color: Qt.alpha(theme.colors.darkerBackground, 0.9)
                                    border.color: theme.colors.border
                                    Label {
                                        id: noteText
                                        anchors.centerIn: parent
                                        width: Math.min(implicitWidth, parent.parent.width - 80)
                                        text: page.device && page.device.note ? page.device.note : ""
                                        wrapMode: Text.Wrap
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: ui.body
                                        color: theme.colors.lightForeground
                                    }
                                }
                            }
                            RowLayout {
                                visible: page.device && page.device.kind === "network"
                                spacing: 18
                                Row { spacing: 6; Rectangle { width: 14; height: 3; y: 6; color: page.device ? page.colorFor("network") : "transparent" }
                                      Label { text: page.device && page.device.legend ? page.device.legend : ""; font.pixelSize: ui.small; color: theme.colors.lightForeground } }
                                Row { spacing: 6; Rectangle { width: 14; height: 3; y: 6; color: theme.colors.cyan }
                                      Label { text: page.device && page.device.legend2 ? page.device.legend2 : ""; font.pixelSize: ui.small; color: theme.colors.lightForeground } }
                            }

                        StatGrid {
                            Layout.fillWidth: true
                            stats: page.device ? page.device.stats : []
                        }
                    }
                }
            }
        }
    }
}
