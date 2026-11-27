import QtQuick
import QtQuick.Controls

// How often the machine is sampled: every 1, 2 or 5 seconds.
Segmented {
    id: picker
    small: true
    readonly property var values: [1000, 2000, 5000]
    options: ["1 s", "2 s", "5 s"]
    current: values.indexOf(monitor.interval)
    onPicked: index => monitor.interval = values[index]
    ToolTip.visible: hover.hovered
    ToolTip.text: qsTr("Update speed")
    ToolTip.delay: 500
    HoverHandler { id: hover }
}
