pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../Model.js" as Model

// Moving parts of one agent, all derived from the scene clock (`time`, seconds).
// A single timer sets the frame rate, so the window renders at most that often
// instead of on every vsync, and nothing rasterizes per frame.
Item {
    id: root
    required property var entry
    required property var colors
    required property real scale
    required property string fontFamily
    required property real time
    readonly property var agent: entry.agent
    readonly property color ink: entry.color
    readonly property bool busy: agent.status === "working" || agent.status === "thinking"
    readonly property bool waiting: agent.status === "waiting"
    x: entry.x
    y: entry.y

    // Particles: outbound in the agent color, returning results in cyan.
    readonly property int particleCount: {
        var recent = agent.activityBuckets.slice(-3).reduce(function(a, b) { return a + b; }, 0);
        return busy && entry.files.length ? Math.min(12, 3 + recent * 2) : 0;
    }
    Repeater {
        model: root.particleCount
        Particle {
            required property int index
            readonly property string key: root.agent.id + "#" + index
            readonly property var node: root.entry.files[Math.floor(Model.unit(key + "n") * Math.min(root.entry.files.length, 6))]
            x: -root.x; y: -root.y
            startX: root.entry.x; startY: root.entry.y
            endX: node.x; endY: node.y
            bend: (Model.unit(key + "c") - 0.5) * root.entry.radius * 0.6
            speed: (0.25 + Model.unit(key + "s") * 0.35) * (root.agent.status === "thinking" ? 0.5 : 1)
            phase: Model.unit(key + "p")
            returning: Model.unit(key + "b") < 0.3
            ink: returning ? root.colors.role("cyan") : root.ink
            time: root.time
        }
    }

    // Subagents orbit on a flattened ring with a short trail.
    Repeater {
        // A count, not the array: snapshots replace the array every second.
        model: root.agent.subagents.length
        Item {
            id: orbit
            required property int index
            readonly property var modelData: root.agent.subagents[index] || {name: ""}
            readonly property real ring: (52 + index * 18) * root.scale
            readonly property color ink: root.colors.role(Model.subagentRole(index))
            readonly property real angle: index * 2.4 + root.time * Math.max(0.15, 0.6 - index * 0.12)
            Repeater {
                model: 8
                Rectangle {
                    required property int index
                    readonly property real a: orbit.angle - index * 0.09
                    readonly property real size: index ? 4.4 * (1 - index / 9) : 9
                    width: size; height: size; radius: size / 2
                    x: Math.cos(a) * orbit.ring - size / 2
                    y: Math.sin(a) * orbit.ring * 0.82 - size / 2
                    color: orbit.ink
                    opacity: index ? 0.4 * (1 - index / 8) : 0.95
                }
            }
            Text {
                x: Math.cos(orbit.angle) * orbit.ring - width / 2
                y: Math.sin(orbit.angle) * orbit.ring * 0.82 - height - 6
                text: orbit.modelData.name
                textFormat: Text.PlainText
                color: orbit.ink
                font.family: root.fontFamily
                font.pixelSize: Math.round(10 * root.scale)
                font.weight: Font.DemiBold
            }
        }
    }

    // Ripples expand from the core while the agent is busy or waiting.
    Repeater {
        model: root.agent.status === "idle" ? 0 : 2
        Rectangle {
            id: ripple
            required property int index
            readonly property real reach: (root.waiting ? 160 : 108) * root.scale
            readonly property real period: root.waiting ? 1.2 : 1.8
            readonly property real progress: (root.time / period + index * 0.5) % 1
            // Grow the circle itself rather than scaling it, so the stroke stays thin.
            readonly property real r: 28 * root.scale + progress * (reach - 28 * root.scale)
            width: r * 2; height: width; radius: r
            x: -r; y: -r
            color: "transparent"
            border.color: root.ink
            border.width: root.waiting ? 3 : 1.5
            opacity: (1 - progress) * (root.waiting ? 0.7 : 0.3)
        }
    }

    // Core glow, pulsing harder while waiting.
    Shape {
        id: core
        readonly property real radius: 16 * root.scale * 2.6 * (root.agent.status === "idle" ? 0.7 : root.agent.status === "thinking" ? 0.85 : 1)
        width: radius * 2; height: radius * 2
        x: -radius; y: -radius
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: core.radius; centerY: core.radius; centerRadius: core.radius
                focalX: core.radius; focalY: core.radius
                GradientStop { position: 0; color: root.colors.light ? root.ink : "#f4ffffff" }
                GradientStop { position: 0.25; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.95) }
                GradientStop { position: 0.6; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathAngleArc { centerX: core.radius; centerY: core.radius; radiusX: core.radius; radiusY: core.radius; startAngle: 0; sweepAngle: 360 }
        }
        scale: root.waiting ? 1 + 0.25 * Math.sin(root.time * 4) : 1 + 0.06 * Math.sin(root.time * 5)
    }

    // Three rotating arc pairs; idle agents turn slowly.
    Repeater {
        model: [[30, 1.1, 1.6], [37, -0.7, 2.4], [44, 0.45, 0.9]]
        Shape {
            id: ringShape
            required property var modelData
            required property int index
            readonly property real r: modelData[0] * root.scale
            width: r * 2 + 4; height: width
            x: -width / 2; y: -width / 2
            // Degrees: the arc speeds are radians per second; idle agents turn at 30%.
            rotation: index * 57 + root.time * modelData[1] * 180 / Math.PI * (root.busy || root.waiting ? 1 : 0.3)
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7 - ringShape.index * 0.18)
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc { centerX: ringShape.width / 2; centerY: ringShape.width / 2; radiusX: ringShape.r; radiusY: ringShape.r; startAngle: 0; sweepAngle: ringShape.modelData[2] * 180 / Math.PI }
                PathMove { x: ringShape.width / 2 - ringShape.r; y: ringShape.width / 2 }
                PathAngleArc { centerX: ringShape.width / 2; centerY: ringShape.width / 2; radiusX: ringShape.r; radiusY: ringShape.r; startAngle: 180; sweepAngle: ringShape.modelData[2] * 0.4 * 180 / Math.PI }
            }
        }
    }
}
