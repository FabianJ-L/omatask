import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A sortable column title in small caps; the sorted one gets the accent.
Item {
    id: cell
    property string title
    property string column
    property bool alignRight: true
    readonly property bool sorted: column.length > 0 && processes.sortColumn === column
    Layout.fillHeight: true

    Label {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: cell.alignRight ? ui.m : 0
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: cell.alignRight ? Text.AlignRight : Text.AlignLeft
        text: cell.title.toUpperCase() + (cell.sorted ? (processes.descending ? " ↓" : " ↑") : "")
        elide: Text.ElideRight
        font.pixelSize: ui.caption
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
        color: cell.sorted ? theme.accent : hover.hovered ? theme.colors.foreground : theme.colors.mutedForeground
    }
    HoverHandler { id: hover; enabled: cell.column.length > 0; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        enabled: cell.column.length > 0
        onTapped: {
            if (cell.sorted) processes.descending = !processes.descending
            else processes.sortColumn = cell.column
        }
    }
}
