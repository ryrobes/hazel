import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property color tint: "white"
    readonly property real vectorScale: Math.min(width / 24, height / 24)

    implicitWidth: 18
    implicitHeight: 16

    // These paths mirror assets/bar-rabbit.svg's 24x24 geometry. Shape keeps
    // them as scene-graph vectors instead of rasterizing and scaling an Image.
    Shape {
        width: 24
        height: 24
        x: (root.width - width * root.vectorScale) / 2
        y: (root.height - height * root.vectorScale) / 2
        scale: root.vectorScale
        transformOrigin: Item.TopLeft
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            fillColor: root.tint

            PathSvg {
                path: "M3.2.6 8.4 2l2 9.3-4.2-1.7-2.1-5z M20.8.6 15.6 2l-2 9.3 4.2-1.7 2.1-5z"
            }
        }

        ShapePath {
            fillRule: ShapePath.OddEvenFill
            strokeWidth: 0
            fillColor: root.tint

            PathSvg {
                path: "M6.2 8 12 5.5 17.8 8l3.1 5.7-2.3 6.8L12 23l-6.6-2.5-2.3-6.8z M5.1 12.2h13.8l-2 3.1H7.1z M10.2 18.3l1.8 1.4 1.8-1.4-1.8 3z"
            }
        }
    }
}
