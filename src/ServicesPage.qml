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
    Keys.onPressed: event => {
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

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            color: theme.colors.darkBackground
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12
                Item { Layout.preferredWidth: 10 }
                Label { Layout.fillWidth: page.width < 720; Layout.preferredWidth: 240; text: qsTr("Name"); font.pixelSize: 12; color: theme.colors.lightForeground }
                Label { visible: page.width >= 720; Layout.fillWidth: true; text: qsTr("Description"); font.pixelSize: 12; color: theme.colors.lightForeground }
                Label { Layout.preferredWidth: 130; text: qsTr("Status"); font.pixelSize: 12; color: theme.colors.lightForeground }
                Label { visible: page.width >= 620; Layout.preferredWidth: 150; text: qsTr("Startup type"); font.pixelSize: 12; color: theme.colors.lightForeground }
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
            onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex < services.units.length) page.selectedUnit = services.units[currentIndex].unit
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isSelected: page.selectedUnit === modelData.unit
                width: ListView.view.width
                height: 34
                color: isSelected ? theme.colors.selection : rowHover.hovered ? Qt.alpha(theme.colors.lighterBackground, 0.7) : "transparent"
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
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: row.modelData.failed ? theme.colors.red : row.modelData.running ? theme.colors.green : theme.colors.border
                    }
                    Label { Layout.fillWidth: page.width < 720; Layout.preferredWidth: 240; text: row.modelData.name; elide: Text.ElideRight; font.pixelSize: 13; color: theme.colors.brightForeground }
                    Label { visible: page.width >= 720; Layout.fillWidth: true; text: row.modelData.description; elide: Text.ElideRight; font.pixelSize: 12; color: theme.colors.lightForeground }
                    Label {
                        Layout.preferredWidth: 130
                        text: page.stateText(row.modelData)
                        elide: Text.ElideRight
                        font.pixelSize: 12
                        color: row.modelData.failed ? theme.colors.red : row.modelData.running ? theme.colors.green : theme.colors.mutedForeground
                    }
                    Label { visible: page.width >= 620; Layout.preferredWidth: 150; text: page.enabledText(row.modelData.enabled); elide: Text.ElideRight; font.pixelSize: 12; color: theme.colors.mutedForeground }
                }
            }
        }

        // Actions for the selected service.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            visible: page.selected !== null
            color: theme.colors.darkBackground
            Rectangle { width: parent.width; height: 1; color: theme.colors.border }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 8
                Label {
                    Layout.fillWidth: true
                    text: page.selected ? page.selected.unit : ""
                    elide: Text.ElideRight
                    font.family: win.mono
                    font.pixelSize: 12
                    color: theme.colors.lightForeground
                }
                Button { text: qsTr("Start"); enabled: page.selected && !page.selected.running; focusPolicy: Qt.NoFocus; onClicked: page.act("start") }
                Button { text: qsTr("Stop"); enabled: page.selected && page.selected.running; focusPolicy: Qt.NoFocus; onClicked: page.act("stop") }
                Button { text: qsTr("Restart"); enabled: page.selected !== null; focusPolicy: Qt.NoFocus; onClicked: page.act("restart") }
                Button {
                    visible: page.selected && (page.selected.enabled === "enabled" || page.selected.enabled === "disabled")
                    text: page.selected && page.selected.enabled === "enabled" ? qsTr("Disable autostart") : qsTr("Enable autostart")
                    flat: true
                    focusPolicy: Qt.NoFocus
                    onClicked: page.act(page.selected.enabled === "enabled" ? "disable" : "enable")
                }
            }
        }
    }

    Menu {
        id: menu
        Material.roundedScale: theme.radius
        MenuItem { text: qsTr("Start"); enabled: page.selected && !page.selected.running; onTriggered: page.act("start") }
        MenuItem { text: qsTr("Stop"); enabled: page.selected && page.selected.running; onTriggered: page.act("stop") }
        MenuItem { text: qsTr("Restart"); onTriggered: page.act("restart") }
        MenuSeparator {}
        MenuItem { text: qsTr("Enable autostart"); enabled: page.selected && page.selected.enabled === "disabled"; onTriggered: page.act("enable") }
        MenuItem { text: qsTr("Disable autostart"); enabled: page.selected && page.selected.enabled === "enabled"; onTriggered: page.act("disable") }
    }
}
