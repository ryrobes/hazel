import "Model.js" as Model
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
    id: root

    property var activity: []
    property color foreground: Color.popups.text
    property color accent: Color.accent
    property color urgent: Color.urgent
    property color warning: Color.accent
    property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
    property string fontFamily: Style.font.family
    readonly property var visibleQueries: firstRows(activity, 3)

    function firstRows(source, limit) {
        var rows = [];
        var count = source && source.length !== undefined ? Math.min(Number(source.length), limit) : 0;
        for (var i = 0; i < count; i++)
            rows.push(source[i]);
        return rows;
    }

    function queryText(row) {
        var text = String(row && row.queryText ? row.queryText : "Active query text is unavailable").trim();
        return text === "" ? "Active query text is unavailable" : text;
    }

    function queryMeta(row) {
        var app = String(row.application || "").trim();
        if (app === "")
            app = String(row.user || "session");
        var age = Model.formatDuration(Number(row.querySeconds || 0));
        if (row.waitEvent)
            return app + " · " + age + " · " + row.waitEvent;

        return app + " · " + age + " · PID " + row.pid;
    }

    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.025)
    borderSpec: Border.controlSpec("normal", foreground, accent)
    radius: Style.cornerRadius

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(9)
        spacing: Style.space(5)

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "LIVE WORK"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: root.activity.length + " CAPTURED"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
            }
        }

        Item {
            visible: root.visibleQueries.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                text: "No active client work in the detail sample"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }
        }

        Repeater {
            model: root.visibleQueries

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Style.space(7)

                Rectangle {
                    Layout.preferredWidth: Style.space(3)
                    Layout.fillHeight: true
                    Layout.maximumHeight: Style.space(28)
                    radius: width / 2
                    color: modelData.blockedBy && modelData.blockedBy.length > 0 ? root.urgent : (modelData.waitEvent ? root.warning : root.accent)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: root.queryText(modelData)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.queryMeta(modelData)
                        color: modelData.blockedBy && modelData.blockedBy.length > 0 ? root.urgent : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
            }
        }

        Text {
            visible: root.activity.length > root.visibleQueries.length
            Layout.fillWidth: true
            text: "+" + (root.activity.length - root.visibleQueries.length) + " more captured"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
        }
    }
}
