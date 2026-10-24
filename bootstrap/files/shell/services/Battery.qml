pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// The battery, from UPower.
//
// Two readings, because that is what the device gives: a level, and the time it
// will take to empty or to fill. Which of those is worth showing depends on
// whether a cable is in, and that judgement is the only thing here.
Singleton {
    id: root

    readonly property var device: UPower.displayDevice

    readonly property bool present: device?.isPresent ?? false
    readonly property bool onBattery: UPower.onBattery ?? false

    /** 0…1. */
    readonly property real level: device?.percentage ?? 0

    /**
     * Seconds, from UPower. Zero when it has no estimate to give, which is the
     * first minute after plugging in or pulling the cable out.
     */
    readonly property real secondsToEmpty: device?.timeToEmpty ?? 0
    readonly property real secondsToFull: device?.timeToFull ?? 0

    /** "3h 20m", or empty when there is no estimate yet. */
    function duration(seconds): string {
        if (!(seconds > 0)) return ""
        const hours = Math.floor(seconds / 3600)
        const minutes = Math.round((seconds % 3600) / 60)
        return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`
    }

    readonly property string remaining: duration(secondsToEmpty)
    readonly property string toFull: duration(secondsToFull)

    /**
     * Plugged in and actually moving, rather than holding at a ceiling — a
     * machine sitting at 85% on a cable has no time-to-full to give.
     */
    readonly property bool charging: !onBattery && secondsToFull > 0

    /**
     * Warn once on the way down past nine percent, because hibernation happens
     * at five and UPower does not announce it.
     *
     * Nine rather than the critical level: the warning is only useful while
     * there is time to do something about it, and five percent is about a
     * minute of work. The flag re-arms when the machine is on a cable or back
     * above ten, so a charge that stalls and falls again warns again rather
     * than staying silent for the rest of the session.
     */
    property bool warned: false

    readonly property bool shouldWarn: onBattery && level <= 0.09 && level > 0.05

    onShouldWarnChanged: {
        if (!shouldWarn) {
            if (!onBattery || level > 0.10) warned = false
            return
        }
        if (warned) return
        warned = true
        warnProc.running = true
    }

    /**
     * notify-send rather than the shell's own server API: this process is the
     * server, and a service notifying itself would be the shell reaching into
     * its own window for something a line of shell does. Sending it the normal
     * way also means it lands in the control centre's list like anything else.
     */
    Process {
        id: warnProc
        command: [
            "notify-send", "-a", "battery", "-u", "critical",
            "Battery low", "System will hibernate at 5%",
        ]
        running: false
    }
}
