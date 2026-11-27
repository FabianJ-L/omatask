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

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        PageHeader {
            Layout.fillWidth: true
            title: qsTr("Sensors & battery")
            subtitle: page.battery.acOnline ? qsTr("Plugged in") : (page.battery.present ? qsTr("On battery") : "")
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: content.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            GridLayout {
                id: content
                x: 20
                width: parent.width - 40
                columns: width > 900 ? 2 : 1
                columnSpacing: 20
                rowSpacing: 20

                Card {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
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
                                Label { visible: (page.battery.remainingText || "").length > 0; text: page.battery.charging ? qsTr("Full in %1").arg(page.battery.remainingText) : qsTr("%1 left").arg(page.battery.remainingText); font.pixelSize: 13; color: theme.colors.lightForeground }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 10
                            radius: 5
                            color: theme.colors.darkBackground
                            Rectangle {
                                width: parent.width * Math.min(1, (page.battery.percent || 0) / 100)
                                height: parent.height
                                radius: 5
                                color: page.battery.charging ? theme.colors.green : (page.battery.percent || 0) <= 15 ? theme.colors.red : theme.accent
                            }
                        }
                        Label { text: qsTr("Power over the last minute"); font.pixelSize: 12; color: theme.colors.mutedForeground }
                        UsageGraph {
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

                Repeater {
                    model: page.groups
                    delegate: Card {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        title: modelData.chip
                        ColumnLayout {
                            width: parent.width
                            spacing: 10
                            Repeater {
                                model: modelData.items
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Label {
                                        text: modelData.kind === "fan" ? "\u{F0210}" : "\uf2c9"
                                        font.family: win.iconFont
                                        font.pixelSize: 13
                                        Layout.preferredWidth: 16
                                        color: theme.colors.mutedForeground
                                    }
                                    Label {
                                        Layout.preferredWidth: 150
                                        text: modelData.label
                                        elide: Text.ElideRight
                                        font.pixelSize: 13
                                        color: theme.colors.foreground
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 6
                                        radius: 3
                                        color: theme.colors.darkBackground
                                        Rectangle {
                                            width: parent.width * modelData.fraction
                                            height: parent.height
                                            radius: 3
                                            color: modelData.level === 2 ? theme.colors.red : modelData.level === 1 ? theme.colors.yellow
                                                 : modelData.kind === "fan" ? theme.colors.cyan : theme.accent
                                            Behavior on width { NumberAnimation { duration: 300 } }
                                        }
                                    }
                                    Label {
                                        Layout.preferredWidth: 80
                                        horizontalAlignment: Text.AlignRight
                                        text: modelData.text
                                        font.family: win.mono
                                        font.pixelSize: 13
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
