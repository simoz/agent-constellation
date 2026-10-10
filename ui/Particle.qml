import QtQuick

// One tool call in flight along a quadratic curve from the core to a file, with
// a short trail. Outbound particles leave the core; returning ones head back.
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
        model: 6
        Rectangle {
            id: dot
            required property int index
            readonly property real progress: root.returning ? root.head + index * 0.03 : root.head - index * 0.03
            readonly property real size: 5.2 * (1 - index / 8)
            visible: progress >= 0 && progress <= 1
            width: size; height: size; radius: size / 2
            color: root.ink
            opacity: 0.85 * (1 - index / 6)
            x: path.x - size / 2
            y: path.y - size / 2
            PathInterpolator {
                id: path
                progress: Math.max(0, Math.min(1, dot.progress))
                path: Path {
                    startX: root.startX; startY: root.startY
                    PathQuad { x: root.endX; y: root.endY; controlX: root.controlX; controlY: root.controlY }
                }
            }
        }
    }
}
