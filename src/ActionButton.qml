import QtQuick
import QtQuick.Controls

// The one button of the app: every button shares its height, corner radius,
// icon size and padding, so toolbars line up with the search field and the
// segmented controls next to them.
//   kind: "normal" (outlined), "primary" (accent), "danger" (red), "ghost" (no frame)
Rectangle {
    id: button
    property string text
    property string icon
    property string kind: "normal"
    property string tip
    property bool small: false
    signal clicked()

    readonly property color tone: kind === "primary" ? theme.accent : kind === "danger" ? theme.colors.red : theme.colors.foreground
    implicitHeight: small ? 28 : 36
    implicitWidth: text.length ? row.implicitWidth + (small ? 20 : 28) : implicitHeight
    radius: Math.min(6, theme.radius)
    opacity: enabled ? 1 : 0.4
    border.width: kind === "normal" ? 1 : 0
    border.color: theme.colors.border
    color: {
        if (kind === "primary") return mouse.pressed ? Qt.darker(theme.accent, 1.15) : hover.hovered ? Qt.lighter(theme.accent, 1.08) : theme.accent
        if (kind === "danger") return Qt.alpha(theme.colors.red, mouse.pressed ? 0.34 : hover.hovered ? 0.26 : 0.16)
        if (kind === "ghost") return hover.hovered ? theme.colors.lighterBackground : "transparent"
        return mouse.pressed ? theme.colors.selection : hover.hovered ? theme.colors.lighterBackground : theme.colors.darkBackground
    }
    Behavior on color { ColorAnimation { duration: 90 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Label {
            visible: button.icon.length > 0
            width: 14
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: button.icon
            font.family: win.iconFont
            font.pixelSize: button.small ? 11 : 13
            color: button.kind === "primary" ? theme.accentForeground : button.tone
        }
        Label {
            visible: button.text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            font.pixelSize: button.small ? 12 : 13
            font.weight: Font.Medium
            color: button.kind === "primary" ? theme.accentForeground : button.tone
        }
    }

    HoverHandler { id: hover; cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: button.enabled
        onClicked: button.clicked()
    }
    ToolTip.visible: tip.length > 0 && hover.hovered
    ToolTip.text: tip
    ToolTip.delay: 400
}
