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
        // The title gives way (and elides) before the controls get squeezed.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: header.title
                font.pixelSize: 20
                font.weight: Font.DemiBold
                color: theme.colors.brightForeground
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: header.subtitle.length > 0
                text: header.subtitle
                font.pixelSize: 12
                color: theme.colors.mutedForeground
            }
        }
        RowLayout {
            id: tools
            spacing: 12
        }
    }
}
