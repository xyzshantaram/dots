import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

// The strip: a left cluster, a right cluster, and nothing in between.
//
// Only the strip. It used to be the window as well, with the tooltip and the
// menus drawn in the space below it — which is exactly what a surface cannot do,
// because a click that lands there belongs to whatever is behind the bar.
// Shell.qml owns the window now.
//
// The widgets are still siblings in this directory and resolve by filename.
// What the floats need from here is where the widgets are, so the ones with a
// menu hand themselves out as aliases and Shell anchors to those.
Item {
    id: bar

    /** The output this strip is drawn on; the title and the dock filter on it. */
    required property string outputName

    implicitHeight: Theme.barHeight

    property alias trayItem: tray
    property alias btItem: bt
    property alias volumeItem: volume
    property alias menuDownItem: menuDown

    /** One value for the mask, the catcher and the tooltip's visibility. */
    readonly property bool anyFloatOpen: tray.menuOpen || bt.menuOpen
        || volume.menuOpen || menuDown.menuOpen

    function closeFloats(): void {
        tray.menuOpen = false
        bt.menuOpen = false
        volume.menuOpen = false
        menuDown.menuOpen = false
    }

    RowLayout {
        anchors.fill: parent
        // A quarter of the layout gap: enough for the pills to read as
        // floating, tight enough that the bar stays slim. Equal on all four
        // sides, which a RowLayout's vertical centring then makes visible.
        anchors.margins: Theme.gap / 4
        spacing: Theme.gap

        // Left: when it is, what is focused, and what is playing.
        Clock {}
        WindowTitle { outputName: bar.outputName }
        NowPlaying {}

        // The middle is deliberately empty: the bar is a left cluster and a
        // right cluster with space between them. This spacer is what holds them
        // apart.
        Item { Layout.fillWidth: true }

        // Right, in the order they were asked for: dictation, the two metric
        // icons, the tray, then volume, connectivity, battery, and the door to
        // the control centre at the very end.
        VoxtypePill {}
        MetricIcons {}

        Tray { id: tray }
        CapsLock {}
        Volume { id: volume }
        Connectivity { id: bt }
        BatteryPill {}
        MenuDown { id: menuDown }
    }
}
