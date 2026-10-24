pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The dictation daemon's own state, taken from the interface it publishes for
// bars rather than inferred from the process list:
//
//   voxtype status --follow --format json
//   {"text":"🎙️","alt":"idle","class":"idle",
//    "tooltip":"Voxtype ready - hold hotkey to record"}
//
// `class` is the field to switch on. This service deliberately carries *only*
// that live state. Everything else about the stack — the Whisper server unit,
// the loaded model, whether the NPU is doing the work — belongs to the control
// centre panel, and restating the state here would put the same fact in two
// places on screen.
Singleton {
    id: root

    /** idle | recording | processing | unavailable */
    property string state: "unavailable"
    /** voxtype's own wording, shown on hover. */
    property string tooltip: ""

    /**
     * Anything that is not idle or unavailable means the daemon is working —
     * held, transcribing, or whatever else it calls the step after that.
     *
     * Matching the exact name of that third state would break the moment
     * voxtype renamed it, and the distinction the bar actually draws is only
     * "quiet or busy", and then "recording or not recording" for the styling.
     */
    readonly property bool busy: state !== "idle" && state !== "unavailable"
    readonly property bool recording: state === "recording"
    readonly property bool processing: busy && !recording

    /** The Pause key does this; clicking the pill should too. */
    function toggle(): void {
        toggleProc.running = true
    }

    Process {
        id: toggleProc
        command: ["voxtype", "record", "toggle"]
        running: false
    }

    /**
     * --follow keeps this running, printing one JSON object per state change and
     * one on start, so the first line is enough to leave "unavailable" behind.
     */
    Process {
        id: followProc
        command: ["voxtype", "status", "--follow", "--format", "json"]
        running: true

        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const parsed = JSON.parse(line)
                    root.state = parsed.class ?? "unavailable"
                    root.tooltip = parsed.tooltip ?? ""
                } catch (e) {
                    // A partial line on start, or the daemon going away.
                    root.state = "unavailable"
                }
            }
        }

        onExited: root.state = "unavailable"
    }
}
