pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Keyboard lock state, read from the kernel's own LEDs.
//
// There is no other source: niri reports the layout and nothing else, and the
// LED is where the state already lives — the compositor sets it, so anything
// reading it sees the same answer the keycap light does.
//
// There are two on this machine, because keyd puts a virtual keyboard in the
// middle: input3 is the real keyboard and input21 is keyd's. Which one gets
// driven depends on which device the compositor talks to, so the answer is
// "any of them lit" rather than one device that might be the wrong one.
//
// Polled rather than watched. sysfs has no inotify, so a FileView would sit on
// a file that never reports a change; twice a second is nothing for a light.
Singleton {
    id: root

    property bool capsLock: false

    Process {
        id: sample
        command: [
            "sh", "-c",
            "for f in /sys/class/leds/*::capslock/brightness; do cat \"$f\" 2>/dev/null; done | sort -r | head -1",
        ]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.capsLock = this.text.trim() === "1"
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: sample.running = true
    }
}
