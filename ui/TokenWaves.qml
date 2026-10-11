pragma ComponentBehavior: Bound
import QtQuick
import "../Model.js" as Model

// One glowing wave per agent whose height follows its output tokens per minute.
// Each wave is drawn once per snapshot as a periodic strip; motion only slides
// the strip along, so animating it costs a translation per frame.
Item {
    id: root
    required property var entries
    required property var colors
    // Drawn as on a light background; on the desktop this follows the wallpaper.
    property bool light: colors.light
    property real time: 0
    property real scale: 1
    property string fontFamily: ""
    readonly property real period: 360
    readonly property int peak: Math.max(1500, Math.max.apply(null, entries.map(function(e) { return e.agent.tokensPerMinute; }).concat([0])))
    visible: entries.length > 0
    Theme { id: theme }
    Text {
        id: caption
        text: "TOKENS / MIN · " + Model.tokens(root.entries.reduce(function(sum, e) { return sum + e.agent.tokensPerMinute; }, 0))
        textFormat: Text.PlainText
        color: root.light === root.colors.light ? theme.text : theme.background
        opacity: 0.4
        font.family: root.fontFamily
        font.pixelSize: Math.round(10 * root.scale)
        font.letterSpacing: 1
    }
    Item {
        id: band
        anchors { left: parent.left; right: parent.right; top: caption.bottom; bottom: parent.bottom; topMargin: 4 }
        clip: true
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: theme.text; opacity: 0.08 }
        Repeater {
            model: root.entries.length
            Canvas {
                id: wave
                required property int index
                readonly property var entry: root.entries[index]
                readonly property var agent: entry ? entry.agent : null
                readonly property real amplitude: !agent ? 0 : agent.status === "waiting" ? 0.04 : agent.status === "idle" ? 0.06
                    : Math.max(0.15, agent.tokensPerMinute / root.peak)
                readonly property color ink: entry ? entry.color : "transparent"
                readonly property real speed: 26 + index * 9
                width: band.width + root.period
                height: band.height
                // Slide by whole periods' remainder so the strip loops seamlessly.
                x: -((root.time * speed + index * 61) % root.period)
                renderStrategy: Canvas.Cooperative
                readonly property string paintKey: amplitude.toFixed(2) + String(ink) + width + "x" + height + root.light
                onPaintKeyChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d");
                    c.reset();
                    if (!agent) return;
                    var css = function(a) { return "rgba(" + Math.round(ink.r * 255) + "," + Math.round(ink.g * 255) + "," + Math.round(ink.b * 255) + "," + a + ")"; };
                    var base = height - 2, amp = (height - 6) * amplitude / 1.4, phase = index * 1.7;
                    c.globalCompositeOperation = root.light ? "source-over" : "lighter";
                    c.beginPath();
                    for (var px = 0; px <= width; px += 3) {
                        // Integer harmonics of the period keep the strip periodic.
                        var u = px / root.period * Math.PI * 2;
                        var y = base - Math.abs(Math.sin(u) * Math.sin(u * 2 + phase) + 0.4 * Math.sin(u * 5 + phase * 2)) * amp;
                        if (px === 0) c.moveTo(px, y); else c.lineTo(px, y);
                    }
                    c.lineJoin = "round";
                    c.strokeStyle = css(0.18); c.lineWidth = 5; c.stroke();
                    c.strokeStyle = css(0.85); c.lineWidth = 1.6; c.stroke();
                }
            }
        }
    }
}
