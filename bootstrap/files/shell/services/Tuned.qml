pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Power profiles, from tuned.
//
// The active profile is read rather than remembered: tuned-adm is the only
// thing that knows which profile survived a reboot, and a menu that lies about
// the current setting is worse than one that admits it does not know.
//
// Until the package is installed, tuned-adm is missing and this stays empty —
// the chip says "unknown" rather than inventing a profile.
Singleton {
    id: root

    /** The profiles the chip cycles, in order. */
    readonly property var profiles: ["balanced", "powersave", "throughput-performance"]

    property string active: ""

    readonly property string label: active === "" ? "unknown" : active

    function cycle(): void {
        const next = profiles[(profiles.indexOf(active) + 1) % profiles.length]
        apply(next)
    }

    function apply(name): void {
        applyProc.command = ["tuned-adm", "profile", name]
        applyProc.running = true
    }

    Process {
        id: applyProc
        running: false
        // The daemon may take a moment to settle, so the read is not immediate.
        onExited: read.running = true
    }

    Process {
        id: read
        command: ["tuned-adm", "active"]
        running: true

        stdout: SplitParser {
            // "Current active profile: balanced"
            onRead: (line) => root.active = line.replace(/^Current active profile:\s*/, "").trim()
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: read.running = true
    }
}
