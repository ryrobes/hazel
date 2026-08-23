import Quickshell
import QtQuick
import "Hazel" as Hazel

ShellRoot {
    Hazel.HazelController {
        id: controller
        settings: ({
            "configured": true,
            "activeProfileId": "sqlserver-qml-test",
            "profileName": "SQL Server QML test",
            "engine": "sqlserver",
            "host": "127.0.0.1",
            "port": 55437,
            "database": "hazel",
            "user": "hazel",
            "sslMode": "disable",
            "rememberPassword": false,
            "closedRefreshSec": 2,
            "openRefreshSec": 1,
            "historyHours": 1
        })
        active: true
        panelOpen: true

        onStateChanged: {
            if (state.connected && state.engine === "sqlserver" && state.sequence >= 1) {
                console.log("HAZEL_SQLSERVER_QML_OK", state.identity.version, state.maintenance.surfaceLabel, state.capacity.workersUsed, state.capacity.logUsed);
                Qt.quit();
            }
        }

        onErrorTextChanged: {
            if (errorText !== "")
                console.log("HAZEL_SQLSERVER_QML_ERROR", errorText);
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: {
            console.log("HAZEL_SQLSERVER_QML_TIMEOUT", controller.engineName, controller.sqlDirectory, controller.errorText);
            Qt.quit();
        }
    }
}
