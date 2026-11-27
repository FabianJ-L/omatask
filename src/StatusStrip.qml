import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The machine at a glance across the top: one quiet line of values, each
// with a hairline meter. The graphs live on the Performance page only, so
// nothing is shown twice. A value opens its device there.
Rectangle {
    id: strip
    color: ui.canvas
    implicitHeight: 46
    signal deviceClicked(string id)

    // The first device of each kind, looked up once per sample.
    readonly property var entries: {
        const list = monitor.devices
        const first = kind => { for (const d of list) if (d.kind === kind) return d; return null }
        const out = []
        for (const [kind, label] of [["cpu", qsTr("CPU")], ["memory", qsTr("Memory")], ["gpu", qsTr("GPU")],
                                     ["disk", qsTr("Disk")], ["network", qsTr("Network")]]) {
            const d = first(kind)
            if (d) out.push({ kind: kind, label: label, device: d })
        }
        return out
    }
    function valueText(entry) {
        const d = entry.device
        if (entry.kind === "network" && d.stats && d.stats.length >= 2)
            return "↓ " + d.stats[0][1] + "  ↑ " + d.stats[1][1]
        return Math.round(d.value || 0).toLocaleString(Qt.locale(translator.language), 'f', 0) + " %"
    }

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.colors.border }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: ui.xl
        anchors.rightMargin: ui.xl
        anchors.bottomMargin: 1
        spacing: ui.xl

        // By count, so entries update in place.
        Repeater {
            model: strip.entries.length
            delegate: Item {
                id: entry
                required property int index
                readonly property var info: strip.entries[index] || ({ kind: "", label: "", device: ({}) })
                readonly property bool network: info.kind === "network"
                // Narrow windows keep CPU, memory and GPU; disk and network step aside.
                visible: index < 3 || strip.width >= (index === 3 ? 640 : 860)
                implicitWidth: row.implicitWidth
                implicitHeight: row.implicitHeight + 6

                RowLayout {
                    id: row
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -2
                    spacing: ui.s
                    Label {
                        text: entry.info.label
                        font.pixelSize: ui.small
                        color: hover.hovered ? theme.colors.foreground : theme.colors.mutedForeground
                    }
                    Label {
                        Layout.preferredWidth: entry.network ? implicitWidth : 38
                        horizontalAlignment: Text.AlignRight
                        text: strip.valueText(entry.info)
                        font.family: win.mono
                        font.pixelSize: ui.small
                        color: theme.colors.brightForeground
                    }
                }
                Meter {
                    visible: !entry.network
                    anchors.left: row.left
                    anchors.right: row.right
                    anchors.top: row.bottom
                    anchors.topMargin: 3
                    implicitHeight: 2
                    value: (entry.info.device.value || 0) / 100
                    tone: win.loadColor(entry.info.device.value || 0)
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: strip.deviceClicked(entry.info.device.id) }
                ToolTip.visible: hover.hovered
                ToolTip.text: entry.info.device.title || ""
                ToolTip.delay: 500
            }
        }

        Item { Layout.fillWidth: true }

        Label {
            visible: monitor.paused
            text: qsTr("Paused")
            font.pixelSize: ui.small
            font.weight: Font.DemiBold
            color: theme.colors.yellow
        }
        SpeedPicker { visible: strip.width >= 560 }
    }
}
