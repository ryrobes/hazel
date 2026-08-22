import QtQuick
import Quickshell.Io

// SplitParser's normal newline mode retains an unterminated line without a
// limit. Reading raw chunks keeps its internal buffer empty; this component
// owns the only cross-chunk buffer and enforces a hard line-length ceiling.
SplitParser {
    id: root

    property int maximumLineLength: 1024 * 1024
    readonly property int bufferedLength: pending.length
    property string pending: ""
    property bool discardingOversizedLine: false

    signal line(string value)
    signal lineRejected(int limit)

    splitMarker: ""

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
        root.appendChunk(data);
    }
}
