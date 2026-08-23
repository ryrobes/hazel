import Quickshell
import QtQuick
import "Hazel" as Hazel

ShellRoot {
    Hazel.HazelController {
        id: controller
        active: false
    }

    Timer {
        interval: 0
        running: true
        onTriggered: {
            controller.enqueueRequest("details");
            controller.enqueueRequest("summary");
            controller.enqueueRequest("details");
            var first = controller.takeQueuedRequest("");
            var second = controller.takeQueuedRequest("");
            var third = controller.takeQueuedRequest("none");
            var passed = first === "summary" && second === "details" && third === "none";
            console.log(passed ? "HAZEL_QUEUE_OK" : "HAZEL_QUEUE_FAIL", first, second, third);
            Qt.quit();
        }
    }
}
