import Quickshell
import Quickshell.Io
import QtQuick
import "Hazel" as Hazel

ShellRoot {
    property bool received: false
    property bool failed: false

    Process {
        id: splitUtf8Producer
        command: ["bash", "-c", "printf '\\342'; sleep 0.05; printf '\\202'; sleep 0.05; printf '\\254uro\\n'"]

        stdout: Hazel.BoundedLineReader {
            id: lineReader
            preserveUtf8Lines: true
            maximumLineLength: 64
            onLine: function(value) {
                received = true;
                if (value !== "€uro")
                    failed = true;
            }
            onLineRejected: function(limit) { failed = true; }
        }

        onExited: function(exitCode) {
            lineReader.finish();
            if (exitCode !== 0 || !received)
                failed = true;
            console.log(failed ? "HAZEL_UTF8_READER_FAIL" : "HAZEL_UTF8_READER_OK");
            Qt.quit();
        }
    }

    Component.onCompleted: splitUtf8Producer.running = true

    Timer {
        interval: 3000
        running: true
        onTriggered: {
            console.log("HAZEL_UTF8_READER_TIMEOUT");
            Qt.quit();
        }
    }
}
