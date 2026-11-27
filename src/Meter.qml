import QtQuick

// A thin rounded bar for a fraction. It snaps to each new sample: a bar that
// animates on every update looks restless (see issue #1).
Rectangle {
    id: meter
    property real value: 0          // 0 … 1
    property color tone: theme.accent
    implicitHeight: 4
    radius: height / 2
    color: Qt.alpha(theme.colors.foreground, 0.08)
    Rectangle {
        width: Math.round(parent.width * Math.max(0, Math.min(1, meter.value)))
        height: parent.height
        radius: parent.radius
        color: meter.tone
    }
}
