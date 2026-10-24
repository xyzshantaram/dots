pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// CPU, memory and disk, in percentages.
//
// One process every couple of seconds, not a stream: none of these change fast
// enough to be worth a watcher, and a bar that adds pollers is a bar that costs
// battery. The shell this borrows its layout from ran three separate processes
// for these same three numbers, which is one of the things this exists to not
// do.
//
// The percentages are computed here rather than in the shell line, because CPU
// is a *difference*: /proc/stat reports counters since boot, so a percentage
// only exists relative to the previous reading. Keeping that state in QML means
// the sample command stays a pure read, and can be run by hand to see exactly
// what the bar sees.
Singleton {
    id: root

    /** All 0..1, except memoryGb which is GiB of memory in use. */
    property real cpu: 0
    property real memory: 0
    property real memoryGb: 0
    property real disk: 0

    // Previous /proc/stat counters, and whether there is a previous pair to
    // difference against. The first sample has nothing to compare with, so it
    // reports 0 rather than an average since boot.
    property real prevTotal: -1
    property real prevIdle: -1

    /**
     * `cpu <total> <idle>` from /proc/stat, `mem <fraction> <gib>` from
     * /proc/meminfo, `disk <percent>` from df. Labelled, because parsing by
     * position would silently swap two of them the day one is added.
     *
     * meminfo reports kilobytes, so the second number is the same subtraction
     * divided by 1048576 — GiB, not GB, because that is what the kernel's
     * numbers actually are.
     */
    Process {
        id: sample
        command: [
            "sh", "-c",
            "awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; print \"cpu\", t, $5+$6}' /proc/stat; " +
            "awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf \"mem %.4f %.2f\\n\", (t-a)/t, (t-a)/1048576}' /proc/meminfo; " +
            "df --output=pcent / | tail -1 | tr -dc '0-9' | sed 's/^/disk /;s/$/\\n/'",
        ]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.apply(this.text)
        }
    }

    function apply(text): void {
        for (const line of text.trim().split("\n")) {
            const [key, ...rest] = line.trim().split(/\s+/)
            if (key === "cpu") {
                const total = Number(rest[0])
                const idle = Number(rest[1])
                if (root.prevTotal >= 0 && total > root.prevTotal) {
                    const busy = 1 - (idle - root.prevIdle) / (total - root.prevTotal)
                    root.cpu = Math.max(0, Math.min(1, busy))
                }
                root.prevTotal = total
                root.prevIdle = idle
            } else if (key === "mem") {
                root.memory = Math.max(0, Math.min(1, Number(rest[0])))
                root.memoryGb = Number(rest[1])
            } else if (key === "disk") {
                root.disk = Math.max(0, Math.min(1, Number(rest[0]) / 100))
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: sample.running = true
    }
}
