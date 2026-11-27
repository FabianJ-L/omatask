import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A row of mutually exclusive choices.
Rectangle {
    id: seg
    property var options: []
    property int current: 0
    property bool small: false
    signal picked(int index)
    implicitHeight: small ? 28 : 36
    implicitWidth: row.implicitWidth + 6
    radius: Math.min(6, theme.radius)
    color: theme.colors.darkBackground
    border.color: theme.colors.border

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 3
        spacing: 2
        Repeater {
            model: seg.options
            delegate: Rectangle {
                required property int index
                required property string modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitWidth: label.implicitWidth + (seg.small ? 14 : 24)
                radius: Math.min(4, theme.radius)
                color: seg.current === index ? theme.accent : hover.hovered ? theme.colors.lighterBackground : "transparent"
                Label {
                    id: label
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: seg.small ? 11 : 13
                    color: seg.current === index ? theme.accentForeground : theme.colors.foreground
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: seg.picked(index) }
            }
        }
    }
}
