import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Every shortcut on one screen.
Rectangle {
    id: overlay
    color: Qt.alpha(theme.colors.darkerBackground, 0.92)
    z: 100
    signal closeRequested()

    TapHandler { onTapped: overlay.closeRequested() }

    readonly property var shortcuts: [
        ["1 – 5", qsTr("Processes, Performance, Sensors, Startup, Services")],
        ["Ctrl+Tab", qsTr("Next page")],
        ["/", qsTr("Search")],
        ["↑ ↓", qsTr("Move through the list")],
        ["→ ← / Enter", qsTr("Expand or collapse an app")],
        ["Del", qsTr("End the selected task")],
        ["Shift+Del", qsTr("Force the selected task to end")],
        ["G", qsTr("Group processes by app, or list them all")],
        ["C", qsTr("Overall CPU or every logical processor")],
        ["S / R", qsTr("Start or stop, restart the selected service")],
        ["Space", qsTr("Pause or resume updates")],
        ["F5", qsTr("Update now")],
        ["Esc", qsTr("Close messages, leave the search")],
        ["? / F1", qsTr("Show or hide this help")],
        ["Q", qsTr("Quit")]
    ]

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(600, overlay.width - 48)
        height: content.implicitHeight + 56
        radius: Math.min(8, theme.radius)
        color: theme.colors.lighterBackground
        border.color: theme.colors.border

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16
            Label {
                text: qsTr("Keyboard shortcuts")
                font.pixelSize: 18
                font.weight: Font.DemiBold
                color: theme.colors.brightForeground
            }
            GridLayout {
                columns: 2
                columnSpacing: 24
                rowSpacing: 7
                Repeater {
                    model: overlay.shortcuts.length * 2
                    delegate: Text {
                        required property int index
                        readonly property var entry: overlay.shortcuts[Math.floor(index / 2)]
                        Layout.fillWidth: index % 2 === 1
                        text: entry[index % 2]
                        color: index % 2 ? theme.colors.foreground : theme.accent
                        font.family: index % 2 ? Qt.application.font.family : win.mono
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
