import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// One tile per device on the left, the chosen device in detail on the right.
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
    Keys.onUpPressed: step(-1)
    Keys.onDownPressed: step(1)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_C && page.device && page.device.kind === "cpu") { showCores = !showCores; event.accepted = true }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Device tiles
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: page.width < 760 ? 190 : 250
            color: theme.colors.darkBackground
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.colors.border }
            ListView {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                clip: true
                // By count, so tiles keep their graphs between samples.
                model: monitor.devices.length
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: tile
                    required property int index
                    readonly property var modelData: monitor.devices[index] || ({})
                    readonly property bool current: page.device && page.device.id === modelData.id
                    width: ListView.view.width
                    height: 66
                    radius: Math.min(6, theme.radius)
                    color: current ? theme.colors.selection : tileHover.hovered ? theme.colors.lighterBackground : "transparent"
                    border.color: current ? Qt.alpha(page.colorFor(modelData.kind), 0.6) : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10
                        UsageGraph {
                            Layout.preferredWidth: 64
                            Layout.fillHeight: true
                            values: tile.modelData.history
                            values2: tile.modelData.history2 || []
                            scale: tile.modelData.scale
                            color: page.colorFor(tile.modelData.kind)
                            grid: false
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                Layout.fillWidth: true
                                text: tile.modelData.title
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: theme.colors.brightForeground
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                text: tile.modelData.subtitle
                                font.pixelSize: 11
                                color: theme.colors.mutedForeground
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                text: tile.modelData.valueText || ""
                                font.pixelSize: 11
                                color: tile.modelData.asleep ? theme.colors.mutedForeground : theme.colors.lightForeground
                                elide: Text.ElideRight
                            }
                        }
                    }
                    HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { page.selectedId = tile.modelData.id; page.forceActiveFocus() } }
                }
            }
        }

        // Detail
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 20
            spacing: 14
            visible: page.device !== null

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: page.device ? page.device.title : ""
                    font.pixelSize: 26
                    font.weight: Font.DemiBold
                    color: theme.colors.brightForeground
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: page.device ? page.device.subtitle : ""
                    elide: Text.ElideRight
                    font.pixelSize: 15
                    color: theme.colors.lightForeground
                }
            }

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
                    font.pixelSize: 12
                    color: theme.colors.mutedForeground
                }
                Item { Layout.fillWidth: true }
                // Network has no fixed top; say what the graph's top line means.
                Label {
                    visible: page.device && page.device.kind === "network"
                    text: page.device && page.device.kind === "network" ? page.device.valueText : ""
                    font.pixelSize: 12
                    color: theme.colors.lightForeground
                }
                Segmented {
                    visible: page.device !== null && page.device.kind === "cpu"
                    small: true
                    options: [qsTr("Overall"), qsTr("Logical processors")]
                    current: page.showCores ? 1 : 0
                    onPicked: index => page.showCores = index === 1
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 160

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
                            color: theme.colors.darkBackground
                            border.color: Qt.alpha(theme.accent, 0.5)
                            radius: Math.min(4, theme.radius)
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 2
                                height: (parent.height - 2) * Math.min(1, modelData / 100)
                                color: Qt.alpha(win.loadColor(modelData), 0.45)
                                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                            Label {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 6
                                text: index
                                font.pixelSize: 11
                                color: theme.colors.mutedForeground
                            }
                            Label {
                                anchors.centerIn: parent
                                text: Math.round(modelData) + " %"
                                font.pixelSize: 13
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
                        font.pixelSize: 13
                        color: theme.colors.lightForeground
                    }
                }
            }

            RowLayout {
                visible: page.device && page.device.kind === "network"
                spacing: 18
                Row { spacing: 6; Rectangle { width: 14; height: 3; y: 6; color: page.device ? page.colorFor("network") : "transparent" }
                      Label { text: page.device && page.device.legend ? page.device.legend : ""; font.pixelSize: 12; color: theme.colors.lightForeground } }
                Row { spacing: 6; Rectangle { width: 14; height: 3; y: 6; color: theme.colors.cyan }
                      Label { text: page.device && page.device.legend2 ? page.device.legend2 : ""; font.pixelSize: 12; color: theme.colors.lightForeground } }
            }

            StatGrid {
                Layout.fillWidth: true
                stats: page.device ? page.device.stats : []
            }
        }
    }
}
