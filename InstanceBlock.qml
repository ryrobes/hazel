import "Model.js" as Model
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
    id: root

    signal expansionRequested()
    signal historyWindowRequested(int hours)

    property var profile: ({})
    property var snapshot: Model.emptyState()
    property string errorText: ""
    property bool expanded: false
    property bool minimized: false
    property bool windowControlActive: false
    property int historyHours: 6
    property color foreground: Color.popups.text
    property color accent: Color.accent
    property color urgent: Color.urgent
    property color warning: Color.accent
    property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
    property string fontFamily: Style.font.family

    readonly property bool connected: snapshot && snapshot.connected === true
    readonly property color statusTone: !connected || snapshot.severity === "critical"
        ? urgent : (snapshot.severity === "warning" ? warning : accent)
    readonly property var topQuery: connected && snapshot.activity && snapshot.activity.length > 0
        ? snapshot.activity[0] : null
    property real cardHeight: minimized
        ? Style.space(54)
        : (connected ? (expanded ? Style.space(670) : Style.space(320)) : Style.space(150))

    function profileName() {
        return String(profile.name || profile.profileName || "Postgres");
    }

    function databaseName() {
        if (connected && snapshot.identity && snapshot.identity.database)
            return String(snapshot.identity.database);
        return String(profile.database || "postgres");
    }

    function routeLabel() {
        if (profile.sshEnabled === true)
            return "via " + String(profile.sshUser || "") + "@" + String(profile.sshHost || "");
        return String(profile.host || "local socket") + (profile.host ? ":" + String(profile.port || 5432) : "");
    }

    function identityMeta() {
        if (!connected)
            return errorText || "Connecting to PostgreSQL";
        var role = snapshot.identity.inRecovery ? "standby" : "primary";
        return "PG " + String(snapshot.identity.version || "") + " · " + role + " · " + snapshot.statusLabel;
    }

    function topQueryLabel() {
        if (!topQuery)
            return "No active client queries in this sample";
        return String(topQuery.queryText || "Active query text unavailable");
    }

    function relationDetail(row) {
        var ratio = Number(row.deadPercent || 0);
        var text = Number(row.deadTuples || 0).toLocaleString() + " dead · " + ratio.toFixed(ratio >= 10 ? 0 : 1) + "%";
        if (row.lastAutovacuum)
            text += " · vacuumed " + Qt.formatDateTime(new Date(row.lastAutovacuum), "MMM d HH:mm");
        return text;
    }

    function statValue(label) {
        if (label === "ACTIVE")
            return snapshot.connections.active;
        if (label === "WAIT")
            return snapshot.connections.waiting;
        if (label === "BLOCK")
            return snapshot.connections.blocked;
        return snapshot.connections.used + "/" + snapshot.connections.max;
    }

    function statTone(label) {
        if (label === "ACTIVE")
            return accent;
        if (label === "WAIT")
            return warning;
        if (label === "BLOCK")
            return urgent;
        return foreground;
    }

    function statHot(label) {
        if (label === "CONN")
            return Number(snapshot.connections.used || 0) > 0;
        return Number(statValue(label) || 0) > 0;
    }

    function focusSummary() {
        if (!connected)
            return "OFFLINE  ·  FOCUS ↗";
        return "A " + snapshot.connections.active
            + "  ·  W " + snapshot.connections.waiting
            + "  ·  B " + snapshot.connections.blocked
            + "  ·  FOCUS ↗";
    }

    Layout.fillWidth: true
    Layout.preferredHeight: cardHeight
    clip: true
    color: "transparent"
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
            position: 0
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.expanded ? 0.20 : (root.minimized ? 0.11 : 0.155))
        }
        GradientStop {
            position: 0.34
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.expanded ? 0.075 : (root.minimized ? 0.035 : 0.055))
        }
        GradientStop {
            position: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.012)
        }
    }
    borderSpec: Border.none()
    radius: Style.cornerRadius

    Behavior on cardHeight {
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
    }

    onSnapshotChanged: {
        if (root.visible)
            refreshPulse.restart();
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: {
            if (!root.windowControlActive)
                root.expansionRequested();
            root.windowControlActive = false;
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(6)
        color: root.accent
        opacity: root.connected ? 1 : 0.48
        radius: parent.radius
    }

    DatabaseWatermark {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Style.space(14)
        anchors.bottomMargin: Style.space(12)
        width: Style.space(108)
        height: Style.space(81)
        visible: !root.expanded && !root.minimized && root.connected
        engine: String(root.snapshot.engine || "postgresql")
        pgRvbbit: root.snapshot.capabilities.pgRvbbit === true
        accent: root.accent
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(12)
        anchors.topMargin: Style.space(root.minimized ? 7 : 10)
        anchors.bottomMargin: Style.space(root.minimized ? 7 : 10)
        spacing: Style.space(7)

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(7)

            Rectangle {
                Layout.preferredWidth: Style.space(8)
                Layout.preferredHeight: Style.space(8)
                radius: width / 2
                color: root.statusTone

                SequentialAnimation on opacity {
                    running: root.connected && root.snapshot.connections.active > 0
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.42; duration: 780; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.42; to: 1; duration: 780; easing.type: Easing.InOutSine }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: root.profileName()
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(4)

                    DatabaseGlyph {
                        Layout.preferredWidth: Style.space(11)
                        Layout.preferredHeight: Style.space(11)
                        accent: root.accent
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.databaseName() + " · " + root.routeLabel()
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: root.expanded ? Text.ElideNone : Text.ElideMiddle
                        textFormat: Text.PlainText
                    }
                }
            }

            ColumnLayout {
                visible: !root.minimized
                Layout.maximumWidth: root.expanded ? root.width : Style.space(190)
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.identityMeta().toUpperCase()
                    color: root.statusTone
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.8
                    elide: root.expanded ? Text.ElideNone : Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }
            }

            Text {
                visible: root.minimized
                text: root.focusSummary()
                color: root.snapshot.connections.blocked > 0 ? root.urgent
                    : (root.snapshot.connections.waiting > 0 ? root.warning : root.accent)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
                horizontalAlignment: Text.AlignRight
            }
        }

        Text {
            visible: !root.minimized && !root.connected
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.errorText !== "" ? root.errorText : "Connecting to " + root.databaseName()
            color: root.errorText !== "" ? root.urgent : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
        }

        PressureAperture {
            visible: !root.minimized && root.connected
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(root.expanded ? 236 : 146)
            transactions: root.snapshot.rates.transactions
            lockWaits: root.snapshot.connections.lockWaiting
            blocked: root.snapshot.connections.blocked
            oldestLockWaitSeconds: root.snapshot.connections.oldestLockWaitSeconds
            connectionsUsed: root.snapshot.connections.used
            maxConnections: root.snapshot.connections.max
            deadTuples: root.snapshot.mvcc.deadTuples
            autovacuumWorkers: root.snapshot.mvcc.autovacuumWorkers
            vacuumWorkers: root.snapshot.mvcc.vacuumWorkers
            lastAutovacuum: root.snapshot.mvcc.lastAutovacuum
            lastVacuum: root.snapshot.mvcc.lastVacuum
            transactionHistory: root.snapshot.histories.transactions
            lockWaitHistory: root.snapshot.histories.lockWaiting
            connectionHistory: root.snapshot.histories.connectionsUsed
            deadTupleHistory: root.snapshot.histories.deadTuples
            autovacuumHistory: root.snapshot.histories.autovacuumCount
            windowHours: root.historyHours
            expandedLayout: root.expanded
            foreground: root.foreground
            accent: root.accent
            urgent: root.urgent
            muted: root.muted
            warning: root.warning
            fontFamily: root.fontFamily
            onWindowInteractionStarted: root.windowControlActive = true
            onWindowRequested: function(hours) {
                root.historyWindowRequested(hours);
                windowControlReset.restart();
            }
        }

        RowLayout {
            visible: !root.minimized && root.connected
            Layout.fillWidth: true
            spacing: Style.space(5)

            Repeater {
                model: ["ACTIVE", "WAIT", "BLOCK", "CONN"]

                delegate: Rectangle {
                    required property string modelData
                    readonly property color tone: root.statTone(modelData)
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(30)
                    color: Qt.rgba(tone.r, tone.g, tone.b, root.statHot(modelData) ? 0.1 : 0.03)
                    border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.18)
                    border.width: 1
                    radius: Style.cornerRadius

                    Row {
                        anchors.centerIn: parent
                        spacing: Style.space(4)
                        Text {
                            text: root.statValue(modelData)
                            color: tone
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }
                        Text {
                            text: modelData
                            color: root.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }
                    }
                }
            }
        }

        RowLayout {
            visible: !root.minimized && root.connected
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(8)

            Item {
                Layout.preferredWidth: Style.space(120)
                Layout.fillHeight: true

                Sparkline {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: Style.space(root.expanded ? 8 : 15)
                    history: root.snapshot.histories.transactions
                    lineColor: root.accent
                    fillColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1)
                    gridColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                }

                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: Model.formatRate(root.snapshot.rates.transactions, " tx/s")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: "LIVE WORK · " + root.snapshot.activity.length + " CAPTURED"
                    color: root.topQuery ? root.foreground : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.7
                }

                Text {
                    Layout.fillWidth: true
                    text: root.topQueryLabel()
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            ColumnLayout {
                Layout.preferredWidth: Style.space(100)
                Layout.fillHeight: true
                spacing: 1

                Text {
                    text: "LOCK FLOW"
                    color: root.snapshot.connections.blocked > 0 ? root.urgent : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.7
                }

                Text {
                    text: root.snapshot.connections.blocked > 0
                        ? root.snapshot.connections.blocked + " blocked"
                        : (root.snapshot.connections.lockWaiting > 0 ? root.snapshot.connections.lockWaiting + " waiting" : "clear")
                    color: root.snapshot.connections.blocked > 0 ? root.urgent : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }
            }
        }

        RowLayout {
            visible: !root.minimized && root.connected && root.expanded
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(132)
            spacing: Style.space(8)

            LiveQueries {
                Layout.fillWidth: true
                Layout.fillHeight: true
                activity: root.snapshot.activity
                foreground: root.foreground
                accent: root.accent
                urgent: root.urgent
                warning: root.warning
                muted: root.muted
                fontFamily: root.fontFamily
            }

            LockFlow {
                Layout.preferredWidth: Style.space(230)
                Layout.fillHeight: true
                edges: root.snapshot.blocking
                foreground: root.foreground
                accent: root.accent
                urgent: root.urgent
                muted: root.muted
                fontFamily: root.fontFamily
            }
        }

        ColumnLayout {
            visible: !root.minimized && root.connected && root.expanded
            Layout.fillWidth: true
            spacing: Style.space(3)

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "MVCC SURFACE"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.8
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: Number(root.snapshot.mvcc.deadTuples || 0).toLocaleString() + " estimated dead tuples"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }
            }

            Repeater {
                model: root.snapshot.relations.slice(0, 3)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: modelData.schema + "." + modelData.relation
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideMiddle
                    }
                    Text {
                        text: root.relationDetail(modelData)
                        color: Number(modelData.deadPercent || 0) >= 25 ? root.warning : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideLeft
                    }
                }
            }
        }

        Text {
            visible: !root.minimized && root.connected && root.expanded
            Layout.fillWidth: true
            text: "MEMORY ONLY · "
                + (root.snapshot.capabilities.fullStats ? "FULL VISIBILITY" : "LIMITED VISIBILITY")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: refreshWash
        anchors.fill: parent
        z: 10
        radius: root.radius
        color: root.accent
        opacity: 0
        enabled: false
    }

    SequentialAnimation {
        id: refreshPulse
        NumberAnimation {
            target: refreshWash
            property: "opacity"
            from: 0.045
            to: 0
            duration: 420
            easing.type: Easing.OutCubic
        }
    }

    Timer {
        id: windowControlReset
        interval: 120
        repeat: false
        onTriggered: root.windowControlActive = false
    }
}
