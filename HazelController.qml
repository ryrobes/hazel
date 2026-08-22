import "Model.js" as Model
import QtQuick
import Quickshell.Io

Item {
    id: root

    property var settings: ({
    })
    property bool active: true
    property bool panelOpen: false
    property var state: Model.emptyState()
    property string errorText: ""
    property bool processReady: false
    property string pendingKind: ""
    property string queuedKind: ""
    property string summarySql: ""
    property string detailsSql: ""
    property string sessionPassword: ""
    property string pendingSecret: ""
    property bool oneShotSucceeded: false
    property int collectorTransactionsSinceSummary: 0
    property bool credentialsReady: false
    property bool passwordRemembered: false
    property bool keyringBusy: false
    property bool tunnelReady: false
    property string tunnelErrorText: ""
    readonly property bool connectionConfigured: booleanSetting("configured", false)
    readonly property string engineName: normalizedEngine(stringSetting("engine", "postgresql"))
    readonly property string engineFamily: Model.engineFamily(engineName)
    readonly property string sqlDirectory: engineName === "mariadb" ? "mariadb" : (engineFamily === "clickhouse" ? "clickhouse" : (engineFamily === "mysql" ? "mysql" : "postgres"))
    readonly property var engineDefaults: Model.engineDefaults(engineName)
    readonly property string profileId: stringSetting("activeProfileId", "default-postgres")
    readonly property string profileName: stringSetting("profileName", "Postgres")
    readonly property string hostName: stringSetting("host", "127.0.0.1")
    readonly property int port: boundedSetting("port", engineDefaults.port, 1, 65535)
    readonly property string databaseName: stringSetting("database", engineDefaults.database)
    readonly property string userName: stringSetting("user", engineDefaults.user)
    readonly property string sslMode: stringSetting("sslMode", "prefer")
    readonly property bool rememberPassword: booleanSetting("rememberPassword", true)
    readonly property bool sshEnabled: booleanSetting("sshEnabled", false)
    readonly property string sshHost: stringSetting("sshHost", "")
    readonly property int sshPort: boundedSetting("sshPort", 22, 1, 65535)
    readonly property string sshUser: stringSetting("sshUser", "")
    readonly property string sshIdentityFile: stringSetting("sshIdentityFile", "")
    readonly property int sshLocalPort: boundedSetting("sshLocalPort", 55439, 1, 65535)
    readonly property int closedRefreshMs: boundedSetting("closedRefreshSec", 5, 2, 60) * 1000
    readonly property int openRefreshMs: boundedSetting("openRefreshSec", 2, 1, 10) * 1000
    readonly property int historyHours: boundedSetting("historyHours", 6, 1, 24)
    readonly property int historyBucketMs: 5000
    readonly property var historyPolicy: ({
        "windowMs": historyHours * 60 * 60 * 1000,
        "bucketMs": historyBucketMs,
        "maxPoints": Math.ceil(historyHours * 60 * 60 * 1000 / historyBucketMs) + 2
    })
    readonly property bool queriesReady: summarySql.trim() !== "" && detailsSql.trim() !== ""
    readonly property string connectionKey: [profileId, engineName, connectionConfigured, hostName, port, databaseName, userName, sslMode, rememberPassword, sshEnabled, sshHost, sshPort, sshUser, sshIdentityFile, sshLocalPort].join("|")

    function stringSetting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        if (value === undefined || value === null)
            return fallback;

        return String(value).trim();
    }

    function normalizedEngine(value) {
        var engine = String(value || "postgresql").toLowerCase();
        return engine === "mysql" || engine === "mariadb" || engine === "percona" || engine === "clickhouse" ? engine : "postgresql";
    }

    function boundedSetting(name, fallback, minimum, maximum) {
        var value = Number(settings ? settings[name] : undefined);
        if (!isFinite(value))
            value = fallback;

        return Math.max(minimum, Math.min(maximum, Math.floor(value)));
    }

    function booleanSetting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        if (value === undefined || value === null)
            return fallback;
        if (typeof value === "string")
            return value.toLowerCase() === "true";

        return value === true;
    }

    function secretAttributes() {
        var attributes = ["application", "hazel"];
        if (engineFamily !== "postgresql")
            attributes.push("engine", engineName);
        return attributes.concat(["profile", profileId, "host", hostName || "local-socket", "port", String(port), "database", databaseName, "user", userName]);
    }

    function beginCredentialLookup() {
        if (!connectionConfigured) {
            credentialsReady = false;
            passwordRemembered = false;
            sessionPassword = "";
            return ;
        }
        if (!rememberPassword) {
            credentialsReady = true;
            passwordRemembered = false;
            sessionPassword = "";
            keyringBusy = false;
            if (active)
                ensureProcess();
            return ;
        }
        if (secretLookup.running) {
            secretLookup.running = false;
            credentialReloadTimer.restart();
            return ;
        }
        credentialsReady = false;
        passwordRemembered = false;
        sessionPassword = "";
        keyringBusy = true;
        secretLookup.command = ["secret-tool", "lookup"].concat(secretAttributes());
        secretLookup.running = true;
    }

    function applyCredential(password, remember, preserveExisting) {
        var value = String(password || "");
        if (secretLookup.running)
            secretLookup.running = false;
        credentialReloadTimer.stop();
        if (value === "" && preserveExisting) {
            credentialsReady = true;
            if (remember && sessionPassword !== "") {
                pendingSecret = sessionPassword;
                keyringBusy = true;
                secretStore.stdinEnabled = true;
                secretStore.command = ["secret-tool", "store", "--label", "Hazel · " + profileName].concat(secretAttributes());
                secretStore.running = true;
            } else if (!remember) {
                passwordRemembered = false;
                secretClear.command = ["secret-tool", "clear"].concat(secretAttributes());
                secretClear.running = true;
            }
            restartConnection();
            return ;
        }
        if (value === "" && remember) {
            beginCredentialLookup();
            return ;
        }

        credentialsReady = true;
        sessionPassword = value;
        passwordRemembered = false;
        if (remember && value !== "") {
            pendingSecret = value;
            keyringBusy = true;
            secretStore.stdinEnabled = true;
            secretStore.command = ["secret-tool", "store", "--label", "Hazel · " + profileName].concat(secretAttributes());
            secretStore.running = true;
        } else {
            secretClear.command = ["secret-tool", "clear"].concat(secretAttributes());
            secretClear.running = true;
        }
        restartConnection();
    }

    function forgetCredential() {
        sessionPassword = "";
        passwordRemembered = false;
        credentialsReady = true;
        secretClear.command = ["secret-tool", "clear"].concat(secretAttributes());
        secretClear.running = true;
        restartConnection();
    }

    function psqlCommand() {
        var command = ["env", "PGAPPNAME=hazel-monitor", "PGCONNECT_TIMEOUT=3", "PGOPTIONS=-c statement_timeout=5000", "PGSSLMODE=" + sslMode];
        if (sessionPassword !== "")
            command.push("PGPASSWORD=" + sessionPassword);
        if (sshEnabled) {
            command.push("PGHOST=127.0.0.1");
            command.push("PGPORT=" + String(sshLocalPort));
        } else {
            if (hostName !== "")
                command.push("PGHOST=" + hostName);
            if (port > 0)
                command.push("PGPORT=" + String(port));
        }

        if (databaseName !== "")
            command.push("PGDATABASE=" + databaseName);

        if (userName !== "")
            command.push("PGUSER=" + userName);

        command.push("psql", "-X", "-w", "-qAt", "--no-readline", "--set=ON_ERROR_STOP=on");
        return command;
    }

    function mysqlCommand() {
        var command = ["env"];
        if (sessionPassword !== "")
            command.push("MYSQL_PWD=" + sessionPassword);
        command.push("mariadb", "--batch", "--raw", "--skip-column-names", "--silent", "--unbuffered", "--connect-timeout=3");
        command.push(engineName === "mariadb"
            ? "--init-command=SET SESSION max_statement_time=5"
            : "--init-command=SET SESSION MAX_EXECUTION_TIME=5000");
        command.push("--host=" + (sshEnabled ? "127.0.0.1" : hostName));
        command.push("--port=" + String(sshEnabled ? sshLocalPort : port));
        command.push("--user=" + userName);
        if (databaseName !== "")
            command.push("--database=" + databaseName);
        if (sslMode === "disable")
            command.push("--skip-ssl");
        else if (sslMode === "require")
            command.push("--ssl");
        else if (sslMode === "verify-ca" || sslMode === "verify-full")
            command.push("--ssl", "--ssl-verify-server-cert");
        return command;
    }

    function clickhouseCommand(sql) {
        var command = ["env"];
        if (sessionPassword !== "")
            command.push("CLICKHOUSE_PASSWORD=" + sessionPassword);
        command.push("clickhouse", "client", "--format", "JSONEachRow", "--connect_timeout=3", "--receive_timeout=8", "--send_timeout=8", "--max_execution_time=5");
        command.push("--host=" + (sshEnabled ? "127.0.0.1" : hostName));
        command.push("--port=" + String(sshEnabled ? sshLocalPort : port));
        command.push("--user=" + userName);
        if (databaseName !== "")
            command.push("--database=" + databaseName);
        if (sslMode === "require")
            command.push("--secure", "--accept-invalid-certificate");
        else if (sslMode === "verify-ca" || sslMode === "verify-full")
            command.push("--secure");
        command.push("--query", String(sql || ""));
        return command;
    }

    function databaseCommand() {
        if (engineFamily === "mysql")
            return mysqlCommand();
        return psqlCommand();
    }

    function engineLabel() {
        return Model.engineLabel(engineName);
    }

    function sshCommand() {
        var command = ["ssh", "-N", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "-o", "ConnectTimeout=5", "-p", String(sshPort)];
        if (sshIdentityFile !== "")
            command.push("-i", sshIdentityFile);
        command.push("-L", "127.0.0.1:" + sshLocalPort + ":" + hostName + ":" + port);
        command.push(sshUser + "@" + sshHost);
        return command;
    }

    function connectionDescription() {
        var host = hostName !== "" ? hostName : "local socket";
        var database = databaseName !== "" ? databaseName : engineDefaults.database;
        var route = database + " · " + host + (hostName !== "" ? ":" + port : "");
        if (sshEnabled)
            route += " · via " + sshUser + "@" + sshHost;
        return route;
    }

    function ensureTunnel() {
        if (!active || !connectionConfigured || !sshEnabled || tunnelProc.running)
            return ;
        if (sshHost === "" || sshUser === "" || hostName === "") {
            errorText = "SSH profile is missing its host, user, or " + engineLabel() + " target";
            return ;
        }
        tunnelReady = false;
        tunnelErrorText = "";
        tunnelProc.command = sshCommand();
        tunnelProc.running = true;
    }

    function ensureProcess() {
        if (!active || !connectionConfigured || !credentialsReady || !queriesReady || psqlProc.running)
            return ;

        if (sshEnabled && !tunnelReady) {
            ensureTunnel();
            return ;
        }

        errorText = "";
        processReady = false;
        if (engineFamily === "clickhouse") {
            var next = queuedKind || "summary";
            queuedKind = "";
            request(next);
            return;
        }
        psqlProc.command = databaseCommand();
        psqlProc.running = true;
    }

    function request(kind) {
        if (!active || !queriesReady)
            return ;

        if (engineFamily === "clickhouse") {
            if (!credentialsReady) {
                queuedKind = kind === "details" ? "details" : (queuedKind || "summary");
                return;
            }
            if (sshEnabled && !tunnelReady) {
                queuedKind = kind === "details" ? "details" : (queuedKind || "summary");
                ensureTunnel();
                return;
            }
            if (psqlProc.running || pendingKind !== "") {
                if (kind === "details" || queuedKind === "")
                    queuedKind = kind;
                return;
            }
            var clickhouseSql = kind === "details" ? detailsSql : summarySql;
            pendingKind = kind;
            oneShotSucceeded = false;
            errorText = "";
            queryWatchdog.restart();
            psqlProc.command = clickhouseCommand(clickhouseSql);
            psqlProc.running = true;
            return;
        }

        if (!psqlProc.running || !processReady) {
            queuedKind = kind === "details" ? "details" : (queuedKind || "summary");
            ensureProcess();
            return ;
        }
        if (pendingKind !== "") {
            if (kind === "details" || queuedKind === "")
                queuedKind = kind;

            return ;
        }
        var sql = kind === "details" ? detailsSql : summarySql;
        pendingKind = kind;
        queryWatchdog.restart();
        psqlProc.write(sql + "\n");
    }

    function requestSummary() {
        request("summary");
    }

    function requestDetails() {
        if (panelOpen)
            request("details");

    }

    function refresh() {
        requestSummary();
        if (panelOpen)
            queuedKind = "details";

    }

    function consumeLine(line) {
        var text = String(line || "").trim();
        if (text === "" || text.charAt(0) !== "{")
            return ;

        var payload;
        try {
            payload = JSON.parse(text);
        } catch (error) {
            errorText = engineLabel() + " returned an unreadable snapshot";
            return ;
        }
        if (payload.kind === "summary") {
            payload.collectorTransactions = collectorTransactionsSinceSummary;
            state = Model.ingestSummary(state, payload, historyPolicy);
            collectorTransactionsSinceSummary = 1;
            errorText = "";
        } else if (payload.kind === "details") {
            state = Model.ingestDetails(state, payload);
            collectorTransactionsSinceSummary++;
        } else {
            return ;
        }
        pendingKind = "";
        queryWatchdog.stop();
        if (engineFamily === "clickhouse") {
            oneShotSucceeded = true;
            return;
        }
        var next = queuedKind;
        queuedKind = "";
        if (next !== "")
            Qt.callLater(function() {
            root.request(next);
        });

    }

    function consumeError(line) {
        var text = String(line || "").trim();
        if (text === "")
            return ;

        text = text.replace(/^(psql|mariadb|mysql|clickhouse(?:-client)?):\s*/i, "");
        errorText = text.length > 180 ? text.slice(0, 177) + "…" : text;
    }

    function restartConnection() {
        reconnectTimer.stop();
        retryTimer.stop();
        pendingKind = "";
        queuedKind = "summary";
        processReady = false;
        collectorTransactionsSinceSummary = 0;
        oneShotSucceeded = false;
        if (psqlProc.running)
            psqlProc.running = false;
        tunnelWarmup.stop();
        tunnelReady = false;
        if (tunnelProc.running)
            tunnelProc.running = false;

        if (active)
            reconnectTimer.restart();

    }

    width: 0
    height: 0
    visible: false
    onActiveChanged: {
        if (active) {
            credentialReloadTimer.restart();
            summaryTimer.restart();
        } else {
            credentialReloadTimer.stop();
            reconnectTimer.stop();
            retryTimer.stop();
            summaryTimer.stop();
            pendingKind = "";
            queuedKind = "";
            processReady = false;
            collectorTransactionsSinceSummary = 0;
            oneShotSucceeded = false;
            if (psqlProc.running)
                psqlProc.running = false;
            tunnelWarmup.stop();
            tunnelReady = false;
            if (tunnelProc.running)
                tunnelProc.running = false;

        }
    }
    onConnectionKeyChanged: {
        if (active) {
            state = Model.emptyState();
            oneShotSucceeded = false;
            if (psqlProc.running)
                psqlProc.running = false;
            tunnelWarmup.stop();
            tunnelReady = false;
            tunnelErrorText = "";
            if (tunnelProc.running)
                tunnelProc.running = false;
            credentialsReady = false;
            credentialReloadTimer.restart();
        }

    }
    onQueriesReadyChanged: {
        if (active && queriesReady)
            ensureProcess();

    }
    onPanelOpenChanged: {
        summaryTimer.restart();
        if (panelOpen)
            refresh();
    }
    Component.onCompleted: {
        if (active)
            credentialReloadTimer.restart();

    }

    FileView {
        path: Qt.resolvedUrl(root.sqlDirectory + "/summary.sql")
        watchChanges: true
        printErrors: false
        onLoaded: root.summarySql = text()
        onFileChanged: reload()
        onLoadFailed: root.errorText = "Hazel could not load its " + root.engineLabel() + " summary query"
    }

    FileView {
        path: Qt.resolvedUrl(root.sqlDirectory + "/details.sql")
        watchChanges: true
        printErrors: false
        onLoaded: root.detailsSql = text()
        onFileChanged: reload()
        onLoadFailed: root.errorText = "Hazel could not load its " + root.engineLabel() + " detail query"
    }

    Process {
        id: psqlProc

        stdinEnabled: true
        onStarted: {
            root.processReady = true;
            if (root.engineFamily === "clickhouse")
                return;
            var next = root.queuedKind || "summary";
            root.queuedKind = "";
            Qt.callLater(function() {
                root.request(next);
            });
        }
        onExited: function(exitCode, exitStatus) {
            root.processReady = false;
            root.pendingKind = "";
            queryWatchdog.stop();
            if (root.engineFamily === "clickhouse" && root.oneShotSucceeded) {
                root.oneShotSucceeded = false;
                var next = root.queuedKind;
                root.queuedKind = "";
                if (root.active && next !== "")
                    Qt.callLater(function() { root.request(next); });
                return;
            }
            root.collectorTransactionsSinceSummary = 0;
            if (root.active) {
                root.state = Model.markDisconnected(root.state);
                if (root.errorText === "")
                    root.errorText = exitCode === 127
                        ? (root.engineFamily === "mysql" ? "mariadb client is not installed" : (root.engineFamily === "clickhouse" ? "clickhouse client is not installed" : "psql is not installed"))
                        : root.engineLabel() + " connection closed";

                retryTimer.restart();
            }
        }

        stdout: SplitParser {
            onRead: function(line) {
                root.consumeLine(line);
            }
        }

        stderr: SplitParser {
            onRead: function(line) {
                root.consumeError(line);
            }
        }

    }

    Process {
        id: tunnelProc

        onStarted: {
            root.tunnelErrorText = "";
            tunnelWarmup.restart();
        }
        onExited: function(exitCode, exitStatus) {
            tunnelWarmup.stop();
            root.tunnelReady = false;
            if (psqlProc.running)
                psqlProc.running = false;
            if (root.active && root.sshEnabled) {
                root.state = Model.markDisconnected(root.state);
                root.errorText = root.tunnelErrorText !== "" ? root.tunnelErrorText : (exitCode === 127 ? "ssh is not installed" : "SSH tunnel closed");
                retryTimer.restart();
            }
        }

        stderr: SplitParser {
            onRead: function(line) {
                var value = String(line || "").trim();
                if (value === "")
                    return ;
                root.tunnelErrorText = value.length > 180 ? value.slice(0, 177) + "…" : value;
                root.errorText = root.tunnelErrorText;
            }
        }
    }

    Process {
        id: secretLookup

        stdout: StdioCollector {
            id: secretLookupOutput
            waitForEnd: true
        }
        onExited: function(exitCode) {
            root.keyringBusy = false;
            var value = exitCode === 0 ? String(secretLookupOutput.text || "").replace(/[\r\n]+$/, "") : "";
            root.sessionPassword = value;
            root.passwordRemembered = value !== "";
            root.credentialsReady = true;
            if (root.active)
                root.ensureProcess();
        }
    }

    Process {
        id: secretStore

        stdinEnabled: true
        onStarted: {
            write(root.pendingSecret + "\n");
            root.pendingSecret = "";
            secretStore.stdinEnabled = false;
        }
        onExited: function(exitCode) {
            root.keyringBusy = false;
            root.passwordRemembered = exitCode === 0;
            if (exitCode !== 0 && root.state.connected)
                root.errorText = "Connected, but the password could not be saved to the desktop keyring";
        }
    }

    Process {
        id: secretClear

        onExited: function(exitCode) {
            root.keyringBusy = false;
        }
    }

    Timer {
        id: credentialReloadTimer

        interval: 350
        repeat: false
        onTriggered: {
            if (root.active)
                root.beginCredentialLookup();
        }
    }

    Timer {
        id: tunnelWarmup

        interval: 350
        repeat: false
        onTriggered: {
            if (root.active && tunnelProc.running) {
                root.tunnelReady = true;
                root.errorText = "";
                root.ensureProcess();
            }
        }
    }

    Timer {
        id: summaryTimer

        interval: root.panelOpen ? root.openRefreshMs : root.closedRefreshMs
        repeat: true
        running: root.active
        onTriggered: root.panelOpen ? root.refresh() : root.requestSummary()
    }

    Timer {
        id: retryTimer

        interval: Math.max(5000, root.closedRefreshMs)
        repeat: false
        onTriggered: {
            if (root.active)
                root.ensureProcess();

        }
    }

    Timer {
        id: reconnectTimer

        interval: 100
        repeat: false
        onTriggered: {
            if (root.active)
                root.ensureProcess();

        }
    }

    Timer {
        id: queryWatchdog

        interval: 8000
        repeat: false
        onTriggered: {
            root.errorText = root.engineLabel() + " snapshot timed out";
            root.pendingKind = "";
            root.processReady = false;
            if (psqlProc.running)
                psqlProc.running = false;

        }
    }

}
