import QtQuick
import QtQuick.Controls

// A compact search box: the Material field floats its label and is taller
// than the page headers want.
Item {
    id: field
    property alias text: input.text
    property string placeholderText
    signal accepted()
    implicitHeight: 36
    implicitWidth: 220

    // Drawn at a fixed height, whatever height the surrounding layout gives.
    Rectangle {
        id: frame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 36
        radius: Math.min(6, theme.radius)
        color: theme.colors.darkBackground
        border.color: input.activeFocus ? theme.accent : theme.colors.border
    }

    function forceActiveFocus() { input.forceActiveFocus(); input.selectAll() }

    Label {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        font.family: win.iconFont
        font.pixelSize: 12
        color: theme.colors.mutedForeground
    }
    TextInput {
        id: input
        anchors.left: icon.right
        anchors.leftMargin: 8
        anchors.right: clear.left
        anchors.verticalCenter: parent.verticalCenter
        color: theme.colors.brightForeground
        selectionColor: theme.colors.selection
        selectedTextColor: theme.colors.brightForeground
        font.pixelSize: 13
        clip: true
        Keys.forwardTo: [field]
        onAccepted: field.accepted()
    }
    Label {
        anchors.left: input.left
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text.length === 0
        text: field.placeholderText
        font.pixelSize: 13
        color: theme.colors.mutedForeground
    }
    Label {
        id: clear
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text.length > 0
        width: visible ? implicitWidth : 0
        text: ""
        font.family: win.iconFont
        font.pixelSize: 12
        color: theme.colors.lightForeground
        TapHandler { onTapped: input.text = "" }
    }
    TapHandler { onTapped: input.forceActiveFocus() }
}
