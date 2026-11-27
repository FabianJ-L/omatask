import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A sortable column title; numeric columns show the machine-wide total above.
Item {
    id: cell
    property string title
    property string column
    property bool alignRight: true
    property double total: -1
    readonly property bool sorted: column.length > 0 && processes.sortColumn === column
    Layout.fillHeight: true

    ColumnLayout {
        anchors.fill: parent
        anchors.rightMargin: cell.alignRight ? 10 : 0
        spacing: 0
        Item { Layout.fillHeight: true }
        Label {
            Layout.fillWidth: true
            visible: cell.total >= 0
            horizontalAlignment: cell.alignRight ? Text.AlignRight : Text.AlignLeft
            text: Math.round(cell.total).toLocaleString(Qt.locale(translator.language), 'f', 0) + " %"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: win.loadColor(cell.total)
        }
        Label {
            Layout.fillWidth: true
            horizontalAlignment: cell.alignRight ? Text.AlignRight : Text.AlignLeft
            text: cell.title + (cell.sorted ? (processes.descending ? "  ▾" : "  ▴") : "")
            elide: Text.ElideRight
            font.pixelSize: 12
            color: cell.sorted ? theme.colors.brightForeground : theme.colors.lightForeground
        }
        Item { Layout.preferredHeight: 6 }
    }
    HoverHandler { enabled: cell.column.length > 0; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        enabled: cell.column.length > 0
        onTapped: {
            if (cell.sorted) processes.descending = !processes.descending
            else processes.sortColumn = cell.column
        }
    }
}
