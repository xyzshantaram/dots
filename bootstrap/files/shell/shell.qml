// The shell.
//
//   qs -p ~/.config/shell    run it
//   qs -p ~/.config/shell    run it again after an edit, replacing the instance
//
// This is now the only config. The tree it was built beside is gone, and
// 120-quickshell.ts deletes any ~/.config/quickshell it finds — a bare `qs`
// reads that path, and it would load a bar with no click-catcher.
//
// One window per output. Shell.qml is a single full-screen surface, so it is
// instantiated by a Variants over Quickshell.screens with its screen set: the
// bar, the dock, the floats and the catcher then belong to that monitor rather
// than to whichever one Quickshell calls primary.
//
// Everything that must exist exactly once lives here, outside the Variants:
// the notification server is a singleton under services/, the lock covers every
// output by itself, and the two IPC targets and the session cues would
// otherwise be duplicated per monitor. QML resolves a sibling component by
// filename with no import, and the singletons in core/, bar/ and float/ are
// declared in their own qmldir — so a directory states what it contains, which
// is the thing a flat tree stops doing once there are twenty files in it.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "lock"
import "services"

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            // Shell.qml declares `modelData` and binds its screen to it:
            // Variants sets that property on each instance.
            Shell { }
        }
    }

    // Not per screen: WlSessionLock instantiates its surface once for each
    // output, which is what makes one instance cover all of them.
    Lock { }

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
    // but a new session does. Once, not once per output.
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
