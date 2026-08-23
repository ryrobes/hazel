import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
    id: root

    property var edges: []
    property color foreground: Color.popups.text
    property color accent: Color.accent
    property color urgent: Color.urgent
    property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
    property string fontFamily: Style.font.family
    property string titleText: "LOCK FLOW"
    readonly property var visibleEdges: firstRows(edges, 3)

    function firstRows(source, limit) {
        var rows = [];
        var count = source && source.length !== undefined ? Math.min(Number(source.length), limit) : 0;
        for (var i = 0; i < count; i++)
            rows.push(source[i]);
        return rows;
    }

    function shortTarget(edge) {
        var target = String(edge && edge.lockTarget ? edge.lockTarget : (edge && edge.waitEvent ? edge.waitEvent : "lock"));
        var mode = String(edge && edge.lockMode ? edge.lockMode : "");
        var label = mode !== "" ? mode + " · " + target : target;
        return label.length > 34 ? label.slice(0, 31) + "…" : label;
    }

    function repaint() {
        graph.requestPaint();
    }

    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.025)
    borderSpec: Border.controlSpec("normal", foreground, accent)
    radius: Style.cornerRadius
    onEdgesChanged: repaint()
    onWidthChanged: repaint()
    onHeightChanged: repaint()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(9)
        spacing: Style.space(3)

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: root.titleText
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
                text: root.edges.length === 0 ? "CLEAR" : root.edges.length + (root.edges.length === 1 ? " WAIT" : " WAITS")
                color: root.edges.length === 0 ? root.muted : root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
            }
        }

        Canvas {
            id: graph

            Layout.fillWidth: true
            Layout.fillHeight: true

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.clearRect(0, 0, width, height);
                var left = 27;
                var right = width - 27;
                var rows = Math.max(1, root.visibleEdges.length);
                var rowHeight = height / rows;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.font = "bold 10px '" + root.fontFamily + "'";

                if (root.visibleEdges.length === 0) {
                    var emptyY = height / 2;
                    ctx.strokeStyle = root.muted;
                    ctx.globalAlpha = 0.28;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(left + 8, emptyY);
                    ctx.lineTo(right - 8, emptyY);
                    ctx.stroke();
                    ctx.fillStyle = root.muted;
                    ctx.beginPath();
                    ctx.arc(left, emptyY, 4, 0, Math.PI * 2);
                    ctx.arc(right, emptyY, 4, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.globalAlpha = 0.72;
                    ctx.fillText("no wait chain", width / 2, emptyY - 11);
                    ctx.globalAlpha = 1;
                    return ;
                }

                for (var i = 0; i < root.visibleEdges.length; i++) {
                    var edge = root.visibleEdges[i];
                    var y = rowHeight * (i + 0.5);
                    ctx.strokeStyle = root.urgent;
                    ctx.globalAlpha = 0.62;
                    ctx.lineWidth = 1.4;
                    ctx.beginPath();
                    ctx.moveTo(left + 8, y);
                    ctx.bezierCurveTo(width * 0.38, y - 8, width * 0.62, y + 8, right - 8, y);
                    ctx.stroke();

                    ctx.fillStyle = root.accent;
                    ctx.globalAlpha = 1;
                    ctx.beginPath();
                    ctx.arc(left, y, 7, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.fillStyle = root.urgent;
                    ctx.beginPath();
                    ctx.arc(right, y, 7, 0, Math.PI * 2);
                    ctx.fill();

                    ctx.fillStyle = root.foreground;
                    ctx.font = "bold 8px '" + root.fontFamily + "'";
                    ctx.fillText(String(edge.blockerPid || "?"), left, y);
                    ctx.fillText(String(edge.blockedPid || "?"), right, y);
                    ctx.fillStyle = root.muted;
                    ctx.font = "9px '" + root.fontFamily + "'";
                    ctx.fillText(root.shortTarget(edge), width / 2, y - 10);
                }
                ctx.globalAlpha = 1;
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "HOLDER"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: "WAITER"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
            }
        }
    }
}
