import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// systemd services, the user's own or the system's, with start, stop and
// restart. System changes go through polkit, which asks for the password.
FocusScope {
    id: page
    property string selectedUnit: ""
    readonly property var selected: {
        for (const u of services.units) if (u.unit === selectedUnit) return u
        return null
    }

    function stateText(u) {
        if (u.failed) return qsTr("Failed")
        if (u.running) return u.sub === "running" ? qsTr("Running") : qsTr("Active (%1)").arg(u.sub)
        return qsTr("Stopped")
    }
    function enabledText(state) {
        switch (state) {
        case "enabled": return qsTr("Starts automatically")
        case "disabled": return qsTr("Manual")
        case "static": return qsTr("Started by others")
        case "masked": return qsTr("Masked")
        default: return state
        }
    }
    function act(verb) {
        if (selected) services.act(selected.unit, verb, services.system)
    }

    Keys.onUpPressed: list.decrementCurrentIndex()
    Keys.onDownPressed: list.incrementCurrentIndex()
    function jumpTo(row) {
        if (list.count === 0) return
        list.currentIndex = Math.max(0, Math.min(list.count - 1, row))
        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    }
    readonly property int halfPage: Math.max(1, Math.floor(list.height / ui.row / 2))
    VimKeys {
        id: vim
        down: () => page.jumpTo(list.currentIndex + 1)
        up: () => page.jumpTo(list.currentIndex - 1)
        top: () => page.jumpTo(0)
        bottom: () => page.jumpTo(list.count - 1)
        halfDown: () => page.jumpTo(list.currentIndex + page.halfPage)
        halfUp: () => page.jumpTo(list.currentIndex - page.halfPage)
    }

    Keys.onPressed: event => {
        if (vim.handle(event)) { event.accepted = true; return }
        if (event.key === Qt.Key_Slash) { search.forceActiveFocus(); event.accepted = true }
        else if (event.key === Qt.Key_S && !(event.modifiers & Qt.ControlModifier)) { act(selected && selected.running ? "stop" : "start"); event.accepted = true }
        else if (event.key === Qt.Key_R && !(event.modifiers & Qt.ControlModifier)) { act("restart"); event.accepted = true }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        PageHeader {
            Layout.fillWidth: true
            title: qsTr("Services")
            subtitle: qsTr("%n services", "", services.units.length)

            FilterField {
                id: search
                Layout.preferredWidth: page.width < 760 ? 150 : 220
                placeholderText: qsTr("Search services")
                text: services.filter
                onTextChanged: services.filter = text
                Keys.onEscapePressed: { text = ""; page.forceActiveFocus() }
                Keys.onDownPressed: page.forceActiveFocus()
            }
            Segmented {
                options: [qsTr("User"), qsTr("System")]
                current: services.system ? 1 : 0
                onPicked: index => { services.system = index === 1; page.selectedUnit = "" }
            }
            BusyIndicator { running: services.busy; visible: running; Layout.preferredHeight: 28; Layout.preferredWidth: 28 }
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: ui.xl
            Layout.rightMargin: ui.xl
            Layout.bottomMargin: page.selected ? ui.m : ui.xl
            flush: true
            clip: true
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: ui.l + 6
                        anchors.rightMargin: ui.l + 6
                        spacing: ui.m
                        Item { Layout.preferredWidth: 10 }
                        Label { Layout.fillWidth: page.width < 720; Layout.preferredWidth: 240; text: qsTr("Name").toUpperCase(); font.pixelSize: ui.caption; font.weight: Font.DemiBold; font.letterSpacing: 0.6; color: theme.colors.mutedForeground }
                        Label { visible: page.width >= 720; Layout.fillWidth: true; text: qsTr("Description").toUpperCase(); font.pixelSize: ui.caption; font.weight: Font.DemiBold; font.letterSpacing: 0.6; color: theme.colors.mutedForeground }
                        Label { Layout.preferredWidth: 130; text: qsTr("Status").toUpperCase(); font.pixelSize: ui.caption; font.weight: Font.DemiBold; font.letterSpacing: 0.6; color: theme.colors.mutedForeground }
                        Label { visible: page.width >= 620; Layout.preferredWidth: 150; text: qsTr("Startup type").toUpperCase(); font.pixelSize: ui.caption; font.weight: Font.DemiBold; font.letterSpacing: 0.6; color: theme.colors.mutedForeground }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.colors.border }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: services.units
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    topMargin: 4
                    bottomMargin: 6
                    onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex < services.units.length) page.selectedUnit = services.units[currentIndex].unit
                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool isSelected: page.selectedUnit === modelData.unit
                        width: ListView.view.width
                        height: ui.row
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.topMargin: 1
                            anchors.bottomMargin: 1
                            radius: ui.rMed
                            color: row.isSelected ? Qt.alpha(theme.accent, 0.16) : rowHover.hovered ? ui.raised : "transparent"
                        }
                        HoverHandler { id: rowHover }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onTapped: (eventPoint, button) => {
                                list.currentIndex = row.index
                                page.selectedUnit = row.modelData.unit
                                page.forceActiveFocus()
                                if (button === Qt.RightButton) {
                                    const p = row.mapToItem(page, eventPoint.position.x, eventPoint.position.y)
                                    menu.popup(page, p.x, p.y)
                                }
                            }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ui.l + 6
                            anchors.rightMargin: ui.l + 6
                            spacing: ui.m
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: row.modelData.failed ? theme.colors.red : row.modelData.running ? theme.colors.green : theme.colors.border
                            }
                            Label { Layout.fillWidth: page.width < 720; Layout.preferredWidth: 240; text: row.modelData.name; elide: Text.ElideRight; font.pixelSize: ui.body; color: theme.colors.brightForeground }
                            Label { visible: page.width >= 720; Layout.fillWidth: true; text: row.modelData.description; elide: Text.ElideRight; font.pixelSize: ui.small; color: theme.colors.lightForeground }
                            Label {
                                Layout.preferredWidth: 130
                                text: page.stateText(row.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: ui.small
                                color: row.modelData.failed ? theme.colors.red : row.modelData.running ? theme.colors.green : theme.colors.mutedForeground
                            }
                            Label { visible: page.width >= 620; Layout.preferredWidth: 150; text: page.enabledText(row.modelData.enabled); elide: Text.ElideRight; font.pixelSize: ui.small; color: theme.colors.mutedForeground }
                        }
                    }
                }
            }
        }

        // Actions for the selected service.
        Card {
            Layout.fillWidth: true
            Layout.leftMargin: ui.xl
            Layout.rightMargin: ui.xl
            Layout.bottomMargin: ui.xl
            visible: page.selected !== null && page.selected !== undefined
            RowLayout {
                width: parent.width
                spacing: ui.s
                Label {
                    Layout.fillWidth: true
                    text: page.selected ? page.selected.unit : ""
                    elide: Text.ElideRight
                    font.family: win.mono
                    font.pixelSize: ui.small
                    color: theme.colors.lightForeground
                }
                ActionButton { icon: "\u{F040A}"; text: qsTr("Start"); enabled: page.selected !== null && !page.selected.running; onClicked: page.act("start") }
                ActionButton { icon: "\u{F04DB}"; text: qsTr("Stop"); kind: "danger"; enabled: page.selected !== null && page.selected.running; onClicked: page.act("stop") }
                ActionButton { icon: "\u{F0709}"; text: qsTr("Restart"); enabled: page.selected !== null; onClicked: page.act("restart") }
                ActionButton {
                    visible: page.selected && (page.selected.enabled === "enabled" || page.selected.enabled === "disabled")
                    text: page.selected && page.selected.enabled === "enabled" ? qsTr("Disable autostart") : qsTr("Enable autostart")
                    kind: "ghost"
                    icon: "\u{F14DF}"
                    onClicked: page.act(page.selected.enabled === "enabled" ? "disable" : "enable")
                }
            }
        }
    }

    Menu {
        id: menu
        Material.roundedScale: theme.radius
        MenuEntry { text: qsTr("Start"); enabled: page.selected && !page.selected.running; onTriggered: page.act("start") }
        MenuEntry { text: qsTr("Stop"); enabled: page.selected && page.selected.running; onTriggered: page.act("stop") }
        MenuEntry { text: qsTr("Restart"); onTriggered: page.act("restart") }
        MenuSeparator {}
        MenuEntry { text: qsTr("Enable autostart"); enabled: page.selected && page.selected.enabled === "disabled"; onTriggered: page.act("enable") }
        MenuEntry { text: qsTr("Disable autostart"); enabled: page.selected && page.selected.enabled === "enabled"; onTriggered: page.act("disable") }
    }
}
