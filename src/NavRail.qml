import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A slim column of icons down the left edge: the pages on top, pause and
// help at the bottom. Titles and shortcuts show as tooltips.
Rectangle {
    id: rail
    color: ui.rail
    property var model: []
    property int currentIndex: 0
    implicitWidth: 60

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: theme.colors.border
    }

    component RailButton: Rectangle {
        id: button
        property string icon
        property string tip
        property bool active: false
        property color tone: active ? theme.accent : theme.colors.lightForeground
        signal clicked()
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 40
        implicitHeight: 40
        radius: ui.rMed
        color: active ? Qt.alpha(theme.accent, 0.16) : hover.hovered ? ui.raised : "transparent"
        Label {
            anchors.centerIn: parent
            text: button.icon
            font.family: win.iconFont
            font.pixelSize: 18
            color: hover.hovered && !button.active ? theme.colors.brightForeground : button.tone
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: button.clicked() }
        ToolTip.visible: hover.hovered
        ToolTip.text: tip
        ToolTip.delay: 300
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: ui.m
        anchors.bottomMargin: ui.m
        anchors.rightMargin: 1
        spacing: ui.xs

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: ui.m
            implicitWidth: 34
            implicitHeight: 34
            radius: ui.rMed
            color: theme.accent
            Label {
                anchors.centerIn: parent
                text: "\u{F0430}"
                font.family: win.iconFont
                font.pixelSize: 18
                color: theme.accentForeground
            }
        }

        Repeater {
            model: rail.model
            delegate: RailButton {
                required property int index
                required property var modelData
                icon: modelData.icon
                tip: modelData.title + "   " + (index + 1)
                active: rail.currentIndex === index
                onClicked: rail.currentIndex = index
            }
        }

        Item { Layout.fillHeight: true }

        RailButton {
            icon: monitor.paused ? "\u{F040A}" : "\u{F03E4}"
            tip: (monitor.paused ? qsTr("Resume updates") : qsTr("Pause updates")) + "   Space"
            tone: monitor.paused ? theme.colors.yellow : theme.colors.lightForeground
            onClicked: monitor.paused = !monitor.paused
        }
        RailButton {
            icon: "\u{F0625}"
            tip: qsTr("Keyboard shortcuts") + "   ?"
            active: win.helpVisible
            onClicked: win.helpVisible = !win.helpVisible
        }
    }
}
