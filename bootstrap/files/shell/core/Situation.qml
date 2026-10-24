pragma Singleton

import Quickshell
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

    /**
     * The pill surface, walking from its resting purple to the alert orange.
     *
     * The same 0…1 score as blend(), with the same meaning, but applied to the
     * background instead of a glyph: the widget itself carries the temperature
     * and the text on it stays white and grey.
     */
    function surface(score): color {
        const t = Math.max(0, Math.min(1, score))
        const a = Theme.surfacePill
        const b = Theme.alert
        return Qt.rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            1)
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
    /**
     * Battery. Full is calm, empty is attention — the direction is the same
     * whether the machine is plugged in or not, so a charging battery calms
     * down as it fills and a draining one warms up as it empties.
     *
     * Written the right way round this time: the ramp runs up from 11% to 55%,
     * and the score is its inverse, so 6% reads as attention rather than as
     * perfect calm.
     */
    function batteryScore(percent): real {
        return 1 - ramp(percent, 11, 55)
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

    /**
     * Load, for anything measured in percent where high is the bad end.
     *
     * The defaults are this machine's working range, not a generic one. A busy
     * day sits around 30-40% of memory and CPU rarely pushes past the same, so
     * a 70/90 ramp would hold both icons white through the whole day and say
     * nothing at all. 20 to 50 spreads the range that actually happens across
     * the middle of the blend.
     *
     * Disk is the odd one out: it lives at whatever it lives at and climbs
     * slowly, so a threshold tuned to CPU will find it permanently tinted.
     */
    function loadScore(percent, warn = 20, critical = 50): real {
        return ramp(percent, warn, critical)
    }

    // --- the evening clock -------------------------------------------------

    /**
     * Evening runs from 22:00 to 09:00, and the clock walks from white at the
     * start of it to orange at the end. Outside that window it is white.
     *
     * One rule and no state: the colour is a function of the wall clock, so a
     * shell restarted at 03:00 looks exactly like one that has been running
     * since 22:00, and there is nothing to reset.
     */
    readonly property int eveningStartHour: 22
    readonly property int eveningEndHour: 9

    /**
     * How the fade is weighted, as an exponent on the progress.
     *
     * 0.5 is a square root: the colour is most of the way to orange by the time
     * the night is half over, rather than halfway between the two. 1.0 restores
     * the even fade; lower gets orange sooner.
     */
    readonly property real eveningWeight: 0.5

    /** 0 at 22:00, 1 at 09:00, and flat white for the rest of the day. */
    function clockTint(now): real {
        const hour = now.getHours()
        const afterMidnight = hour < eveningEndHour
        if (!afterMidnight && hour < eveningStartHour) return 0

        // The window straddles midnight, so the base is either tonight's 22:00
        // or last night's. Eleven hours either way, which is why the length is
        // computed rather than written down twice.
        const from = new Date(now)
        if (afterMidnight) from.setDate(from.getDate() - 1)
        from.setHours(eveningStartHour, 0, 0, 0)

        const hours = 24 - eveningStartHour + eveningEndHour
        return ramp(now.getTime(), from.getTime(), from.getTime() + hours * 3600 * 1000)
    }

    /**
     * White to the alert orange, by an already-computed 0…1 score.
     *
     * Shared, so the evening clock and a hot CPU come out the same family of
     * colour rather than two blends that drift apart the first time one of them
     * is adjusted.
     */
    function warmth(t): color {
        const a = Theme.text
        const b = Theme.alert
        return Qt.rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            1)
    }

    /**
     * The colour for a load given as 0…1, white at rest and orange under load.
     *
     * Takes a fraction where loadScore wants a percentage, because every
     * sampler in the shell measures in fractions; converting at the edge here
     * beats a caller that forgets and reads as permanently calm.
     */
    function loadColour(value): color {
        return warmth(loadScore(value * 100))
    }
}
