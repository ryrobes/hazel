import QtQuick
import Quickshell.Io

// Raw-chunk mode owns the cross-chunk buffer and enforces a hard ceiling.
// For Hazel's structurally bounded JSON rows, newline mode can instead keep
// raw UTF-8 bytes intact until Quickshell decodes the complete line.
SplitParser {
    id: root

    property int maximumLineLength: 1024 * 1024
    // Database result rows are structurally bounded by Hazel's SELECTs. Let
    // Quickshell retain their raw bytes through the newline so UTF-8 code
    // points cannot be split across arbitrary process read chunks.
    property bool preserveUtf8Lines: false
    readonly property int bufferedLength: pending.length
    property string pending: ""
    property bool discardingOversizedLine: false

    signal line(string value)
    signal lineRejected(int limit)

    splitMarker: preserveUtf8Lines ? "\n" : ""

    function reset() {
        pending = "";
        discardingOversizedLine = false;
    }

    function appendSegment(segment, terminated) {
        if (!discardingOversizedLine) {
            if (pending.length + segment.length > maximumLineLength) {
                pending = "";
                discardingOversizedLine = true;
                lineRejected(maximumLineLength);
            } else {
                pending += segment;
            }
        }

        if (!terminated)
            return ;

        if (!discardingOversizedLine) {
            var value = pending;
            if (value.endsWith("\r"))
                value = value.slice(0, -1);
            line(value);
        }
        pending = "";
        discardingOversizedLine = false;
    }

    function appendChunk(data) {
        var chunk = String(data || "");
        var start = 0;
        var newline = chunk.indexOf("\n", start);
        while (newline >= 0) {
            appendSegment(chunk.slice(start, newline), true);
            start = newline + 1;
            newline = chunk.indexOf("\n", start);
        }
        if (start < chunk.length)
            appendSegment(chunk.slice(start), false);
    }

    function finish() {
        if (pending.length > 0 && !discardingOversizedLine)
            line(pending.endsWith("\r") ? pending.slice(0, -1) : pending);
        reset();
    }

    onRead: function(data) {
        if (root.preserveUtf8Lines)
            root.appendSegment(String(data || ""), true);
        else
            root.appendChunk(data);
    }
}
