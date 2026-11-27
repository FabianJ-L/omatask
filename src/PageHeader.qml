import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A page's title on the left and its controls on the right.
Item {
    id: header
    property string title
    property string subtitle
    default property alias controls: tools.data
    implicitHeight: 68

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 14
        ColumnLayout {
            spacing: 0
            Label {
                text: header.title
                font.pixelSize: 20
                font.weight: Font.DemiBold
                color: theme.colors.brightForeground
            }
            Label {
                visible: header.subtitle.length > 0
                text: header.subtitle
                font.pixelSize: 12
                color: theme.colors.mutedForeground
            }
        }
        Item { Layout.fillWidth: true }
        RowLayout {
            id: tools
            spacing: 12
        }
    }
}
