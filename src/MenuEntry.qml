import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// A context-menu row at the app's density instead of Material's 48 px.
MenuItem {
    implicitHeight: ui.row
    font.pixelSize: ui.body
    Material.roundedScale: theme.radius
}
