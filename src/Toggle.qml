import QtQuick
import QtQuick.Controls

// A compact on/off switch with an optional label, sized to sit in a 36 px row.
Item {
    id: toggle
    property bool checked: false
    property string text
    signal toggled()
    implicitHeight: 36
    implicitWidth: track.width + (label.visible ? label.implicitWidth + 10 : 0)
    opacity: enabled ? 1 : 0.4

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: 20
        radius: 10
        color: toggle.checked ? theme.accent : theme.colors.darkBackground
        border.width: toggle.checked ? 0 : 1
        border.color: theme.colors.border
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 14
            height: 14
            radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: toggle.checked ? parent.width - width - 3 : 3
            color: toggle.checked ? theme.accentForeground : theme.colors.lightForeground
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    Label {
        id: label
        visible: toggle.text.length > 0
        anchors.left: track.right
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: toggle.text
        font.pixelSize: 13
        color: theme.colors.foreground
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler {
        onTapped: {
            toggle.checked = !toggle.checked
            toggle.toggled()
        }
    }
}
