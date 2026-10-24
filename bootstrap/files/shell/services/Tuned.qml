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

    readonly property string label: active === "" ? "unknown" : pretty(active)

    /**
     * The daemon's slug in words.
     *
     * tuned-adm names profiles after their tuning goal — throughput-performance,
     * latency-performance — and a chip that reads "throughput-performance" is
     * reading the config file aloud. The mapping is a table rather than a rule
     * because each of these is a name, and the fallback only has to be better
     * than nothing for a profile that is not in it.
     */
    function pretty(name: string): string {
        const words = {
            "balanced": "Balanced",
            "powersave": "Power save",
            "throughput-performance": "Performance",
            "latency-performance": "Low latency",
            "network-latency": "Network latency",
            "network-throughput": "Network throughput",
            "virtual-guest": "Virtual guest",
        };
        return words[name] ?? name.replace(/-/g, " ");
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
