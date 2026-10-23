pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// One question, asked everywhere: does this need attention?
//
// Zero is purple and means nothing to see. One is orange and means look at me.
// Anything in the shell that has a colour at all takes it from here, so the bar
// reads as one system rather than a row of widgets that each picked a hue.
//
// The blend walks the hue *forward* from purple to orange — about 252° to 377°
// — which travels through violet, magenta and red. A straight RGB interpolation
// between the two ends would cut the corner through a muddy brown the moment
// either end moved, and the forward walk is the shorter arc here anyway.
Singleton {
    // Named, because the evening-clock block below references its own
    // properties and its file watcher by it.
    id: root
    readonly property color calm:  Theme.calm
    readonly property color alert: Theme.alert

    /// Hue of an end, in degrees, and the forward distance between them.
    readonly property real calmHue: Theme.calm.hsvHue * 360
    readonly property real alertHue: {
        let d = Theme.alert.hsvHue * 360 - Theme.calm.hsvHue * 360
        if (d < 0) d += 360
        return d
    }

    /**
     * The colour for an attention score: 0 calm, 1 alert, anything between a
     * real colour on the ramp rather than a snapped state.
     */
    function blend(score): color {
        const t = Math.max(0, Math.min(1, score))
        const hue = (calmHue + alertHue * t) / 360
        // Saturation and value are interpolated too, so the middle of the ramp
        // stays as saturated as its ends instead of washing out.
        const sat = Theme.calm.hsvSaturation + (Theme.alert.hsvSaturation - Theme.calm.hsvSaturation) * t
        const val = Theme.calm.hsvValue + (Theme.alert.hsvValue - Theme.calm.hsvValue) * t
        return Qt.hsva(hue % 1, sat, val, 1)
    }

    /** A value's position between two bounds, clamped. */
    function ramp(value, from, to): real {
        if (to === from) return 0
        return Math.max(0, Math.min(1, (value - from) / (to - from)))
    }

    /**
     * Battery. Full is calm, empty is attention — the direction is the same
     * whether the machine is plugged in or not, so a charging battery calms
     * down as it fills and a draining one warms up as it empties. The caller
     * decides which of the two it is showing.
     */
    function batteryScore(percent): real {
        return ramp(percent, 11, 55)
    }

    /**
     * The microphone. Muted is the attention case, because a muted mic is the
     * one thing you cannot hear and cannot see. Recording is *not* on this
     * scale: it gets the recording red, which is a statement rather than a
     * level.
     */
    function micScore(muted): real {
        return muted ? 1 : 0
    }

    /** Load, for anything measured in percent where high is the bad end. */
    function loadScore(percent, warn = 70, critical = 90): real {
        return ramp(percent, warn, critical)
    }

    // --- the evening clock -------------------------------------------------

    /**
     * Where the clock's warmth counts from: 19:00 today, or yesterday's if it
     * is already past midnight.
     *
     * Without that second case, opening the shell at 01:00 would put the base
     * six hours in the future, the score at zero, and the clock back to white —
     * a jump backwards rather than a ramp.
     */
    property date clockBase: defaultClockBase()

    function defaultClockBase(): date {
        const d = new Date()
        d.setHours(19, 0, 0, 0)
        if (d.getTime() > Date.now()) d.setDate(d.getDate() - 1)
        return d
    }

    /** Hours from the base to full warmth. */
    readonly property int clockRampHours: 6

    /** 0 at the base, 1 six hours later, and flat either side. */
    function clockTint(now): real {
        const from = clockBase.getTime()
        return ramp(now.getTime(), from, from + clockRampHours * 3600 * 1000)
    }

    /**
     * White by day, walking to the alert orange across the evening.
     *
     * Deliberately not blend(): that ramp means "needs attention" and runs
     * from purple, and the time of day should not be mistakable for a
     * notification.
     */
    function clockColour(now): color {
        const t = clockTint(now)
        const a = Theme.text
        const b = Theme.alert
        return Qt.rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            1)
    }

    /** Start the evening again from now. */
    function resetClockTint(): void {
        clockBase = new Date()
    }

    /**
     * `bun reset-clock-tint` touches this file, and that is the whole protocol:
     * a running shell sees the change and restarts the ramp. A watched file
     * rather than Quickshell's IPC because it needs nothing registered with
     * anything, which also means the command is harmless when no shell is up.
     *
     * The initial load is deliberately unhandled. A file left over from an
     * earlier reset should not decide what this session starts at — only a
     * *change* to it means anything.
     */
    readonly property string clockResetFile:
        `${Quickshell.env("HOME")}/.cache/dots/clock-tint-reset`

    FileView {
        path: root.clockResetFile
        watchChanges: true
        onFileChanged: root.resetClockTint()
    }
}
