import QtQuick
import QtQuick.Layouts
import Quickshell
import "services"

// The focused window: its own icon, then a bold grey title cut to
// Theme.titleChars.
//
// "Active" and "focused" are the same window in niri, so this follows
// Niri.focusedWindow rather than keeping a second notion of which window
// matters. The whole pill disappears when there is no title to show, which is
// what an empty workspace should look like.
Pill {
    // The pill, not `parent`: children of a Pill are reparented into its inner
    // row, so `parent` here is that row and carries none of these properties.
    id: root

    visible: Niri.windowTitle !== ""

    /**
     * niri reports an app id like `org.wezfurlong.wezterm`, which is exactly
     * what a desktop entry is keyed by, so the icon comes from the entry rather
     * than from a private map of ids to glyphs that would rot.
     */
    readonly property var entry: Niri.windowAppId ? DesktopEntries.byId(Niri.windowAppId) : null
    readonly property string iconSource: entry?.icon ? Quickshell.iconPath(entry.icon, true) : ""

    readonly property string shortTitle: Niri.windowTitle.length > Theme.titleChars
        ? `${Niri.windowTitle.slice(0, Theme.titleChars - 1)}…`
        : Niri.windowTitle

    Image {
        visible: root.iconSource !== ""
        source: root.iconSource
        sourceSize.width: 16
        sourceSize.height: 16
        fillMode: Image.PreserveAspectFit
        // Its own colours, as asked: a monochrome icon is how an app is
        // recognised, and tinting it would take that away.
        smooth: true
    }

    Text {
        text: root.shortTitle
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        elide: Text.ElideRight
    }
}
