import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A page's title on the left and its controls on the right, straight on the
// canvas. The title gives way (and elides) before the controls get squeezed.
Item {
    id: header
    property string title
    property string subtitle
    default property alias controls: tools.data
    implicitHeight: 72

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: ui.xl
        anchors.rightMargin: ui.xl
        anchors.topMargin: ui.s
        spacing: ui.l
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: header.title
                font.pixelSize: ui.h2
                font.weight: Font.DemiBold
                color: theme.colors.brightForeground
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: header.subtitle.length > 0
                text: header.subtitle
                font.pixelSize: ui.small
                color: theme.colors.mutedForeground
            }
        }
        RowLayout {
            id: tools
            spacing: ui.s
        }
    }
}
