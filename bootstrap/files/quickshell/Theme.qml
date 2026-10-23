pragma Singleton

import Quickshell
import QtQuick

// The ends of the two ramps, plus the surfaces and type they sit on.
//
// The two hues come from the palette images in /tmp/escrow: purple is what
// nothing needs from you, orange is what does. The ramp between them lives in
// Situation.qml — this file only holds the extremes, so changing the palette is
// changing two colours here rather than a hundred widgets.
//
// Everything is a token with a name for its role, never a literal in a widget.
Singleton {
    // --- the calm end ------------------------------------------------------
    // From purples.jpeg: the deep violet, the accent already in use as niri's
    // focus ring, and two lights above it.
    readonly property color calmDeep:   "#584BB4"
    readonly property color calm:       "#7561C9"
    readonly property color calmBright: "#916AEC"
    readonly property color calmPale:   "#AB9BD8"

    // --- the attention end -------------------------------------------------
    // From oranges.jpg: burnt, orange, amber, then a yellow that is nearly a
    // warning on its own.
    readonly property color alertDeep:   "#C1553A"
    readonly property color alert:       "#E05F2A"
    readonly property color alertBright: "#EC9E24"
    readonly property color alertHot:    "#F8D035"

    // --- fixed metric colours ---------------------------------------------
    // CPU, memory and disk are deliberately outside the calm/alert ramp: they
    // are three things to read at a glance, and a shared ramp would make them
    // three shades of the same answer. Blue, white and yellow as asked.
    readonly property color metricCpu:  "#F8D035"
    readonly property color metricMem:  "#F0EFF3"
    readonly property color metricDisk: "#584BB4"

    // --- recording --------------------------------------------------------
    // The one red in the shell, for the recording dot. Red rather than the
    // alert orange because "we are recording you" is not on the attention
    // scale, it is a different statement.
    readonly property color recording: "#E5484D"

    // --- surfaces ---------------------------------------------------------
    // Dark purple pills. Kept opaque on purpose: niri composites no blur, so a
    // translucent surface over a wallpaper reads as muddy rather than soft.
    readonly property color surface:       "#1A1024"
    readonly property color surfacePill:   "#241634"
    readonly property color surfaceRaised: "#2E1C42"
    readonly property color border:        "#3A2850"

    // --- text -------------------------------------------------------------
    readonly property color text:      "#F0EFF3"
    readonly property color textMuted: "#B099B7"
    readonly property color textDim:   "#8A7C93"

    // --- type -------------------------------------------------------------
    // Inter for words: it is the system sans-serif, and the bar has to match
    // what applications render. The nerd font only for glyphs, since that is
    // the only family installed that carries them.
    readonly property string fontFamily: "Inter"
    readonly property string iconFont:   "FantasqueSansM Nerd Font Mono"
    readonly property int fontSize:      13
    readonly property int fontSizeSmall: 11
    readonly property int fontSizeLarge: 15

    // --- geometry ---------------------------------------------------------
    // Gaps are 8 in niri's layout; the bar uses the same number so its margin
    // against the screen edge and the gap between windows agree.
    readonly property int gap:        8
    // Tall enough for the largest pill plus its padding: the clock sets the
    // floor at fontSizeLarge, and the half-gap margins above and below take 8.
    // At 32 the pills were clipped along their bottom edge.
    readonly property int barHeight:  36
    readonly property int pillRadius: 999   // fully rounded
    readonly property int radiusCard: 18
    readonly property int radiusSmall: 12

    // --- truncation -------------------------------------------------------
    /// The window title is cut to this many characters before an ellipsis.
    readonly property int titleChars: 30
    /// How long a colour takes to walk the ramp. Slow on purpose: the whole
    /// point is that a change in state is noticed, not that it flashes.
    readonly property int blendMs: 800
}
