pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The networks in range, and connecting to one.
//
// NetworkManager through nmcli rather than quickshell's Networking module: the
// module exposes devices and the association, not scan results, and a list of
// what is in range is the whole job here. Net.qml still owns the bar's glyph;
// this owns the panel.
//
// Nothing polls while the panel is closed. A scan wakes the radio and costs
// battery, so `watching` is set by the control centre for as long as it is up.
Singleton {
    id: root

    /** [{ ssid, signal, secured, active }] — active first, then by signal. */
    property var networks: []

    /**
     * The SSID we are associated with, from its own cheap read.
     *
     * Not derived from `networks`: that list only exists after a scan, and a
     * scan only happens while the panel is open — so a chip bound to it was
     * blank exactly when it was shut, which is most of the time.
     */
    property string current: ""

    /**
     * The radio, read from NetworkManager rather than from the Networking
     * module: that module reports no wifi device on this machine even while one
     * is associated, so a chip bound to it stays unlit on a working connection.
     */
    property bool enabled: true

    function radio(on: boolean): void {
        radioProc.command = ["nmcli", "radio", "wifi", on ? "on" : "off"];
        radioProc.running = true;
        enabled = on;
    }

    /** The network that wants a password, "" when none does. */
    property string needsPassword: ""

    /** The network being connected or dropped, so its row can say so. */
    property string busy: ""

    /** The network the last command was for, whatever it turned out to be. */
    property string pending: ""

    property string error: ""

    /** Whether the panel is open; nothing is read while it is shut. */
    property bool watching: false
    onWatchingChanged: {
        if (watching) scan();
    }

    /** True while a scan is running — what the panel's spinner follows. */
    readonly property bool scanning: list.running

    function scan(): void {
        if (list.running) return;
        list.running = true;
    }

    /**
     * Connect, with a password if one was given.
     *
     * Without a password this is the attempt that finds out whether one is
     * needed: NetworkManager answers "Secrets were required" for a network it
     * has no key for, and that is a better test than guessing from the security
     * string, which says WPA2 for a network we already have saved.
     */
    function connect(ssid: string, password: string): void {
        busy = ssid;
        pending = ssid;
        error = "";
        connectProc.command = password === ""
            ? ["nmcli", "device", "wifi", "connect", ssid]
            : ["nmcli", "device", "wifi", "connect", ssid, "password", password];
        connectProc.running = true;
    }

    function disconnect(ssid: string): void {
        busy = ssid;
        pending = ssid;
        error = "";
        connectProc.command = ["nmcli", "connection", "down", "id", ssid];
        connectProc.running = true;
    }

    function submit(password: string): void {
        if (needsPassword === "") return;
        const ssid = needsPassword;
        needsPassword = "";
        connect(ssid, password);
    }

    function cancel(): void {
        needsPassword = "";
    }

    /**
     * Splits an nmcli -t line on colons, except the ones it backslash-escaped.
     *
     * A terse line escapes the separator, so a network called "cafe: guest"
     * arrives as "cafe\: guest" and splitting on ":" alone would cut it in two
     * and shift every field after it.
     */
    function fields(line: string): var {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                cur += line[++i];
                continue;
            }
            if (c === ":") {
                out.push(cur);
                cur = "";
                continue;
            }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    function absorb(text: string): void {
        const byName = new Map();
        for (const line of text.split("\n")) {
            if (line === "") continue;
            const f = fields(line);
            if (f.length < 4) continue;
            const [use, ssid, signal, security] = f;
            if (ssid === "") continue;

            const entry = {
                ssid: ssid,
                signal: Number(signal) || 0,
                secured: security !== "--" && security !== "",
                active: use === "*",
            };

            // One network has one row per access point. Keep the one we are on,
            // otherwise the strongest.
            const seen = byName.get(ssid);
            const better = !seen
                || (entry.active && !seen.active)
                || (entry.active === seen.active && entry.signal > seen.signal);
            if (better) byName.set(ssid, entry);
        }
        // By signal, strongest first. Being connected is not a reason to hoist a
        // network above a better one: the list is what is available, and the
        // orange border already says which one we are on.
        networks = [...byName.values()].sort((a, b) => b.signal - a.signal);
    }

    Process {
        id: list
        command: [
            "nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY",
            // --rescan yes, not the cache: opening the list is the only thing
            // that triggers a scan, so it has to be a real one.
            "device", "wifi", "list", "--rescan", "yes",
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.absorb(this.text);
                // The radio can be switched from elsewhere, so every scan
                // re-reads it rather than trusting the last value it set.
                radioState.running = true;
            }
        }
    }

    Process {
        id: active
        command: ["nmcli", "-t", "-f", "IN-USE,SSID", "device", "wifi", "list"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const line = this.text.split("\n").find((l) => l.startsWith("*"));
                root.current = line ? root.fields(line)[1] : "";
            }
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: active.running = true
    }

    Process {
        id: radioState
        command: ["nmcli", "-t", "radio", "wifi"]
        running: true

        stdout: SplitParser {
            onRead: (line) => root.enabled = line.trim() === "enabled"
        }
    }

    Process {
        id: radioProc
        command: []
        onExited: radioState.running = true
    }

    Process {
        id: connectProc
        command: []

        stderr: StdioCollector {
            id: connectError
        }

        onExited: (code) => {
            root.busy = "";
            active.running = true;
            if (code === 0) {
                root.needsPassword = "";
                root.scan();
                return;
            }
            const message = (connectError.text ?? "").trim();
            if (/Secrets were required|no secrets/i.test(message)) {
                root.needsPassword = root.pending;
                return;
            }
            root.error = message.split("\n").pop() ?? "could not connect";
        }
    }

    Timer {
        interval: 20000
        running: root.watching
        repeat: true
        onTriggered: root.scan()
    }
}
