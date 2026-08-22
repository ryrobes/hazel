import QtQuick

Item {
    id: root

    property var history: []
    property color lineColor: "white"
    property color fillColor: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.1)
    property color gridColor: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.12)
    property real lineWidth: 1.5
    property real maximum: 0
    property bool mirrored: false

    function observedMaximum() {
        if (maximum > 0)
            return maximum;

        var peak = 0;
        for (var i = 0; i < history.length; i++) {
            var value = Number(history[i].value);
            if (isFinite(value) && value > peak)
                peak = value;

        }
        return Math.max(1, peak);
    }

    implicitHeight: 58
    implicitWidth: 220
    onHistoryChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onFillColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (width <= 2 || height <= 2)
                return ;

            ctx.strokeStyle = String(root.gridColor);
            ctx.lineWidth = 1;
            ctx.setLineDash([2, 5]);
            ctx.beginPath();
            ctx.moveTo(0, Math.round(height * 0.5) + 0.5);
            ctx.lineTo(width, Math.round(height * 0.5) + 0.5);
            ctx.stroke();
            ctx.setLineDash([]);
            var points = root.history || [];
            if (points.length === 0)
                return ;

            var maxValue = root.observedMaximum();
            var pad = 2;
            var usableHeight = Math.max(1, height - pad * 2);
            ctx.beginPath();
            ctx.moveTo(points.length <= 1 ? width : 0, root.mirrored ? 0 : height);
            for (var i = 0; i < points.length; i++) {
                var fillX = points.length <= 1 ? width : i * width / (points.length - 1);
                var fillFraction = Math.max(0, Math.min(1, Number(points[i].value) / maxValue));
                var fillY = root.mirrored ? pad + fillFraction * usableHeight : height - pad - fillFraction * usableHeight;
                ctx.lineTo(fillX, fillY);
            }
            ctx.lineTo(width, root.mirrored ? 0 : height);
            ctx.closePath();
            ctx.fillStyle = String(root.fillColor);
            ctx.fill();
            ctx.beginPath();
            for (var j = 0; j < points.length; j++) {
                var x = points.length <= 1 ? width : j * width / (points.length - 1);
                var fraction = Math.max(0, Math.min(1, Number(points[j].value) / maxValue));
                var y = root.mirrored ? pad + fraction * usableHeight : height - pad - fraction * usableHeight;
                if (j === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.strokeStyle = String(root.lineColor);
            ctx.lineWidth = root.lineWidth;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.stroke();
        }
    }

}
