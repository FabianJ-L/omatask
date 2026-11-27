import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Says what went wrong (permission denied, a missing tool) in the window.
Rectangle {
    id: banner
    property string text
    signal dismissed()
    visible: text.length > 0
    implicitHeight: visible ? row.implicitHeight + 20 : 0
    color: Qt.alpha(theme.colors.red, 0.18)
    Rectangle { width: parent.width; height: 1; color: theme.colors.red }
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: ui.xl
        anchors.rightMargin: ui.m
        spacing: 12
        Label {
            text: "󰗖"
            font.family: win.iconFont
            color: theme.colors.red
        }
        Label {
            Layout.fillWidth: true
            text: banner.text
            wrapMode: Text.Wrap
            font.pixelSize: ui.body
            color: theme.colors.brightForeground
        }
        ActionButton {
            kind: "ghost"
            small: true
            icon: "\u{F0156}"
            text: qsTr("Dismiss")
            onClicked: banner.dismissed()
        }
    }
}
