import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// What starts with the session. User services can be switched here; the
// Hyprland and XDG entries are lines in config files, shown with their file.
FocusScope {
    id: page
    readonly property var sections: [
        { kind: "hyprland", title: qsTr("Hyprland"), hint: qsTr("Started by Hyprland at login. Change them in the file shown.") },
        { kind: "systemd", title: qsTr("User services"), hint: qsTr("systemd units that start with your session. Switching one off takes effect at the next login.") },
        { kind: "xdg", title: qsTr("XDG autostart"), hint: qsTr("Desktop entries in ~/.config/autostart and /etc/xdg/autostart.") }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        PageHeader {
            Layout.fillWidth: true
            title: qsTr("Startup")
            subtitle: qsTr("%n entries", "", services.startup.length)
            BusyIndicator { running: services.busy; visible: running; Layout.preferredHeight: 28; Layout.preferredWidth: 28 }
            ActionButton { icon: "\uf021"; text: qsTr("Refresh"); onClicked: services.refreshStartup() }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight + 30
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: col
                x: 20
                width: parent.width - 40
                spacing: 20
                Repeater {
                    model: page.sections
                    delegate: Card {
                        id: card
                        required property var modelData
                        readonly property var entries: services.startup.filter(e => e.kind === modelData.kind)
                        Layout.fillWidth: true
                        visible: entries.length > 0
                        title: modelData.title + "  (" + entries.length + ")"
                        ColumnLayout {
                            width: parent.width
                            spacing: 2
                            Label {
                                Layout.fillWidth: true
                                Layout.bottomMargin: 8
                                text: card.modelData.hint
                                wrapMode: Text.Wrap
                                font.pixelSize: 12
                                color: theme.colors.mutedForeground
                            }
                            Repeater {
                                model: card.entries
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: Math.min(4, theme.radius)
                                    color: entryHover.hovered ? theme.colors.lighterBackground : "transparent"
                                    HoverHandler { id: entryHover }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 12
                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            color: modelData.enabled ? theme.colors.green : theme.colors.mutedForeground
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                elide: Text.ElideRight
                                                font.pixelSize: 13
                                                color: modelData.enabled ? theme.colors.brightForeground : theme.colors.mutedForeground
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.kind === "systemd" ? modelData.command : modelData.command + "   ·   " + modelData.source
                                                elide: Text.ElideMiddle
                                                font.family: win.mono
                                                font.pixelSize: 11
                                                color: theme.colors.mutedForeground
                                            }
                                        }
                                        Label {
                                            visible: !modelData.toggleable
                                            text: modelData.enabled ? qsTr("Enabled") : qsTr("Disabled")
                                            font.pixelSize: 12
                                            color: theme.colors.lightForeground
                                        }
                                        Toggle {
                                            visible: modelData.toggleable
                                            checked: modelData.enabled
                                            onToggled: services.act(modelData.unit, checked ? "enable" : "disable", false)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
