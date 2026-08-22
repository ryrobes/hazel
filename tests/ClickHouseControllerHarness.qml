import Quickshell
import QtQuick
import "Hazel" as Hazel

ShellRoot {
    Hazel.HazelController {
        id: controller
        settings: ({
            "configured": true,
            "activeProfileId": "clickhouse-qml-test",
            "profileName": "ClickHouse QML test",
            "engine": "clickhouse",
            "host": "127.0.0.1",
            "port": 55436,
            "database": "hazel",
            "user": "default",
            "sslMode": "disable",
            "rememberPassword": false,
            "closedRefreshSec": 2,
            "openRefreshSec": 1,
            "historyHours": 1
        })
        active: true
        panelOpen: true

        onStateChanged: {
            if (state.connected && state.engine === "clickhouse" && state.sequence >= 1) {
                console.log("HAZEL_CLICKHOUSE_QML_OK", state.identity.version, state.maintenance.surfaceLabel, state.capacity.memoryUsed);
                Qt.quit();
            }
        }

        onErrorTextChanged: {
            if (errorText !== "")
                console.log("HAZEL_CLICKHOUSE_QML_ERROR", errorText);
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: {
            console.log("HAZEL_CLICKHOUSE_QML_TIMEOUT", controller.engineName, controller.sqlDirectory, controller.errorText);
            Qt.quit();
        }
    }
}
