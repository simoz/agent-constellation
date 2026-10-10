import QtQuick

// Tool calls per 10-second bucket over the last five minutes.
Canvas {
    id: root
    property var values: []
    property color ink: "white"
    implicitHeight: 28
    onValuesChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    function css(a) { return "rgba(" + Math.round(ink.r * 255) + "," + Math.round(ink.g * 255) + "," + Math.round(ink.b * 255) + "," + a + ")"; }
    onPaint: {
        var c = getContext("2d"), n = values.length;
        c.reset();
        if (n < 2) return;
        var top = Math.max(4, Math.max.apply(null, values)), stepX = width / (n - 1);
        c.beginPath();
        for (var i = 0; i < n; i++) {
            var y = height - 1 - values[i] / top * (height - 4);
            if (i === 0) c.moveTo(0, y); else c.lineTo(i * stepX, y);
        }
        c.strokeStyle = css(0.9); c.lineWidth = 1.5; c.stroke();
        c.lineTo(width, height); c.lineTo(0, height); c.closePath();
        c.fillStyle = css(0.14); c.fill();
    }
}
