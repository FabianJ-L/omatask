import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// The battery on one side, temperatures and fans on the other.
FocusScope {
    id: page
    readonly property var battery: monitor.battery

    // Sensors grouped by chip, in the order they arrive.
    readonly property var groups: {
        const out = []
        const index = {}
        for (const s of monitor.sensors) {
            if (index[s.chip] === undefined) { index[s.chip] = out.length; out.push({ chip: s.chip, items: [] }) }
            out[index[s.chip]].items.push(s)
        }
        return out
    }


    // j and k scroll a row, Ctrl+d and Ctrl+u half a page, gg and G to the ends.
    function scrollBy(dy) {
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy))
    }
    VimKeys {
        id: vim
        down: () => page.scrollBy(40)
        up: () => page.scrollBy(-40)
        top: () => page.scrollBy(-flick.contentHeight)
        bottom: () => page.scrollBy(flick.contentHeight)
        halfDown: () => page.scrollBy(flick.height / 2)
        halfUp: () => page.scrollBy(-flick.height / 2)
    }
    Keys.onPressed: event => { if (vim.handle(event)) event.accepted = true }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        PageHeader {
            Layout.fillWidth: true
            title: qsTr("Sensors & battery")
            subtitle: page.battery.acOnline ? qsTr("Plugged in") : (page.battery.present ? qsTr("On battery") : "")
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: content.implicitHeight + ui.xl
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            GridLayout {
                id: content
                x: ui.xl
                width: parent.width - 2 * ui.xl
                columns: width > 860 ? 2 : 1
                columnSpacing: ui.l
                rowSpacing: ui.l

                Card {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.columnSpan: content.columns
                    visible: page.battery.present === true
                    title: qsTr("Battery")
                    ColumnLayout {
                        width: parent.width
                        spacing: 14
                        RowLayout {
                            spacing: 16
                            Label {
                                text: Math.round(page.battery.percent || 0) + " %"
                                font.pixelSize: 40
                                font.weight: Font.DemiBold
                                color: (page.battery.percent || 0) <= 15 && !page.battery.charging ? theme.colors.red : theme.colors.brightForeground
                            }
                            ColumnLayout {
                                spacing: 2
                                Label { text: page.battery.statusText || ""; font.pixelSize: 14; color: page.battery.charging ? theme.colors.green : theme.colors.foreground }
                                Label { visible: (page.battery.remainingText || "").length > 0; text: page.battery.charging ? qsTr("Full in %1").arg(page.battery.remainingText) : qsTr("%1 left").arg(page.battery.remainingText); font.pixelSize: ui.body; color: theme.colors.lightForeground }
                            }
                        }
                        Meter {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            value: (page.battery.percent || 0) / 100
                            tone: page.battery.charging ? theme.colors.green : (page.battery.percent || 0) <= 15 ? theme.colors.red : theme.accent
                        }
                        Label { text: qsTr("Power over the last minute"); font.pixelSize: ui.small; color: theme.colors.mutedForeground }
                        UsageGraph {
                            scrolling: true
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            values: page.battery.powerHistory || []
                            scale: {
                                let peak = 10
                                for (const v of (page.battery.powerHistory || [])) peak = Math.max(peak, v * 1.2)
                                return peak
                            }
                            color: page.battery.charging ? theme.colors.green : theme.colors.yellow
                        }
                        StatGrid { Layout.fillWidth: true; stats: page.battery.stats || [] }
                    }
                }

                // By count: cards and bars survive each sample instead of
                // being rebuilt.
                Repeater {
                    model: page.groups.length
                    delegate: Card {
                        required property int index
                        readonly property var modelData: page.groups[index] || ({ chip: "", items: [] })
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        title: modelData.chip
                        ColumnLayout {
                            width: parent.width
                            spacing: ui.m
                            Repeater {
                                id: items
                                readonly property var list: modelData.items
                                model: list.length
                                delegate: RowLayout {
                                    required property int index
                                    readonly property var modelData: items.list[index] || ({})
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Label {
                                        text: modelData.kind === "fan" ? "\u{F0210}" : "\u{F050F}"
                                        font.family: win.iconFont
                                        font.pixelSize: ui.body
                                        Layout.preferredWidth: 16
                                        color: theme.colors.mutedForeground
                                    }
                                    Label {
                                        Layout.preferredWidth: 150
                                        text: modelData.label
                                        elide: Text.ElideRight
                                        font.pixelSize: ui.body
                                        color: theme.colors.foreground
                                    }
                                    Meter {
                                        Layout.fillWidth: true
                                        implicitHeight: 6
                                        value: modelData.fraction || 0
                                        tone: modelData.level === 2 ? theme.colors.red : modelData.level === 1 ? theme.colors.yellow
                                             : modelData.kind === "fan" ? theme.colors.cyan : theme.accent
                                    }
                                    Label {
                                        Layout.preferredWidth: 80
                                        horizontalAlignment: Text.AlignRight
                                        text: modelData.text
                                        font.family: win.mono
                                        font.pixelSize: ui.body
                                        color: modelData.level === 2 ? theme.colors.red : modelData.level === 1 ? theme.colors.yellow : theme.colors.brightForeground
                                    }
                                }
                            }
                        }
                    }
                }

                Label {
                    visible: page.groups.length === 0 && page.battery.present !== true
                    text: qsTr("No sensors were found in /sys/class/hwmon.")
                    color: theme.colors.mutedForeground
                }
            }
        }
    }
}
