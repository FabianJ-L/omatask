import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Label over value pairs, flowing into as many columns as fit.
Flow {
    id: flow
    property var stats: []
    spacing: 22
    // Indexed by count, so values update in place instead of every row
    // being recreated (and flickering) on each sample.
    Repeater {
        model: flow.stats.length
        delegate: ColumnLayout {
            required property int index
            readonly property var modelData: flow.stats[index] || ["", ""]
            width: Math.max(150, valueLabel.implicitWidth)
            spacing: 1
            Label {
                text: modelData[0]
                font.pixelSize: 12
                color: theme.colors.mutedForeground
                elide: Text.ElideRight
                Layout.maximumWidth: 260
            }
            Label {
                id: valueLabel
                text: modelData[1]
                font.pixelSize: 15
                color: theme.colors.brightForeground
            }
        }
    }
}
