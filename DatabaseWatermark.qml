import QtQuick
import QtQuick.Effects

Item {
    id: root

    property string engine: "postgresql"
    property bool pgRvbbit: false
    property color accent: "white"
    property real markOpacity: 0.085

    readonly property url markSource: {
        if (engine === "postgresql" || engine === "postgres")
            return Qt.resolvedUrl(pgRvbbit ? "assets/pg-rvbbit.svg" : "assets/postgresql.svg");
        if (engine === "mysql")
            return Qt.resolvedUrl("assets/mysql.svg");
        if (engine === "mariadb")
            return Qt.resolvedUrl("assets/mariadb.svg");
        if (engine === "percona")
            return Qt.resolvedUrl("assets/percona.svg");
        if (engine === "clickhouse")
            return Qt.resolvedUrl("assets/clickhouse.svg");
        return "";
    }

    implicitWidth: 108
    implicitHeight: 81
    visible: markSource.toString() !== ""

    Image {
        id: sourceMark
        anchors.fill: parent
        source: root.markSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: sourceMark
        source: sourceMark
        autoPaddingEnabled: false
        colorization: 1.0
        colorizationColor: root.accent
        opacity: root.markOpacity
    }
}
