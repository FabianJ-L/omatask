import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A number in the process table with a hairline meter under it that shows
// how much of the machine it takes. Only heavy users get one; the rest of
// the table stays quiet.
Item {
    id: cell
    property alias text: label.text
    property real fraction: 0
    Layout.fillHeight: true
    Label {
        id: label
        anchors.right: parent.right
        anchors.rightMargin: ui.m
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -1
        horizontalAlignment: Text.AlignRight
        font.family: win.mono
        font.pixelSize: ui.small
        color: cell.fraction >= 0.1 ? theme.colors.brightForeground : theme.colors.lightForeground
    }
    Meter {
        visible: cell.fraction >= 0.1
        anchors.right: label.right
        anchors.top: label.bottom
        anchors.topMargin: 2
        width: 36
        height: 2
        value: cell.fraction
        tone: win.loadColor(cell.fraction * 100)
    }
}
