import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A number in the process table, tinted by how busy it is.
Rectangle {
    property alias text: label.text
    property color tint: "transparent"
    Layout.fillHeight: true
    color: tint
    Label {
        id: label
        anchors.fill: parent
        anchors.rightMargin: 10
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        font.family: win.mono
        font.pixelSize: 12
        color: theme.colors.foreground
    }
}
