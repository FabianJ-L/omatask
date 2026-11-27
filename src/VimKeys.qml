import QtQuick

// Vim-style movement for a page: j k h l, gg and G, Ctrl+d and Ctrl+u.
// A page calls handle(event) first in its Keys.onPressed and gives the
// callbacks it supports; unknown or unsupported keys fall through.
QtObject {
    id: vim
    property var down: null
    property var up: null
    property var left: null
    property var right: null
    property var top: null
    property var bottom: null
    property var halfDown: null
    property var halfUp: null

    // The first g of gg waits this long for the second.
    property bool pendingG: false
    readonly property Timer gTimer: Timer { interval: 600; onTriggered: vim.pendingG = false }

    function call(fn) {
        if (!fn) return false
        fn()
        return true
    }

    function handle(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
        if (mods === Qt.ControlModifier) {
            if (event.key === Qt.Key_D) return call(halfDown)
            if (event.key === Qt.Key_U) return call(halfUp)
            return false
        }
        if (mods !== 0) return false
        switch (event.text) {
        case "j": return call(down)
        case "k": return call(up)
        case "h": return call(left)
        case "l": return call(right)
        case "G": pendingG = false; return call(bottom)
        case "g":
            if (!top) return false
            if (pendingG) { pendingG = false; gTimer.stop(); return call(top) }
            pendingG = true
            gTimer.restart()
            return true
        }
        pendingG = false
        return false
    }
}
