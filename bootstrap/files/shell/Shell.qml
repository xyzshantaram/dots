import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "bar"
import "core"
import "float"
import "lock"
import "notices"
import "services"

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

        /**
         * Track everything we are told about.
         *
         * A notification only appears in `trackedNotifications` — which is what
         * both the banners and the panel's list read — once it is marked
         * tracked, and Quickshell leaves that to the consumer so a server can
         * also be a pass-through. This one is the only daemon on the bus, so
         * everything that arrives here is meant to be drawn.
         */
        onNotification: (note) => {
            note.tracked = true;
        }
    }

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
        anchor: bar.menuDownItem
        server: notifications
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

    Lock { }

    Osd { }

    IpcHandler {
        target: "osd"
        function brightness(): void { OsdService.showBrightness(); }
    }

    IpcHandler {
        target: "lock"
        function open(): void { LockService.lock(); }
    }

    // niri answered its first output query: outputs are configured and the
    // shell is drawing. Keyed to niri's pid, so a config reload does not chirp
    // but a new session does.
    Connections {
        target: Niri
        function onOutputsChanged() {
            if (Niri.outputs.length === 0) return;
            cuePlayer.running = true;
        }
    }

    Process {
        id: cuePlayer
        command: ["sh", "-c",
            "m=\"$XDG_RUNTIME_DIR/niri-ready-cue-$(pgrep -x niri | head -1)\"; [ -e \"$m\" ] && exit 0; touch \"$m\"; sleep 1.5; exec paplay \"$HOME/Downloads/niri-boot-chime.mp3\""]
    }

    // Both edges of one signal. `true` is emitted before the snapshot, so
    // locking here covers the lid, the idle timer, UPower and a manual
    // `systemctl hibernate` alike — every path goes through logind. `false` is
    // the way back, and the shell is frozen with the system rather than
    // restarted, so it is still holding the lock when the machine resumes.
    Process {
        id: resumeWatch
        command: ["dbus-monitor", "--system",
            "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("boolean true")) LockService.lock();
                else if (line.includes("boolean false")) resumeDelay.restart();
            }
        }
    }

    Timer {
        id: resumeDelay
        interval: 1500
        onTriggered: resumePlayer.running = true
    }

    Process {
        id: resumePlayer
        command: ["paplay", Quickshell.env("HOME") + "/Downloads/resume-success-sound.mp3"]
    }
}
