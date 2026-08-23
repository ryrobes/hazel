import Quickshell
import QtQuick
import "Hazel" as Hazel

ShellRoot {
    property bool replacementApplied: false

    Hazel.HazelController {
        id: controller
        settings: ({
            "configured": true,
            "activeProfileId": "credential-race-test",
            "profileName": "Credential race test",
            "engine": "postgresql",
            "host": "127.0.0.1",
            "port": 1,
            "database": "postgres",
            "user": "postgres",
            "sslMode": "disable",
            "rememberPassword": true,
            "closedRefreshSec": 60,
            "openRefreshSec": 10,
            "historyHours": 1
        })
        active: true

        onKeyringBusyChanged: {
            if (keyringBusy && !replacementApplied)
                replacementTimer.restart();
        }
    }

    Timer {
        id: replacementTimer
        interval: 40
        repeat: false
        onTriggered: {
            replacementApplied = true;
            controller.applyCredential("fresh-session-password", false, false);
            assertionTimer.restart();
        }
    }

    Timer {
        id: assertionTimer
        interval: 1300
        repeat: false
        onTriggered: {
            var passed = controller.sessionPassword === "fresh-session-password"
                && controller.credentialsReady
                && controller.secretLookupGeneration === -1;
            console.log(passed ? "HAZEL_CREDENTIAL_RACE_OK" : "HAZEL_CREDENTIAL_RACE_FAIL",
                controller.sessionPassword, controller.credentialsReady, controller.secretLookupGeneration);
            Qt.quit();
        }
    }

    Timer {
        interval: 4000
        running: true
        onTriggered: {
            console.log("HAZEL_CREDENTIAL_RACE_TIMEOUT");
            Qt.quit();
        }
    }
}
