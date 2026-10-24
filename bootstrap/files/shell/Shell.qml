import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "bar"
import "core"
import "float"

// The shell's only window, and the reason the floats work.
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // The strip, and only the strip, is space taken from the tiling area. The
    // rest of this window floats over whatever is beneath it.
    exclusiveZone: Theme.barHeight

    /** True while any float is open: what the mask and the catcher switch on. */
    readonly property bool floating: bar.anyFloatOpen

    // One server, and this is the only shell running now that the old tree is
    // gone: it owns org.freedesktop.Notifications, which is why nothing else
    // may be spawned to claim it. Quickshell outlives niri's spawn list here —
    // the panel is passed this object rather than making a second one.
    NotificationServer {
        id: notifications
    }

    mask: Region {
        x: 0
        y: 0
        width: shell.width
        height: shell.floating ? shell.height : Theme.barHeight
    }

    Bar {
        id: bar
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
        server: notifications
    }
}
