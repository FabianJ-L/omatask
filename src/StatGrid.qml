import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Label over value pairs, flowing into as many columns as fit.
Flow {
    id: flow
    property var stats: []
    spacing: 22
    Repeater {
        model: flow.stats
        delegate: ColumnLayout {
            required property var modelData
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
