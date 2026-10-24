pragma Singleton

import Quickshell
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
}
