import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1180
    height: 760
    minimumWidth: 860
    minimumHeight: 520
    visible: true
    title: "OmaTask"
    color: theme.colors.background

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.background: theme.colors.background
    Material.foreground: theme.colors.foreground
    Material.primary: theme.colors.lighterBackground
    Material.roundedScale: theme.radius

    readonly property string mono: "monospace"
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    property bool helpVisible: false
    // Tiled windows are often half a screen wide; the sidebar shrinks to icons then.
    readonly property bool compact: width < 1000
    property alias page: sidebar.currentIndex

    readonly property var pages: [
        { icon: "󰉹", title: qsTr("Processes") },
        { icon: "󰄪", title: qsTr("Performance") },
        { icon: "󰔏", title: qsTr("Sensors & battery") },
        { icon: "󱓟", title: qsTr("Startup") },
        { icon: "󰢻", title: qsTr("Services") }
    ]

    // Heavy work (the process scan, service lists) only runs for the page on screen.
    onPageChanged: {
        monitor.activePage = page
        if (page === 3) services.refreshStartup()
        if (page === 4) services.refresh()
        Qt.callLater(focusPage)
    }
    function focusPage() {
        const item = stack.children[page]
        if (item) item.forceActiveFocus()
    }
    Component.onCompleted: focusPage()

    // Colors for load: calm, busy, alarming.
    function loadColor(percent) {
        if (percent >= 85) return theme.colors.red
        if (percent >= 60) return theme.colors.yellow
        return theme.accent
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        SideBar {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: win.compact ? 64 : 220
            compact: win.compact
            model: win.pages
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            StackLayout {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.page
                ProcessesPage {}
                PerformancePage {}
                SensorsPage {}
                StartupPage {}
                ServicesPage {}
            }

            ErrorBanner {
                Layout.fillWidth: true
                text: processes.error.length ? processes.error : services.error
                onDismissed: { processes.clearError(); services.clearError() }
            }
        }
    }

    HelpOverlay {
        anchors.fill: parent
        visible: win.helpVisible
        onCloseRequested: win.helpVisible = false
    }

    Shortcut { sequence: "1"; context: Qt.ApplicationShortcut; enabled: !win.typing(); onActivated: win.page = 0 }
    Shortcut { sequence: "2"; context: Qt.ApplicationShortcut; enabled: !win.typing(); onActivated: win.page = 1 }
    Shortcut { sequence: "3"; context: Qt.ApplicationShortcut; enabled: !win.typing(); onActivated: win.page = 2 }
    Shortcut { sequence: "4"; context: Qt.ApplicationShortcut; enabled: !win.typing(); onActivated: win.page = 3 }
    Shortcut { sequence: "5"; context: Qt.ApplicationShortcut; enabled: !win.typing(); onActivated: win.page = 4 }
    Shortcut { sequence: "Ctrl+Tab"; context: Qt.ApplicationShortcut; onActivated: win.page = (win.page + 1) % 5 }
    Shortcut { sequence: "Ctrl+Shift+Tab"; context: Qt.ApplicationShortcut; onActivated: win.page = (win.page + 4) % 5 }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !win.typing(); onActivated: monitor.paused = !monitor.paused }
    Shortcut { sequences: ["?", "F1"]; context: Qt.ApplicationShortcut; enabled: !win.typing() || win.helpVisible; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; enabled: !win.typing(); onActivated: Qt.quit() }
    Shortcut { sequence: "Ctrl+Q"; context: Qt.ApplicationShortcut; onActivated: Qt.quit() }
    Shortcut { sequence: "F5"; context: Qt.ApplicationShortcut; onActivated: { monitor.sampleNow(); if (win.page === 3) services.refreshStartup(); if (win.page === 4) services.refresh() } }
    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (win.helpVisible) win.helpVisible = false
            else if (processes.error.length || services.error.length) { processes.clearError(); services.clearError() }
            else win.focusPage()
        }
    }

    // Single-key shortcuts must not fire while typing into a search field.
    function typing() {
        const item = win.activeFocusItem
        return item !== null && item.hasOwnProperty("cursorPosition") && !item.readOnly
    }
}
