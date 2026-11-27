import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// A second look before something that cannot be undone.
Dialog {
    id: dialog
    property string message
    property string acceptText: qsTr("OK")
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(460, parent ? parent.width - 48 : 460)
    modal: true
    Material.roundedScale: theme.radius
    Material.background: theme.colors.lighterBackground

    contentItem: Label {
        width: dialog.availableWidth
        text: dialog.message
        wrapMode: Text.Wrap
        color: theme.colors.foreground
        font.pixelSize: 13
    }
    footer: DialogButtonBox {
        Material.background: "transparent"
        Button {
            text: qsTr("Cancel")
            flat: true
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            text: dialog.acceptText
            highlighted: true
            Material.accent: theme.colors.red
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }
    onOpened: footer.forceActiveFocus()
}
