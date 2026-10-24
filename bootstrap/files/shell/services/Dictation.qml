pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The dictation stack, not just the daemon.
//
// Voxtype.qml carries the live state and nothing else, on purpose: the bar pill
// only ever asks "is it busy". This is the other half — what is behind the
// daemon — and it exists only because the control centre panel has room to say
// it.
Singleton {
    id: root

    readonly property string state: Voxtype.state
    readonly property string detail: Voxtype.tooltip

    /** "active", "failed", "inactive" — the NPU server behind voxtype. */
    property string server: "unknown"

    /** The same, for the unit the panel's pill toggles. */
    property string target: "unknown"

    readonly property bool running: target === "active"

    /**
     * The pill's second line: two halves of the stack in four words.
     *
     * "idle" reads as on because that is what it means here — the daemon is up
     * and waiting for the hotkey. Only "unavailable" is off.
     */
    readonly property string byline: {
        const voice = state === "unavailable" ? "voxtype off"
            : state === "recording" ? "voxtype recording"
            : "voxtype on";
        const whisper = server === "active" ? "ready"
            : server === "failed" ? "failed"
            : "off";
        return `${voice} · whisper ${whisper}`;
    }

    /**
     * Both are read in one call, because the panel wants both and two processes
     * polling the same manager is one more than it needs.
     */
    Process {
        id: unit
        command: ["sh", "-c",
            "echo server $(systemctl --user is-active flm-whisper.service); " +
            "echo target $(systemctl --user is-active dictation.target)"]
        running: true

        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("server ")) root.server = line.slice(7).trim();
                else if (line.startsWith("target ")) root.target = line.slice(7).trim();
            }
        }
    }

    /** The whole stack, the way the target wants to be driven. */
    function toggle(): void {
        toggleProc.command = [
            "systemctl", "--user",
            root.running ? "stop" : "start", "dictation.target",
        ];
        toggleProc.running = true;
    }

    Process {
        id: toggleProc
        command: []
        // The read is what updates the pill, so it is the only thing to do here.
        onExited: unit.running = true
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: unit.running = true
    }
}
