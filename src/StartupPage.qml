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
            title: qsTr("Startup")
            subtitle: qsTr("%n entries", "", services.startup.length)
            BusyIndicator { running: services.busy; visible: running; Layout.preferredHeight: 28; Layout.preferredWidth: 28 }
            ActionButton { icon: "\u{F0450}"; text: qsTr("Refresh"); onClicked: services.refreshStartup() }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight + ui.xl
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: col
                x: ui.xl
                width: parent.width - 2 * ui.xl
                spacing: ui.l
                Repeater {
                    model: page.sections
                    delegate: Card {
                        id: card
                        required property var modelData
                        readonly property var entries: services.startup.filter(e => e.kind === modelData.kind)
                        Layout.fillWidth: true
                        visible: entries.length > 0
                        title: modelData.title
                        subtitle: String(entries.length)
                        ColumnLayout {
                            width: parent.width
                            spacing: 2
                            Label {
                                Layout.fillWidth: true
                                Layout.bottomMargin: ui.s
                                text: card.modelData.hint
                                wrapMode: Text.Wrap
                                font.pixelSize: ui.small
                                color: theme.colors.mutedForeground
                            }
                            Repeater {
                                model: card.entries
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 50
                                    radius: ui.rMed
                                    color: entryHover.hovered ? ui.raised : "transparent"
                                    HoverHandler { id: entryHover }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: ui.m
                                        anchors.rightMargin: ui.m
                                        spacing: ui.m
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
                                                font.pixelSize: ui.body
                                                color: modelData.enabled ? theme.colors.brightForeground : theme.colors.mutedForeground
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.kind === "systemd" ? modelData.command : modelData.command + "   ·   " + modelData.source
                                                elide: Text.ElideMiddle
                                                font.family: win.mono
                                                font.pixelSize: ui.caption
                                                color: theme.colors.mutedForeground
                                            }
                                        }
                                        Label {
                                            visible: !modelData.toggleable
                                            text: modelData.enabled ? qsTr("Enabled") : qsTr("Disabled")
                                            font.pixelSize: ui.small
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
