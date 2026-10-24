pragma Singleton

import Quickshell

// One tooltip for the whole bar.
//
// Widgets announce themselves here rather than each growing a popup of its own.
// Two reasons, both structural: a Pill hands its children to an inner row, so a
// widget has no way to draw outside its own bounds, and the bar strip is 34px
// tall with no room below it. So the Bar owns a single tooltip in the headroom
// under the strip, and a widget only has to say "me, and where I am".
//
// It holds a *reference* to the hovering item rather than a copy of its text,
// which is what keeps the tooltip live: the Bar's binding reads `provider.tip`,
// so a value that changes while the pointer rests still updates the popup.
Singleton {
    /** The widget whose tooltip should be shown, or null. */
    property var provider: null

    /** Where to point it, in window coordinates. */
    property real anchorX: 0

    function show(item, x): void {
        provider = item
        anchorX = x
    }

    /** Only the item that is currently showing may retract it. */
    function hide(item): void {
        if (provider === item) provider = null
    }

    // A widget that has no tooltip has no `tip` property at all, which is
    // undefined rather than empty — and a bar that hovers a title with no
    // tooltip should not warn once per pixel of movement.
    readonly property string text: provider?.tip ?? ""
}
