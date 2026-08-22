import Quickshell
import Quickshell.Io
import QtQuick
import "Hazel" as Hazel

ShellRoot {
    property int rejectedLines: 0
    property bool recoveredLine: false
    property bool failed: false

    Process {
        id: hostileProducer
        command: ["bash", "-c", "printf '%080d' 0; printf '\\nok\\n'"]

        stdout: Hazel.BoundedLineReader {
            id: boundedReader
            maximumLineLength: 64
            onLineRejected: function(limit) {
                rejectedLines += 1;
                if (limit !== 64 || bufferedLength > 64)
                    failed = true;
            }
            onLine: function(value) {
                if (value === "ok")
                    recoveredLine = true;
            }
        }

        onExited: function(exitCode) {
            boundedReader.finish();
            if (exitCode !== 0 || rejectedLines !== 1 || !recoveredLine || boundedReader.bufferedLength > 64)
                failed = true;
            console.log(failed ? "HAZEL_BOUNDED_READER_FAIL" : "HAZEL_BOUNDED_READER_OK");
            Qt.quit();
        }
    }

    Component.onCompleted: hostileProducer.running = true

    Timer {
        interval: 3000
        running: true
        onTriggered: {
            console.log("HAZEL_BOUNDED_READER_TIMEOUT");
            Qt.quit();
        }
    }
}
