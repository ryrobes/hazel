import "Model.js" as Model
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: root

    signal windowRequested(int hours)
    signal windowInteractionStarted()

    property string engine: "postgresql"
    property real transactions: 0
    property int lockWaits: 0
    property int blocked: 0
    property real oldestLockWaitSeconds: 0
    property int connectionsUsed: 0
    property int maxConnections: 0
    property real deadTuples: 0
    property int autovacuumWorkers: 0
    property int vacuumWorkers: 0
    property int runningQueries: 0
    property int activeMerges: 0
    property int pendingMutations: 0
    property int activeParts: 0
    property real capacityUsed: 0
    property real capacityMax: 0
    property var lastAutovacuum: null
    property var lastVacuum: null
    property var transactionHistory: []
    property var lockWaitHistory: []
    property var connectionHistory: []
    property var deadTupleHistory: []
    property var autovacuumHistory: []
    property var runningHistory: []
    property var capacityHistory: []
    property string maintenanceLabel: "DEAD TUPLES"
    property string maintenanceKind: "vacuum"
    property int windowHours: 6
    property bool expandedLayout: false
    property color foreground: Color.foreground
    property color accent: Color.accent
    property color urgent: Color.urgent
    property color muted: Color.muted
    property color warning: Qt.tint(accent, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.52))
    property string fontFamily: Style.font.family

    function rowKeys() {
        return Model.isClickHouse(engine) ? ["flow", "running", "memory", "maintenance"] : ["flow", "locks", "connections", "deadTuples"];
    }

    function rowLabel(key) {
        if (key === "flow")
            return "FLOW";
        if (key === "locks")
            return "LOCK WAITS";
        if (key === "connections")
            return "CONNECTIONS";
        if (key === "running")
            return "RUNNING";
        if (key === "memory")
            return "MEMORY";
        if (key === "maintenance")
            return "MERGE DEBT";
        return maintenanceLabel;
    }

    function rowKind(key) {
        if (key === "flow")
            return "rate";
        if (key === "connections")
            return "connections";
        if (key === "memory")
            return "bytes";
        return "count";
    }

    function rowCurrent(key) {
        if (key === "flow")
            return transactions;
        if (key === "locks")
            return lockWaits;
        if (key === "connections")
            return connectionsUsed;
        if (key === "running")
            return runningQueries;
        if (key === "memory")
            return capacityUsed;
        if (key === "maintenance")
            return deadTuples;
        return deadTuples;
    }

    function rawHistory(key) {
        if (key === "flow")
            return transactionHistory;
        if (key === "locks")
            return lockWaitHistory;
        if (key === "connections")
            return connectionHistory;
        if (key === "running")
            return runningHistory;
        if (key === "memory")
            return capacityHistory;
        return deadTupleHistory;
    }

    function historyFor(key) {
        var source = rawHistory(key) || [];
        if (source.length < 2)
            return source;
        var latest = Number(source[source.length - 1].time || 0);
        var cutoff = latest - windowHours * 60 * 60 * 1000;
        var start = 0;
        while (start < source.length - 1 && Number(source[start].time || 0) < cutoff)
            start++;
        return start > 0 ? source.slice(start) : source;
    }

    function formatCount(value) {
        var number = Math.max(0, Number(value) || 0);
        if (number >= 1000000000)
            return (number / 1000000000).toFixed(number >= 10000000000 ? 0 : 1) + "G";
        if (number >= 1000000)
            return (number / 1000000).toFixed(number >= 10000000 ? 0 : 1) + "M";
        if (number >= 1000)
            return (number / 1000).toFixed(number >= 10000 ? 0 : 1) + "k";
        return String(Math.round(number));
    }

    function formatValue(value, kind) {
        if (kind === "rate")
            return Model.formatRate(value, "/s");
        if (kind === "bytes")
            return Model.formatBytes(value);
        return formatCount(value);
    }

    function currentText(key) {
        if (key === "connections")
            return formatCount(rowCurrent(key)) + "/" + formatCount(maxConnections);
        if (key === "memory")
            return formatValue(rowCurrent(key), rowKind(key));
        return formatValue(rowCurrent(key), rowKind(key));
    }

    function observedText() {
        var stats = Model.historyStats(historyFor("flow"));
        if (stats.count < 2 || stats.lastAt <= stats.firstAt)
            return windowHours + "H LENS  ·  WARMING UP";
        var observed = Model.formatDuration((stats.lastAt - stats.firstAt) / 1000);
        return windowHours + "H LENS  ·  " + observed + " OBSERVED  ·  5s BUCKETS";
    }

    function lockContext() {
        if (Model.isClickHouse(engine))
            return runningQueries + (runningQueries === 1 ? " QUERY RUNNING" : " QUERIES RUNNING");
        if (lockWaits <= 0)
            return "LOCKS CLEAR";
        var text = lockWaits + (lockWaits === 1 ? " LOCK WAIT" : " LOCK WAITS");
        if (blocked > 0)
            text += " · " + blocked + " BLOCKED";
        if (oldestLockWaitSeconds > 0)
            text += " · " + Model.formatDuration(oldestLockWaitSeconds) + " OLD";
        return text;
    }

    function mvccTrendPerMinute() {
        return Model.historyRate(deadTupleHistory, 5 * 60 * 1000, 60);
    }

    function vacuumContext() {
        if (Model.isClickHouse(engine))
            return activeMerges + (activeMerges === 1 ? " MERGE" : " MERGES")
                + " · " + pendingMutations + (pendingMutations === 1 ? " MUTATION" : " MUTATIONS")
                + " · " + formatCount(activeParts) + " PARTS";
        var trend = mvccTrendPerMinute();
        var lastDrop = Model.historyLastDrop(deadTupleHistory);
        var recentDrop = lastDrop.amount > 0 && Date.now() - lastDrop.at <= 10 * 60 * 1000;
        if (maintenanceKind === "purge") {
            var purgeText = recentDrop
                ? "PURGED " + formatCount(lastDrop.amount)
                : (Math.abs(trend) < 0.5
                    ? "PURGE STEADY"
                    : (trend > 0 ? "UNDO +" : "UNDO −") + formatCount(Math.abs(trend)) + "/min");
            return purgeText + (vacuumWorkers > 0
                ? " · " + vacuumWorkers + (vacuumWorkers === 1 ? " PURGE THREAD" : " PURGE THREADS")
                : " · PURGE IDLE");
        }
        var text = recentDrop
            ? "CLEARED " + formatCount(lastDrop.amount)
            : (Math.abs(trend) < 0.5
                ? "MVCC STEADY"
                : (trend > 0 ? "MVCC +" : "MVCC −") + formatCount(Math.abs(trend)) + "/min");
        if (vacuumWorkers > 0)
            return text + " · " + vacuumWorkers + (autovacuumWorkers > 0 ? " AUTO" : " VAC") + " ACTIVE";
        var autoAt = lastAutovacuum ? new Date(lastAutovacuum).getTime() : 0;
        var manualAt = lastVacuum ? new Date(lastVacuum).getTime() : 0;
        var latest = Math.max(isFinite(autoAt) ? autoAt : 0, isFinite(manualAt) ? manualAt : 0);
        if (latest > 0) {
            var kind = autoAt >= manualAt ? "AUTO" : "VAC";
            return text + " · " + kind + " " + Model.formatDuration(Math.max(0, Date.now() - latest) / 1000) + " AGO";
        }
        return text + " · NO AUTO YET";
    }

    function rowColor(key) {
        var stats = Model.historyStats(historyFor(key));
        var current = rowCurrent(key);
        if (key === "locks")
            return blocked > 0 ? urgent : (lockWaits > 0 ? warning : accent);
        if (key === "connections") {
            var ratio = maxConnections > 0 ? current / maxConnections : 0;
            return ratio >= 0.95 ? urgent : (ratio >= 0.8 ? warning : accent);
        }
        if (key === "memory") {
            var capacityRatio = capacityMax > 0 ? current / capacityMax : 0;
            return capacityRatio >= 0.95 ? urgent : (capacityRatio >= 0.8 ? warning : accent);
        }
        if (key === "maintenance")
            return pendingMutations > 0 ? warning : accent;
        if (key === "deadTuples") {
            var trend = mvccTrendPerMinute();
            if (stats.count >= 12 && stats.p90 > 0 && current > stats.p90 * 1.5)
                return urgent;
            if (trend > 0.5 || (stats.count >= 12 && current > stats.p90))
                return warning;
            return accent;
        }
        if (stats.count >= 12 && stats.p90 > 0 && current > stats.p90 * 1.5)
            return urgent;
        if (stats.count >= 12 && current > stats.p90)
            return warning;
        return accent;
    }

    implicitWidth: Style.space(400)
    implicitHeight: Style.space(expandedLayout ? 236 : 146)

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(root.expandedLayout ? 5 : 2)

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(root.expandedLayout ? 22 : 14)
            spacing: Style.space(8)

            Text {
                text: "BEHAVIOR MEMORY"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
            }

            Text {
                visible: root.expandedLayout
                Layout.fillWidth: true
                text: "DISTRIBUTION  ·  P25–P90 BAND  ·  ● NOW"
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.38)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
            }

            Item { visible: !root.expandedLayout; Layout.fillWidth: true }

            Repeater {
                model: root.expandedLayout ? [1, 3, 6, 24] : []

                delegate: Rectangle {
                    required property int modelData
                    readonly property bool selected: root.windowHours === modelData

                    Layout.preferredWidth: Style.space(modelData === 24 ? 36 : 31)
                    Layout.preferredHeight: Style.space(18)
                    radius: Style.cornerRadius
                    color: selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) : "transparent"
                    border.width: 1
                    border.color: selected
                        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.62)
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13)

                    Text {
                        anchors.centerIn: parent
                        text: modelData + "H"
                        color: selected ? root.accent : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.windowInteractionStarted()
                        onClicked: root.windowRequested(modelData)
                    }
                }
            }

            Text {
                visible: !root.expandedLayout
                text: root.windowHours + "H"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
            }
        }

        Repeater {
            model: root.rowKeys()

            delegate: Item {
                id: behaviorRow

                required property string modelData
                readonly property string key: modelData
                readonly property string kind: root.rowKind(key)
                readonly property real current: Number(root.rowCurrent(key)) || 0
                readonly property var stats: Model.historyStats(root.historyFor(key))
                readonly property color signalColor: root.rowColor(key)

                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(root.expandedLayout ? 42 : 24)

                Column {
                    id: currentColumn
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(root.expandedLayout ? 112 : 78)
                    spacing: 0

                    Text {
                        width: parent.width
                        text: root.rowLabel(behaviorRow.key)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 0.65
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.currentText(behaviorRow.key) + "  NOW"
                        color: behaviorRow.signalColor
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: landmarks
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(root.expandedLayout ? 270 : 192)
                    height: parent.height

                    Repeater {
                        model: ["P50", "P90", "HIGH"]

                        delegate: Column {
                            required property string modelData
                            width: landmarks.width / 3
                            spacing: 0

                            Text {
                                width: parent.width
                                text: modelData
                                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.42)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                            }

                            Text {
                                width: parent.width
                                text: root.formatValue(modelData === "P50" ? behaviorRow.stats.p50
                                    : (modelData === "P90" ? behaviorRow.stats.p90 : behaviorRow.stats.high), behaviorRow.kind)
                                color: modelData === "HIGH" ? behaviorRow.signalColor : root.muted
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }

                Rectangle {
                    id: lane
                    anchors.left: currentColumn.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: landmarks.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.space(root.expandedLayout ? 24 : 9)
                    radius: height / 2
                    clip: true
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.065)
                    border.width: 1
                    border.color: Qt.rgba(behaviorRow.signalColor.r, behaviorRow.signalColor.g, behaviorRow.signalColor.b, 0.12)

                    Canvas {
                        id: distribution
                        anchors.fill: parent
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.clearRect(0, 0, width, height);
                            var history = root.historyFor(behaviorRow.key);
                            var stats = behaviorRow.stats;
                            var zoomed = behaviorRow.key === "connections" || behaviorRow.key === "deadTuples" || behaviorRow.key === "running" || behaviorRow.key === "memory" || behaviorRow.key === "maintenance";
                            var span = Math.max(0, stats.high - stats.low);
                            var pad = zoomed ? Math.max(1, span * 0.12, stats.high * 0.005) : 0;
                            var axisLow = zoomed ? Math.max(0, stats.low - pad) : 0;
                            var axisHigh = zoomed
                                ? Math.max(axisLow + 1, stats.high + pad, behaviorRow.current)
                                : Math.max(1, stats.high, behaviorRow.current);
                            var usableLeft = 4;
                            var usableWidth = Math.max(1, width - 8);

                            function xFor(value) {
                                var ratio = (Number(value) - axisLow) / Math.max(1e-9, axisHigh - axisLow);
                                return usableLeft + usableWidth * Math.max(0, Math.min(1, ratio));
                            }

                            ctx.strokeStyle = String(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08));
                            ctx.lineWidth = 1;
                            for (var grid = 1; grid < 4; grid++) {
                                var gridX = Math.round(width * grid / 4) + 0.5;
                                ctx.beginPath();
                                ctx.moveTo(gridX, 2);
                                ctx.lineTo(gridX, height - 2);
                                ctx.stroke();
                            }

                            var bins = root.expandedLayout ? 32 : 20;
                            var counts = [];
                            var maximumCount = 0;
                            for (var b = 0; b < bins; b++) counts.push(0);
                            for (var i = 0; i < history.length; i++) {
                                var value = Math.max(axisLow, Number(history[i] && history[i].value) || 0);
                                var index = Math.min(bins - 1, Math.max(0, Math.floor(bins * (value - axisLow) / Math.max(1e-9, axisHigh - axisLow))));
                                counts[index]++;
                                maximumCount = Math.max(maximumCount, counts[index]);
                            }
                            if (maximumCount > 0) {
                                var binWidth = usableWidth / bins;
                                for (var j = 0; j < bins; j++) {
                                    var density = counts[j] / maximumCount;
                                    ctx.fillStyle = String(Qt.rgba(behaviorRow.signalColor.r, behaviorRow.signalColor.g, behaviorRow.signalColor.b, 0.04 + density * 0.28));
                                    ctx.fillRect(usableLeft + j * binWidth, 1, Math.max(1, binWidth), height - 2);
                                }
                            }

                            var bandLeft = xFor(stats.p25);
                            var bandRight = xFor(stats.p90);
                            ctx.fillStyle = String(Qt.rgba(behaviorRow.signalColor.r, behaviorRow.signalColor.g, behaviorRow.signalColor.b, 0.18));
                            ctx.fillRect(bandLeft, 1, Math.max(1, bandRight - bandLeft), height - 2);

                            ctx.strokeStyle = String(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.52));
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            ctx.moveTo(xFor(stats.p50) + 0.5, 1);
                            ctx.lineTo(xFor(stats.p50) + 0.5, height - 1);
                            ctx.stroke();

                            ctx.strokeStyle = String(behaviorRow.signalColor);
                            ctx.lineWidth = 1.5;
                            ctx.beginPath();
                            ctx.moveTo(xFor(stats.p90) + 0.5, 1);
                            ctx.lineTo(xFor(stats.p90) + 0.5, height - 1);
                            ctx.stroke();

                            var highX = xFor(stats.high);
                            ctx.fillStyle = String(root.muted);
                            ctx.beginPath();
                            ctx.moveTo(highX, 1);
                            ctx.lineTo(highX + 3, height / 2);
                            ctx.lineTo(highX, height - 1);
                            ctx.lineTo(highX - 3, height / 2);
                            ctx.closePath();
                            ctx.fill();

                            ctx.fillStyle = String(behaviorRow.signalColor);
                            ctx.beginPath();
                            ctx.arc(xFor(behaviorRow.current), height / 2, Math.max(2.5, height * 0.25), 0, Math.PI * 2);
                            ctx.fill();
                        }

                        Connections {
                            target: behaviorRow
                            function onStatsChanged() { distribution.requestPaint(); }
                            function onCurrentChanged() { distribution.requestPaint(); }
                            function onSignalColorChanged() { distribution.requestPaint(); }
                        }

                        Connections {
                            target: root
                            function onWindowHoursChanged() { distribution.requestPaint(); }
                            function onTransactionHistoryChanged() { distribution.requestPaint(); }
                            function onLockWaitHistoryChanged() { distribution.requestPaint(); }
                            function onConnectionHistoryChanged() { distribution.requestPaint(); }
                            function onDeadTupleHistoryChanged() { distribution.requestPaint(); }
                            function onRunningHistoryChanged() { distribution.requestPaint(); }
                            function onCapacityHistoryChanged() { distribution.requestPaint(); }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(16)
            spacing: Style.space(8)

            Text {
                Layout.minimumWidth: 0
                text: root.lockContext()
                color: Model.isClickHouse(root.engine) ? (root.runningQueries > 0 ? root.accent : root.muted) : (root.blocked > 0 ? root.urgent : (root.lockWaits > 0 ? root.warning : root.muted))
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.minimumWidth: 0
                text: root.observedText()
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.minimumWidth: 0
                text: root.vacuumContext()
                color: Model.isClickHouse(root.engine) ? (root.pendingMutations > 0 ? root.warning : root.muted) : (root.mvccTrendPerMinute() > 0.5 ? root.warning : root.muted)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
            }
        }
    }
}
