import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// A context-menu row at the app's density instead of Material's 48 px.
MenuItem {
    implicitHeight: 34
    font.pixelSize: 13
    Material.roundedScale: theme.radius
}
