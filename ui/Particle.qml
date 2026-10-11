import QtQuick

// One tool call in flight along a quadratic curve from the core to a file, with
// a short trail. Outbound particles leave the core; returning ones head back.
// Hidden particles stay in the pool with their clock frozen, so they cost nothing per frame.
Item {
    id: root
    required property real startX
    required property real startY
    required property real endX
    required property real endY
    required property real bend
    required property real speed
    required property real phase
    required property bool returning
    required property color ink
    required property real time
    readonly property real controlX: (startX + endX) / 2 - (endY - startY) / Math.max(1, length) * bend
    readonly property real controlY: (startY + endY) / 2 + (endX - startX) / Math.max(1, length) * bend
    readonly property real length: Math.hypot(endX - startX, endY - startY)
    readonly property real cycle: (phase + time * speed) % 1
    readonly property real head: returning ? 1 - cycle : cycle
    Repeater {
        model: 4
        Rectangle {
            id: dot
            required property int index
            readonly property real progress: root.returning ? root.head + index * 0.05 : root.head - index * 0.05
            readonly property real size: 5.2 * (1 - index * 0.2)
            visible: progress >= 0 && progress <= 1
            width: size; height: size; radius: size / 2
            color: root.ink
            opacity: 0.85 * (1 - index / 4)
            // The quadratic Bézier, evaluated directly: cheaper than a PathInterpolator per dot.
            x: (1 - progress) * ((1 - progress) * root.startX + 2 * progress * root.controlX) + progress * progress * root.endX - size / 2
            y: (1 - progress) * ((1 - progress) * root.startY + 2 * progress * root.controlY) + progress * progress * root.endY - size / 2
        }
    }
}
