import "../core"
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../services"

// The focused window: its own icon, then a bold grey title cut to
// Theme.titleChars.
//
// "Active" and "focused" are the same window in niri, so this follows the
// focused window *on this bar's output* rather than the machine's focused one:
// with a bar per monitor, the other monitor's window is not this strip's news.
// The whole pill disappears when there is no title to show, which is what an
// empty workspace should look like.
Pill {
    // The pill, not `parent`: children of a Pill are reparented into its inner
    // row, so `parent` here is that row and carries none of these properties.
    id: root

    /** The output this bar belongs to; see Bar.qml. */
    required property string outputName

    visible: Niri.windowTitleOn(root.outputName) !== ""

    /**
     * niri reports an app id like `org.wezfurlong.wezterm`, which is exactly
     * what a desktop entry is keyed by, so the icon comes from the entry rather
     * than from a private map of ids to glyphs that would rot.
     */
    readonly property string appId: Niri.windowAppIdOn(root.outputName)
    readonly property var entry: root.appId ? DesktopEntries.byId(root.appId) : null
    readonly property string iconSource: entry?.icon ? Quickshell.iconPath(entry.icon, true) : ""

    readonly property string title: Niri.windowTitleOn(root.outputName)
    readonly property string shortTitle: root.title.length > Theme.titleChars
        ? `${root.title.slice(0, Theme.titleChars - 1)}…`
        : root.title

    Image {
        visible: root.iconSource !== ""
        source: root.iconSource

        // Layout.preferred*, not width/height. Inside a Layout, an item's
        // width and height are managed by the layout, which asks for its
        // implicit size instead — and an Image's implicit size is the size of
        // its source, so `width: 16` was quietly ignored and the icon was laid
        // out at sourceSize, dragging the whole pill taller with it.
        Layout.preferredWidth: Theme.iconSize
        Layout.preferredHeight: Theme.iconSize
        // Loaded at 2x so it stays crisp on a scaled output, then drawn small.
        sourceSize.width: Theme.iconSize * 2
        sourceSize.height: Theme.iconSize * 2
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
