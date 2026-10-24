pragma Singleton

import Quickshell
import Quickshell.Networking
import Quickshell.Io
import QtQuick

// The network, as one glyph.
//
// Named Net, not Networking: the module below exports a singleton called
// `Networking`, and a service of that name would shadow it inside its own file.
//
// The obvious fields lie, so the distinctions here are measured. `address` on a
// device is its MAC, present even with the cable out, and `connected` is true
// for that same device; `state` is what separates them, 0 disconnected and 2
// connected. `type` is 1 for wifi, 2 for wired. Signal strength is not on the
// device and there is no networks collection to ask, so it comes from
// /proc/net/wireless, as do the IPv4 addresses from ip(8).
Singleton {
    id: root

    readonly property var connected: Networking.devices.values.filter((d) =>
        String(d.state) === "2")

    readonly property var wired: connected.find((d) => String(d.type) === "2") ?? null
    readonly property bool useEthernet: wired !== null
    readonly property bool online: connected.length > 0

    /** Connected and not by cable, which is what makes this a wireless link. */
    readonly property bool wireless: online && !useEthernet

    /** Link quality, 0…1, straight from the kernel. */
    property real linkQuality: 0

    /**
     * A wireless link with no quality reading yet reads as strong rather than
     * absent. The glyph's job is to say "connected", and a slashed icon beside
     * a working connection is a lie in the wrong direction. It is also what
     * made the bar show offline for the second it takes the sample to land.
     */
    readonly property real signal: wireless ? Math.max(linkQuality, 0.75) : 0

    property var addresses: []

    Process {
        id: sample
        command: [
            "sh", "-c",
            // Quality is labelled because it may not be there at all, and
            // position-based parsing would then read the first address as a
            // number. From nmcli rather than /proc/net/wireless: this driver
            // reports no wireless extensions, so the kernel file has no quality
            // line, while NetworkManager always knows. nmcli gives a
            // percentage, which is what the divisor below expects.
            "nmcli -t -f IN-USE,SIGNAL device wifi list 2>/dev/null " +
            "| awk -F: '$1 == \"*\" {print \"q\", $2; exit}'; " +
            "ip -4 -br addr show scope global | awk '{print $3}' | cut -d/ -f1",
        ]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter((l) => l.length > 0)
                const quality = lines.find((l) => l.startsWith("q "))
                if (quality) {
                    const n = Number(quality.slice(2))
                    root.linkQuality = Number.isFinite(n) ? Math.min(1, n / 100) : 0
                }
                root.addresses = lines.filter((l) => /^\d+\.\d+\.\d+\.\d+$/.test(l))
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: sample.running = true
    }
}
