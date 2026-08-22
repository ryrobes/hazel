import QtQuick
import QtQuick.Effects

Item {
    id: root

    property color accent: "white"
    property real glyphOpacity: 0.72

    implicitWidth: 11
    implicitHeight: 11

    Image {
        id: glyphSource
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/database.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: glyphSource
        source: glyphSource
        autoPaddingEnabled: false
        colorization: 1.0
        colorizationColor: root.accent
        opacity: root.glyphOpacity
    }
}
