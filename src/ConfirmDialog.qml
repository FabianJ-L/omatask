import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A second look before something that cannot be undone. Built on a plain
// Popup so it shares the app's buttons, corners and colors.
Popup {
    id: dialog
    property string title
    property string message
    property string acceptText: qsTr("OK")
    signal accepted()

    function accept() { close(); accepted() }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(460, parent ? parent.width - 48 : 460)
    modal: true
    focus: true
    padding: ui.xl
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        radius: ui.rLarge
        color: ui.cardSolid
        border.color: theme.colors.border
    }
    Overlay.modal: Rectangle { color: Qt.alpha(theme.colors.darkerBackground, 0.6) }

    contentItem: ColumnLayout {
        spacing: ui.m
        Label {
            Layout.fillWidth: true
            text: dialog.title
            wrapMode: Text.Wrap
            font.pixelSize: ui.title + 1
            font.weight: Font.DemiBold
            color: theme.colors.brightForeground
        }
        Label {
            Layout.fillWidth: true
            text: dialog.message
            wrapMode: Text.Wrap
            font.pixelSize: ui.body
            color: theme.colors.foreground
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 8
            Item { Layout.fillWidth: true }
            ActionButton { kind: "ghost"; text: qsTr("Cancel"); onClicked: dialog.close() }
            ActionButton { kind: "danger"; icon: "󰅖"; text: dialog.acceptText; onClicked: dialog.accept() }
        }
    }

    // Enter confirms; Esc cancels through the close policy.
    Shortcut { sequences: ["Return", "Enter"]; enabled: dialog.visible; onActivated: dialog.accept() }
}
