import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A titled panel.
Rectangle {
    id: card
    property string title
    default property alias content: body.data
    implicitHeight: column.implicitHeight + 36
    radius: Math.min(8, theme.radius)
    color: theme.colors.darkBackground
    border.color: theme.colors.border

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14
        Label {
            text: card.title
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: theme.colors.brightForeground
        }
        Item {
            id: body
            Layout.fillWidth: true
            implicitHeight: childrenRect.height
        }
    }
}
