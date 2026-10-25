pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// niri integration, written by hand because there was nothing to adapt.
//
// Quickshell 0.3.2 ships Hyprland, I3, X11 and WindowManager modules and no
// niri one, and niri exposes no i3 IPC socket — `$I3SOCK` is unset, and
// /run/user/$UID holds only niri.wayland-*.sock and wayland-*.sock. So state
// comes from `niri msg --json`, and change notification from
// `niri msg event-stream`.
//
// The event stream is not JSON. It prints niri's Rust debug formatting:
//
//   Workspaces changed: [Workspace { id: 1, idx: 1, name: None, ... }]
//
// Parsing that would tie the bar to a debug-printing format that upstream is
// free to change between releases, so it is used as a *trigger* only: a line
// mentioning something tracked here causes a re-query of the JSON, which is the
// interface niri documents and the one the CLI is written against.
Singleton {
    id: root

    /** Raw `niri msg --json` results, in niri's own field names. */
    property var workspaces: []
    property var windows: []
    property var outputs: []

    /** The focused workspace, which is what names the focused output. */
    readonly property var focusedWorkspace: workspaces.find((w) => w.is_focused) ?? null

    /**
     * The output under the pointer.
     *
     * niri's `focus-follows-mouse` focuses the workspace and the output when
     * the pointer enters them, so the focused workspace's output is the one the
     * pointer is on. The OSD and the banners key off this.
     */
    readonly property string focusedOutputName: focusedWorkspace?.output ?? ""

    /**
     * Connector name for a window.
     *
     * A window does not carry its output — the JSON has workspace_id and stops
     * there — so the workspace table is the join. Every per-output widget goes
     * through this; there is no other place the answer exists.
     */
    function outputOf(window): string {
        if (!window) return "";
        const ws = root.workspaces.find((w) => w.id === window.workspace_id);
        return ws?.output ?? "";
    }

    /** Windows on one output, in niri's order. */
    function windowsOn(outputName): var {
        if (!outputName) return [];
        const ids = {};
        for (let i = 0; i < root.workspaces.length; i++) {
            if (root.workspaces[i].output === outputName) ids[root.workspaces[i].id] = true;
        }
        return root.windows.filter((w) => ids[w.workspace_id] === true);
    }

    function focusedWindowOn(outputName): var {
        return root.windows.find((w) => w.is_focused && root.outputOf(w) === outputName) ?? null;
    }

    function windowTitleOn(outputName): string {
        return root.focusedWindowOn(outputName)?.title ?? "";
    }

    function windowAppIdOn(outputName): string {
        return root.focusedWindowOn(outputName)?.app_id ?? "";
    }

    function outputByName(name): var {
        return root.outputs.find((o) => o.name === name) ?? null;
    }

    /**
     * Runs `niri msg action ...`, taking the arguments as an array.
     *
     * An array rather than rest parameters because QML's JS engine is not
     * every-engine: `...args` inside the list below is a parse error, and a
     * parse error anywhere in this file takes the whole shell down with a
     * message about the file that imported it rather than about this line.
     *
     * The command is rebuilt wholesale rather than bound to a property, because
     * a binding would still hold the previous value on the tick that `running`
     * is set.
     */
    function action(args): void {
        actionProc.command = ["niri", "msg", "action"].concat(args ?? [])
        actionProc.running = true
    }

    function refresh(): void {
        workspacesProc.running = true
        windowsProc.running = true
        outputsProc.running = true
    }

    Component.onCompleted: refresh()

    Process {
        id: workspacesProc
        command: ["niri", "msg", "--json", "workspaces"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.workspaces = JSON.parse(this.text)
                } catch (e) {
                    console.warn("Niri: workspaces did not parse:", e)
                }
            }
        }
    }

    Process {
        id: windowsProc
        command: ["niri", "msg", "--json", "windows"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.windows = JSON.parse(this.text)
                } catch (e) {
                    console.warn("Niri: windows did not parse:", e)
                }
            }
        }
    }

    Process {
        id: outputsProc
        command: ["niri", "msg", "--json", "outputs"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // Keyed by connector name rather than an array, and each
                    // value already carries its own `name`, so the values are
                    // the list. Spreading them into a new object would be a
                    // parse error — see action() below.
                    root.outputs = Object.values(JSON.parse(this.text))
                } catch (e) {
                    console.warn("Niri: outputs did not parse:", e)
                }
            }
        }
    }

    Process {
        id: actionProc
        command: []
        running: false
    }

    /**
     * One long-lived stream, used only to know *when* to re-query. Lines not
     * worth an update — anything about the keyboard, the overview and so on —
     * are still filtered out to keep this cheap.
     */
    Process {
        id: eventsProc
        command: ["niri", "msg", "event-stream"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                // "Window focus changed" is its own event, separate from
                // "Windows changed", and it is the one that moves the title and
                // the workspace highlight. The stream emits no "Outputs
                // changed"; outputs are read once at startup and are static
                // enough for that.
                if (line.includes("Workspaces") || line.includes("Windows")
                    || line.includes("focus") || line.includes("Overview"))
                    root.refresh()
            }
        }
    }
}
