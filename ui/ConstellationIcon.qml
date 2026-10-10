import QtQuick
import QtQuick.Shapes

// Three linked stars; geometric so it stays sharp at any bar scale.
Item {
    id: root
    required property color ink
    implicitWidth: 20
    implicitHeight: 20
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.ink
            strokeWidth: 1.1
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M 5 14 L 10 5 L 16 12 L 5 14" }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.ink
            PathSvg { path: "M 7.4 14 A 2.4 2.4 0 1 1 2.6 14 A 2.4 2.4 0 1 1 7.4 14 M 12 5 A 2 2 0 1 1 8 5 A 2 2 0 1 1 12 5 M 18 12 A 2 2 0 1 1 14 12 A 2 2 0 1 1 18 12" }
        }
    }
}
