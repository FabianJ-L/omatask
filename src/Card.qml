import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A rounded panel on the canvas. With a title it gets a heading row (and an
// optional actions slot on the right); flush drops the inner padding so a
// list can run edge to edge.
Rectangle {
    id: card
    property string title
    property string subtitle
    property bool flush: false
    default property alias content: body.data
    property alias actions: actionRow.data
    readonly property int pad: flush ? 0 : ui.l
    implicitHeight: column.implicitHeight + pad * 2
    radius: ui.rLarge
    color: ui.card

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: card.pad
        spacing: ui.m
        RowLayout {
            visible: card.title.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: card.flush ? ui.l : 0
            Layout.rightMargin: card.flush ? ui.l : 0
            Layout.topMargin: card.flush ? ui.m : 0
            spacing: ui.s
            Label {
                text: card.title
                font.pixelSize: ui.title
                font.weight: Font.DemiBold
                color: theme.colors.brightForeground
            }
            Label {
                visible: card.subtitle.length > 0
                Layout.fillWidth: true
                text: card.subtitle
                elide: Text.ElideRight
                font.pixelSize: ui.small
                color: theme.colors.mutedForeground
            }
            Item { visible: card.subtitle.length === 0; Layout.fillWidth: true }
            RowLayout { id: actionRow; spacing: ui.s }
        }
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            // The tallest child's own height, so cards inside a scroll view
            // know how much room they need even when the child fills them.
            implicitHeight: {
                let h = 0
                for (let i = 0; i < children.length; ++i) h = Math.max(h, children[i].implicitHeight)
                return h
            }
        }
    }
}
