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
        anchors.leftMargin: 20
        anchors.rightMargin: 12
        spacing: 12
        Label {
            text: ""
            font.family: win.iconFont
            color: theme.colors.red
        }
        Label {
            Layout.fillWidth: true
            text: banner.text
            wrapMode: Text.Wrap
            font.pixelSize: 13
            color: theme.colors.brightForeground
        }
        Button {
            text: qsTr("Dismiss")
            flat: true
            focusPolicy: Qt.NoFocus
            onClicked: banner.dismissed()
        }
    }
}
