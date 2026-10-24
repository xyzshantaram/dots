pragma Singleton

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

// The bluetooth adapter and the devices we know about.
//
// Named BT, not Bluetooth, on purpose: the module below exports a singleton
// called `Bluetooth`, and a service of the same name would shadow it inside
// this very file — `Bluetooth.defaultAdapter` would resolve to this singleton
// and find nothing.
//
// Reads come from quickshell's service. The writes go through bluetoothctl, for
// the same reason the volume mute goes through wpctl: it is the path that cannot
// disagree with the daemon, and it is what you would type by hand to check.
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false

    /**
     * Devices worth listing: paired, or connected. A device that is neither is
     * one we cannot connect to without pairing first, which is not what this
     * menu is for.
     */
    readonly property var known: {
        if (!adapter) return []
        return adapter.devices.values
            .filter((d) => d.bonded || d.connected)
            .sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0))
    }

    readonly property int connectedCount: known.filter((d) => d.connected).length

    function toggleEnabled(): void {
        powerProc.running = true
    }

    /** Connect a device, or disconnect it if it already is. */
    function toggleDevice(device): void {
        deviceProc.command = [
            "bluetoothctl",
            device.connected ? "disconnect" : "connect",
            device.address,
        ]
        deviceProc.running = true
    }

    Process {
        id: powerProc
        command: ["bluetoothctl", "power", "toggle"]
        running: false
    }

    Process {
        id: deviceProc
        command: []
        running: false
    }
}
