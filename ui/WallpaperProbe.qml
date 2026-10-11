import QtQuick

// A coarse luminance grid of the wallpaper under an area of the screen, for
// inks that stand out on the desktop. The full image is decoded only to sample
// it and released afterwards; nothing runs per frame.
Canvas {
    id: root
    // Local path of the wallpaper, shown cropped to fill the screen.
    property string source: ""
    property real screenWidth: 1
    property real screenHeight: 1
    // The sampled area, in screen pixels.
    property rect area: Qt.rect(0, 0, screenWidth, screenHeight)
    readonly property int columns: 32
    readonly property int rows: Math.max(1, Math.round(columns * area.height / Math.max(1, area.width)))
    // Row-major relative (linear) luminance, 0–1; empty until the wallpaper is sampled.
    property var values: []
    property string loaded: ""
    width: columns
    height: rows
    // Painted only to be read back: never shown.
    opacity: 0
    renderStrategy: Canvas.Cooperative

    function reload() {
        values = [];
        if (loaded) unloadImage(loaded);
        loaded = source ? "file://" + source : "";
        // A small decode gives the aspect ratio; the canvas draws the image itself.
        shape.source = loaded;
        requestPaint();
    }
    onSourceChanged: reload()
    onImageLoaded: requestPaint()
    onAreaChanged: requestPaint()
    onScreenWidthChanged: requestPaint()
    onScreenHeightChanged: requestPaint()

    Image {
        id: shape
        visible: false
        asynchronous: true
        cache: false
        sourceSize.width: 64
        onStatusChanged: if (status === Image.Ready) root.requestPaint()
    }
    onPaint: {
        var c = getContext("2d"), iw = shape.implicitWidth, ih = shape.implicitHeight;
        c.reset();
        if (!loaded || shape.status !== Image.Ready || iw <= 0 || ih <= 0) return;
        if (!isImageLoaded(loaded)) { loadImage(loaded); return; }
        // The wallpaper fills the screen with PreserveAspectCrop; the area maps onto the grid.
        var scale = Math.max(screenWidth / iw, screenHeight / ih), kx = columns / area.width, ky = rows / area.height;
        var ox = (screenWidth - iw * scale) / 2, oy = (screenHeight - ih * scale) / 2;
        c.drawImage(loaded, (ox - area.x) * kx, (oy - area.y) * ky, iw * scale * kx, ih * scale * ky);
        var data = c.getImageData(0, 0, columns, rows).data, list = [];
        var linear = function(v) { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
        for (var i = 0; i < columns * rows; i++)
            list.push(0.2126 * linear(data[i * 4]) + 0.7152 * linear(data[i * 4 + 1]) + 0.0722 * linear(data[i * 4 + 2]));
        values = list;
        unloadImage(loaded);
    }
}
