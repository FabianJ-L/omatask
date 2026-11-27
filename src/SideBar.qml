import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Navigation down the left edge, like Windows 11's Task Manager, with a
// small live summary and the refresh speed at the bottom.
Rectangle {
    id: bar
    color: theme.colors.darkBackground
    property var model: []
    property int currentIndex: 0
    property bool compact: false

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: theme.colors.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.topMargin: 6
            Layout.bottomMargin: 14
            spacing: 10
            Rectangle {
                width: 26; height: 26
                radius: Math.min(6, theme.radius)
                color: theme.accent
                Label {
                    anchors.centerIn: parent
                    text: "󰐰"
                    font.family: win.iconFont
                    font.pixelSize: 14
                    color: theme.accentForeground
                }
            }
            Label {
                visible: !bar.compact
                text: "OmaTask"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                color: theme.colors.brightForeground
            }
        }

        Repeater {
            model: bar.model
            delegate: Rectangle {
                id: item
                required property int index
                required property var modelData
                readonly property bool current: bar.currentIndex === index
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: Math.min(6, theme.radius)
                color: current ? theme.colors.selection : hover.hovered ? theme.colors.lighterBackground : "transparent"

                Rectangle {
                    visible: item.current
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3; height: 18
                    radius: 1.5
                    color: theme.accent
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 12
                    Label {
                        Layout.preferredWidth: 18
                        horizontalAlignment: Text.AlignHCenter
                        text: item.modelData.icon
                        font.family: win.iconFont
                        font.pixelSize: 14
                        color: item.current ? theme.accent : theme.colors.lightForeground
                    }
                    Label {
                        visible: !bar.compact
                        Layout.fillWidth: true
                        text: item.modelData.title
                        elide: Text.ElideRight
                        font.pixelSize: 14
                        color: item.current ? theme.colors.brightForeground : theme.colors.foreground
                    }
                    Label {
                        visible: !bar.compact
                        text: item.index + 1
                        font.family: win.mono
                        font.pixelSize: 11
                        color: theme.colors.mutedForeground
                    }
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: bar.currentIndex = item.index }
                ToolTip.visible: bar.compact && hover.hovered
                ToolTip.text: item.modelData.title
                ToolTip.delay: 400
            }
        }

        Item { Layout.fillHeight: true }

        // A glance at the machine, whichever page is open. The values snap to
        // each new sample without animating; a fixed count keeps the rows
        // alive between samples instead of rebuilding them.
        ColumnLayout {
            visible: !bar.compact
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 4
            spacing: 14

            Repeater {
                model: bar.compact ? 0 : 4
                delegate: ColumnLayout {
                    required property int index
                    readonly property string label: [qsTr("CPU"), qsTr("Memory"), qsTr("GPU"), qsTr("Disk")][index]
                    readonly property real value: [monitor.cpuPercent, monitor.memPercent, monitor.gpuPercent, monitor.diskPercent][index]
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: label
                            font.pixelSize: 13
                            color: theme.colors.lightForeground
                        }
                        Label {
                            text: Math.round(value).toLocaleString(Qt.locale(translator.language), 'f', 0) + " %"
                            font.pixelSize: 13
                            font.family: win.mono
                            color: theme.colors.foreground
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: theme.colors.lighterBackground
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, value / 100))
                            height: parent.height
                            radius: 3
                            color: win.loadColor(value)
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: !bar.compact
            Layout.fillWidth: true
            Layout.topMargin: 14
            Layout.bottomMargin: 10
            height: 1
            color: theme.colors.border
        }

        ColumnLayout {
            visible: !bar.compact
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 8
            Label {
                Layout.fillWidth: true
                text: monitor.paused ? qsTr("Paused") : qsTr("Update speed")
                font.pixelSize: 12
                color: monitor.paused ? theme.colors.yellow : theme.colors.lightForeground
                elide: Text.ElideRight
            }
            Segmented {
                Layout.fillWidth: true
                small: true
                readonly property var values: [1000, 2000, 5000]
                options: [qsTr("Fast"), qsTr("Normal"), qsTr("Slow")]
                current: values.indexOf(monitor.interval)
                onPicked: index => monitor.interval = values[index]
            }
        }
        Label {
            visible: !bar.compact
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.topMargin: 6
            text: qsTr("Space pauses · ? shows shortcuts")
            font.pixelSize: 11
            color: theme.colors.mutedForeground
            elide: Text.ElideRight
        }
    }
}
