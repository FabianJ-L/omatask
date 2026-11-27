import QtQuick

// A minute of history as a filled line, newest on the right. A second series
// (network send, say) draws as a dashed line on top.
Canvas {
    id: graph
    property var values: []
    property var values2: []
    property double scale: 100
    property color color: theme.accent
    property color color2: theme.colors.cyan
    property bool grid: true
    property bool framed: true

    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function series(ctx, data, stroke, fill, dashed) {
        if (!data || data.length < 2) return
        const n = data.length
        const step = width / (n - 1)
        const s = Math.max(scale, 0.0001)
        ctx.beginPath()
        for (let i = 0; i < n; ++i) {
            const x = i * step
            const y = height - Math.min(1, Math.max(0, data[i] / s)) * (height - 2) - 1
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
        }
        ctx.setLineDash(dashed ? [4, 3] : [])
        ctx.lineWidth = 1.5
        ctx.strokeStyle = stroke
        ctx.stroke()
        if (fill) {
            ctx.lineTo(width, height)
            ctx.lineTo(0, height)
            ctx.closePath()
            ctx.fillStyle = Qt.alpha(stroke, 0.16)
            ctx.fill()
        }
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        if (grid) {
            ctx.strokeStyle = Qt.alpha(theme.colors.border, 0.6)
            ctx.lineWidth = 1
            ctx.setLineDash([])
            for (let i = 1; i < 4; ++i) {
                const y = Math.round(height * i / 4) + 0.5
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
            }
            for (let i = 1; i < 10; ++i) {
                const x = Math.round(width * i / 10) + 0.5
                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
            }
        }
        series(ctx, values, color, true, false)
        series(ctx, values2, color2, false, true)
        if (framed) {
            ctx.setLineDash([])
            ctx.strokeStyle = Qt.alpha(color, 0.55)
            ctx.lineWidth = 1
            ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
        }
    }
}
