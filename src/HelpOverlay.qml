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
        ["Ctrl+Tab · Ctrl+L / H", qsTr("Next or previous page")],
        ["/", qsTr("Search")],
        ["j k · ↑ ↓", qsTr("Move through the list")],
        ["gg · G", qsTr("Jump to the top or the bottom")],
        ["Ctrl+D · Ctrl+U", qsTr("Half a page down or up")],
        ["l h · → ←", qsTr("Expand or collapse an app")],
        ["x · Del", qsTr("End the selected task")],
        ["X · Shift+Del", qsTr("Force the selected task to end")],
        ["A", qsTr("Group processes by app, or list them all")],
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
        height: content.implicitHeight + 2 * ui.xl
        radius: ui.rLarge
        color: ui.cardSolid
        border.color: theme.colors.border

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: ui.xl
            spacing: ui.l
            Label {
                text: qsTr("Keyboard shortcuts")
                font.pixelSize: ui.h2 - 2
                font.weight: Font.DemiBold
                color: theme.colors.brightForeground
            }
            GridLayout {
                columns: 2
                columnSpacing: ui.xl
                rowSpacing: ui.s
                Repeater {
                    model: overlay.shortcuts.length * 2
                    delegate: Text {
                        required property int index
                        readonly property var entry: overlay.shortcuts[Math.floor(index / 2)]
                        Layout.fillWidth: index % 2 === 1
                        text: entry[index % 2]
                        color: index % 2 ? theme.colors.foreground : theme.accent
                        font.family: index % 2 ? Qt.application.font.family : win.mono
                        font.pixelSize: ui.body
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
