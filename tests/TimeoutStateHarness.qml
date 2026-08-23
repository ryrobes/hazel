import Quickshell
import QtQuick
import "Hazel" as Hazel
import "Hazel/Model.js" as Model

ShellRoot {
    property bool passed: false

    Hazel.HazelController {
        id: controller
        active: false
        panelOpen: false
        settings: ({
            "configured": true,
            "activeProfileId": "timeout-test",
            "profileName": "Timeout test",
            "engine": "postgresql",
            "host": "127.0.0.1",
            "port": 5432,
            "database": "postgres",
            "user": "hazel",
            "sslMode": "disable",
            "rememberPassword": false,
            "closedRefreshSec": 60
        })
        onStateChanged: {
            if (state.connected === true && state.stale === true && state.severity === "warning") {
                passed = true;
                console.log("HAZEL_TIMEOUT_STATE_OK", state.statusLabel);
                Qt.quit();
            }
        }
    }

    Component.onCompleted: {
        controller.state = Model.ingestSummary(Model.emptyState(), {
            "schema": 1,
            "kind": "summary",
            "collectedAtMs": Date.now(),
            "engine": "postgresql",
            "connections": { "used": 1, "max": 100, "active": 0 },
            "counters": {},
            "mvcc": {}
        }, 120);
        controller.active = true;
    }

    Timer {
        interval: 12000
        running: true
        onTriggered: {
            console.log("HAZEL_TIMEOUT_STATE_FAIL", controller.state.connected, controller.state.stale, controller.state.severity);
            Qt.quit();
        }
    }
}
