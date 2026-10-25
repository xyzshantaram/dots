import QtQuick
import Quickshell
import Quickshell.Wayland
import "bar"
import "core"
import "dock"
import "float"
import "lock"
import "notices"
import "services"

// The shell's window, one per output, and the reason the floats work.
//
// shell.qml builds one of these for every entry in Quickshell.screens, passing
// the screen in, so the bar, the dock, the catcher and the floats belong to a
// monitor rather than to whichever one Quickshell calls primary.
//
// A layer-shell surface receives input only inside its own geometry. The old
// bar was the strip plus 200px of headroom, so a click on the desktop never
// arrived and no menu could close itself — the pointer was over a different
// surface entirely.
//
// So this is one full-screen transparent surface:
//
//   * the strip reserves Theme.barHeight through exclusiveZone, so windows
//     still tile below it;
//   * the mask is the switch — the strip normally, the whole screen while
//     anything is floating. That is what turns a click anywhere into an event
//     this window can see;
//   * a catcher under the floats closes them on click. It and the floats are
//     Items in one window, so z-order is ordinary QML and not the undefined
//     ordering of two layer-shell surfaces.
//
// The strip is not a sibling window any more either, which means the floats can
// reach bar widgets with mapToItem: no cross-window mapping anywhere.
PanelWindow {
    id: shell

    /**
     * The screen this window belongs to.
     *
     * Variants sets this on each instance (see shell.qml); the binding below is
     * what puts the window on that output. Declared here because Variants
     * assigns a property on the delegate object rather than exposing a scope.
     */
    property var modelData

    screen: shell.modelData

    /**
     * The connector name of the output this window was built for.
     *
     * shell.qml instantiates one of these per screen and passes the screen in,
     * and niri and Quickshell agree on connector names, so this is what the
     * bar, the dock and the OSD filter on.
     */
    readonly property string outputName: shell.screen ? shell.screen.name : ""

    anchors {
        top: true
        left: true
        right: true
    }

    // Full height, but anchored at the top only. A layer surface anchored to
    // both top and bottom has no defined exclusive zone — there is no single
    // edge to reserve from — so niri reserved nothing and windows tiled under
    // the bar. Height is what makes this window big; the anchor is what makes
    // the reservation meaningful.
    implicitHeight: shell.screen ? shell.screen.height : 1080

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    // On-demand here: the panels are their own layer surfaces and ask for the
    // keyboard themselves, so this window only takes it for a focused text
    // field in the banner.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // The strip, and only the strip, is space taken from the tiling area. The
    // rest of this window floats over whatever is beneath it.
    exclusiveZone: Theme.barHeight

    /** True while any float is open: what the mask and the catcher switch on. */
    readonly property bool floating: bar.anyFloatOpen

    /**
     * The strip, plus whatever is hanging under it.
     *
     * A union of rectangles, not a whole-screen switch. Opening the screen for
     * banners seemed reasonable until a notification arrived with no timeout:
     * the mask stayed full-screen, the shell took every click and every key, and
     * the machine had to be used from a TTY. The banner's own rectangle is
     * enough for it to be clicked; the screen is only opened when a float really
     * does need the whole surface.
     */
    mask: Region {
        x: 0
        y: 0
        width: shell.width
        height: Theme.barHeight

        Region {
            x: 0
            y: 0
            width: shell.floating ? shell.width : 0
            height: shell.floating ? shell.height : 0
        }

        Region {
            x: toasts.x
            y: toasts.y
            width: toasts.visible ? toasts.width : 0
            height: toasts.visible ? toasts.height : 0
        }
    }

    Bar {
        id: bar
        outputName: shell.outputName
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
    }

    // Under the floats, over the strip: clicking anywhere that is not a float
    // closes whatever is open.
    MouseArea {
        anchors.fill: parent
        visible: shell.floating
        z: 5
        onClicked: bar.closeFloats()
    }

    // Notification banners, at the control centre's top edge and stacking down.
    Toasts {
        id: toasts
        server: Notifications.server
        // Only the output the pointer is on takes a new banner. Once taken it
        // stays there, even if focus moves: see Toasts.qml.
        active: shell.outputName === Niri.focusedOutputName
        // A menu and a banner compete for the same corner; the menu wins.
        suppressed: shell.floating
    }

    // The dock is its own bottom-anchored surface on this output, so it needs
    // nothing from this window but whether a float is open.
    Dock {
        id: dock
        outputName: shell.outputName
        suppressed: shell.floating
    }

    // The one tooltip, drawn under the strip for whichever widget asked. Hidden
    // while anything is floating, including on the widget that opened it: a
    // tooltip on top of its own menu is the worst case of the two.
    Item {
        id: tip

        visible: Hover.text !== "" && !shell.floating
        z: 6

        width: label.implicitWidth + 16
        height: label.implicitHeight + 10
        y: Theme.barHeight + 4
        x: Math.max(4, Math.min(shell.width - width - 4, Hover.anchorX - width / 2))

        Rectangle {
            anchors.fill: parent
            radius: 7
            color: Theme.surfaceRaised
            border.width: 1
            border.color: Theme.border
        }

        Text {
            id: label
            anchors.centerIn: parent
            text: Hover.text
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // ---- the floats
    //
    // The two that live in this window already, given their widget so position
    // and open state come from the one place that knows them.
    TrayMenu {
        id: trayMenu
        tray: bar.trayItem
    }

    BluetoothMenu {
        id: btMenu
        bt: bar.btItem
    }

    // The two still PopupWindows, anchored to their widgets. They move in with
    // everything else in the next pass; until then PopupAnchor is what makes a
    // separate window work, and both widgets are in this window's strip.
    Mixer {
        id: mixer
        anchorItem: bar.volumeItem
        visible: bar.volumeItem.menuOpen
    }

    ControlCentre {
        id: centre
        anchorItem: bar.menuDownItem
        visible: bar.menuDownItem.menuOpen
        server: Notifications.server
        // Its own window now, so it has to be told which screen it belongs to;
        // PanelWindow otherwise picks the primary.
        screen: shell.screen
    }

    Osd {
        active: shell.outputName === Niri.focusedOutputName
    }
}
