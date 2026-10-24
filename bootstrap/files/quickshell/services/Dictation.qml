pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The dictation stack, not just the daemon.
//
// Voxtype.qml carries the live state and nothing else, on purpose: the bar pill
// only ever asks "is it busy". This is the other half — what is behind the
// daemon — and it exists only because the control centre panel has room to say
// it. The panel is the one place the stack is described; putting any of it on
// the bar would put the same fact in two places on screen.
Singleton {
    id: root

    readonly property string state: Voxtype.state
    readonly property string detail: Voxtype.tooltip

    /** "active", "failed", "inactive" — the unit behind voxtype. */
    property string server: "unknown"

    /**
     * Polled rather than subscribed: a user unit's state is two words and the
     * panel is opened by hand, so a watcher for it would be machinery earning
     * nothing. The first read also lands before anyone opens the panel.
     */
    Process {
        id: unit
        command: ["systemctl", "--user", "is-active", "whisper-server.service"]
        running: true

        stdout: SplitParser {
            onRead: (line) => root.server = line.trim()
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: unit.running = true
    }

    /** One line, as the panel draws it. */
    readonly property string summary: {
        const daemon = state === "unavailable" ? "voxtype unavailable" : `voxtype ${state}`
        return `${daemon} · whisper-server ${server}`
    }
}
