import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
    id: root

    property var jobs: []
    property color foreground: Color.popups.text
    property color accent: Color.accent
    property color urgent: Color.urgent
    property color warning: Color.accent
    property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
    property string fontFamily: Style.font.family
    property real phase: 0
    readonly property var visibleJobs: firstRows(jobs, 3)

    function firstRows(source, limit) {
        var rows = [];
        var count = source && source.length !== undefined ? Math.min(Number(source.length), limit) : 0;
        for (var i = 0; i < count; i++)
            rows.push(source[i]);
        return rows;
    }

    function jobLabel(job) {
        var kind = String(job.kind || "work").toUpperCase();
        var table = String(job.table || "background");
        if (job.kind === "merge")
            return kind + "  " + table + "  ·  " + Math.round(Number(job.progress || 0) * 100) + "%";
        return kind + "  " + table + "  ·  " + Number(job.partsToDo || 0) + " PARTS";
    }

    function repaint() {
        conveyor.requestPaint();
    }

    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.025)
    borderSpec: Border.controlSpec("normal", foreground, accent)
    radius: Style.cornerRadius
    onJobsChanged: repaint()
    onWidthChanged: repaint()
    onHeightChanged: repaint()
    onPhaseChanged: repaint()

    NumberAnimation on phase {
        from: 0
        to: 1
        duration: 1500
        loops: Animation.Infinite
        running: root.visible && root.jobs.length > 0
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(9)
        spacing: Style.space(3)

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "BACKGROUND WORK"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.jobs.length === 0 ? "CLEAR" : root.jobs.length + (root.jobs.length === 1 ? " JOB" : " JOBS")
                color: root.jobs.length === 0 ? root.muted : root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
            }
        }

        Canvas {
            id: conveyor
            Layout.fillWidth: true
            Layout.fillHeight: true

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.clearRect(0, 0, width, height);
                var rows = Math.max(1, root.visibleJobs.length);
                var rowHeight = height / rows;

                if (root.visibleJobs.length === 0) {
                    var y = height / 2;
                    ctx.strokeStyle = String(root.muted);
                    ctx.globalAlpha = 0.25;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(8, y);
                    ctx.lineTo(width - 8, y);
                    ctx.stroke();
                    for (var idle = 0; idle < 5; idle++)
                        ctx.fillRect(14 + idle * Math.max(18, (width - 34) / 5), y - 3, 11, 6);
                    ctx.globalAlpha = 0.7;
                    ctx.fillStyle = String(root.muted);
                    ctx.textAlign = "center";
                    ctx.font = "bold 9px '" + root.fontFamily + "'";
                    ctx.fillText("parts at rest", width / 2, y - 12);
                    ctx.globalAlpha = 1;
                    return;
                }

                for (var i = 0; i < root.visibleJobs.length; i++) {
                    var job = root.visibleJobs[i];
                    var centerY = rowHeight * (i + 0.5);
                    var tone = job.failed ? root.urgent : (job.kind === "mutation" ? root.warning : root.accent);
                    ctx.globalAlpha = 0.2;
                    ctx.strokeStyle = String(tone);
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(5, centerY + 7);
                    ctx.lineTo(width - 5, centerY + 7);
                    ctx.stroke();

                    var step = 24;
                    var offset = (root.phase * step) % step;
                    ctx.fillStyle = String(tone);
                    ctx.globalAlpha = 0.5;
                    for (var x = -step + offset; x < width; x += step)
                        ctx.fillRect(x, centerY + 4, 14, 6);

                    if (job.kind === "merge") {
                        var progress = Math.max(0, Math.min(1, Number(job.progress || 0)));
                        ctx.globalAlpha = 0.18;
                        ctx.fillRect(5, centerY - 2, width - 10, 2);
                        ctx.globalAlpha = 0.9;
                        ctx.fillRect(5, centerY - 2, (width - 10) * progress, 2);
                    }
                    ctx.globalAlpha = 1;
                    ctx.fillStyle = String(job.failed ? root.urgent : root.foreground);
                    ctx.textAlign = "left";
                    ctx.font = "bold 9px '" + root.fontFamily + "'";
                    ctx.fillText(root.jobLabel(job), 5, centerY - 7);
                }
                ctx.globalAlpha = 1;
            }
        }
    }
}
