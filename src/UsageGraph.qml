import QtQuick
import QtQuick.Window

// A minute of history as a filled line, newest on the right. A second series
// (network send, say) draws as a dashed line on top.
//
// With scrolling on, the line glides left over one sample interval instead
// of jumping a step. The line is painted once per sample, one step wider
// than the view, and then only moved: moving a finished texture costs the
// GPU next to nothing, where repainting the canvas every frame kept a CPU
// core busy.
Item {
    id: graph
    property var values: []
    property var values2: []
    property double scale: 100
    property color color: theme.accent
    property color color2: theme.colors.cyan
    property bool grid: true
    property bool framed: true
    property bool scrolling: false

    readonly property int count: Math.max(values ? values.length : 0, 3)
    readonly property real step: width / (count - 2)

    clip: true

    onValuesChanged: {
        lines.requestPaint()
        if (scrolling && visible) {
            lines.offset = 0
            glide.start()
        }
    }
    onValues2Changed: lines.requestPaint()
    onColorChanged: { lines.requestPaint(); backdrop.requestPaint() }
    onWidthChanged: { lines.requestPaint(); backdrop.requestPaint() }
    onHeightChanged: { lines.requestPaint(); backdrop.requestPaint() }

    // Grid and frame: painted only when the size or colors change.
    Canvas {
        id: backdrop
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (graph.grid) {
                ctx.strokeStyle = Qt.alpha(theme.colors.border, 0.6)
                ctx.lineWidth = 1
                for (let i = 1; i < 4; ++i) {
                    const y = Math.round(height * i / 4) + 0.5
                    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                }
                for (let i = 1; i < 10; ++i) {
                    const x = Math.round(width * i / 10) + 0.5
                    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
                }
            }
        }
    }

    // The data, one step wider than the view; x slides from 0 to -step.
    Canvas {
        id: lines
        width: graph.width + graph.step
        height: graph.height
        // offset 0 shows the previous sample's view (points 0..n-2); 1 the
        // current one (1..n-1), one step further left.
        x: -graph.step * (graph.scrolling ? offset : 1)
        property real offset: 1
        // The line moves only step pixels per sample, so a frame per device
        // pixel looks as smooth as 60 fps at a fraction of the redraws.
        Timer {
            id: glide
            readonly property real pixels: Math.max(1, graph.step * Screen.devicePixelRatio)
            interval: Math.max(33, monitor.interval / pixels)
            repeat: true
            onTriggered: {
                lines.offset = Math.min(1, lines.offset + interval / monitor.interval)
                if (lines.offset >= 1)
                    stop()
            }
        }

        function series(ctx, data, stroke, fill, dashed) {
            if (!data || data.length < 2) return
            const n = data.length
            const s = Math.max(graph.scale, 0.0001)
            ctx.beginPath()
            for (let i = 0; i < n; ++i) {
                const x = i * graph.step
                const y = height - Math.min(1, Math.max(0, data[i] / s)) * (height - 2) - 1
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.setLineDash(dashed ? [4, 3] : [])
            ctx.lineWidth = 1.5
            ctx.strokeStyle = stroke
            ctx.stroke()
            if (fill) {
                ctx.lineTo((n - 1) * graph.step, height)
                ctx.lineTo(0, height)
                ctx.closePath()
                ctx.fillStyle = Qt.alpha(stroke, 0.16)
                ctx.fill()
            }
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            series(ctx, graph.values, graph.color, true, false)
            series(ctx, graph.values2, graph.color2, false, true)
        }
    }

    Rectangle {
        visible: graph.framed
        anchors.fill: parent
        color: "transparent"
        border.color: Qt.alpha(graph.color, 0.55)
    }
}
