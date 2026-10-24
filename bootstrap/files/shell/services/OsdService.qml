pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The indicator for the two things with no other feedback: output volume and
// screen brightness. Both have a value and a direction, so the glyph follows
// the direction and the segments follow the value.
//
// Volume is reactive because the shell already tracks it. Brightness is not:
// the keybind runs the brightness helper, which writes the output it changed
// and its new percentage to $XDG_RUNTIME_DIR/qs-brightness, and then asks for
// the indicator by IPC. The helper owns the hardware, this owns the picture.

Singleton {
    id: root

    property bool shown: false
    property bool muted: false
    property real value: 0
    property string glyph: ""
    property string label: ""

    property real lastVolume: -1
    property real lastBrightness: -1
    property bool lastMicMuted: false

    function pop(g: string, l: string, v: real, m: bool): void {
        glyph = g;
        label = l;
        value = Math.max(0, Math.min(1, v));
        muted = m;
        shown = true;
        hide.restart();
    }

    function volumeChanged(): void {
        const v = Audio.volume;
        if (Math.abs(v - lastVolume) < 0.001 && Audio.muted === root.muted) return;
        const up = v >= lastVolume;
        lastVolume = v;
        root.pop(Audio.muted ? "\uDB81\uDF5F" : (up ? "\uDB81\uDF5D" : "\uDB81\uDF5E"), Audio.sinkName, v, Audio.muted);
    }

    function showBrightness(): void {
        probe.running = true;
    }

    function micChanged(): void {
        if (Audio.micMuted === lastMicMuted) return;
        lastMicMuted = Audio.micMuted;
        root.pop(Audio.micMuted ? "\uDB80\uDF6D" : "\uDB80\uDF6C",
            Audio.sourceName, Audio.sourceVolume, false);
    }

    Connections {
        target: Audio
        function onVolumeChanged() { root.volumeChanged(); }
        function onMutedChanged() { root.volumeChanged(); }
        function onMicMutedChanged() { root.micChanged(); }
    }

    Timer {
        id: hide
        interval: 1400
        onTriggered: root.shown = false
    }

    Process {
        id: probe
        command: ["sh", "-c", "cat \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/qs-brightness\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [dev, pct] = text.trim().split(" ");
                if (dev === undefined || pct === undefined) return;
                const v = Number(pct) / 100;
                const up = v >= root.lastBrightness;
                root.lastBrightness = v;
                root.pop(up ? "\uDB80\uDCE0" : "\uDB80\uDCDE", dev, v, false);
            }
        }
    }
}
