pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Audio state, from PipeWire.
//
// The two directions are deliberately asymmetric. The output level is something
// you set and forget, so the bar shows a volume, a mute and three steps of
// glyph. The microphone only gets its mute on the bar: what matters there is
// whether it is open, and its level lives in the mixer.
//
// Writes go through the service, not through wpctl. The reference mixer this
// borrows from does the same, and it is the path that keeps the value you see
// and the value the daemon has in one place rather than two.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    /** 0…1, as PipeWire reports it. */
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property real sourceVolume: source?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false

    /**
     * What to call a node, for a tooltip or a list row. Description first: it is
     * the human one, and nickname and name are the fallbacks PipeWire offers.
     */
    function label(node, fallback): string {
        return node?.description || node?.nickname || node?.name || fallback
    }

    readonly property string sinkName: label(sink, "output")
    readonly property string sourceName: label(source, "input")

    /** Three glyphs' worth of resolution: off, quiet, loud. */
    readonly property string level: muted ? "off" : volume < 0.34 ? "low" : "high"

    /** Every node, filtered. Sinks, sources and the streams applications open. */
    function nodesWhere(predicate): var {
        const out = []
        for (const node of Pipewire.nodes.values) {
            if (node && node.audio && predicate(node)) out.push(node)
        }
        return out
    }

    /**
     * The class strings, not isSink, decide what a node is.
     *
     * Checking "isSink and not a stream" also matched the video nodes the
     * screenshot portal leaves behind, one per capture, named after the output
     * they came from — eDP-1 several times over, with no description between
     * them. media.class is the one field that says what a node actually is.
     */
    function nodeClass(node): string {
        return node?.properties?.["media.class"] ?? ""
    }

    readonly property var sinks: nodesWhere((n) =>
        nodeClass(n).startsWith("Audio/Sink"))

    readonly property var sources: nodesWhere((n) =>
        nodeClass(n).startsWith("Audio/Source"))

    /**
     * Applications producing audio.
     *
     * For a stream the class is what distinguishes an application's output from
     * a capture; isSink means different things for different streams.
     */
    readonly property var streams: nodesWhere((n) =>
        nodeClass(n) === "Stream/Output/Audio")

    /**
     * Nodes have to be subscribed to before their properties mean anything.
     *
     * Until one is tracked, it exists as an object with a volume of zero, a
     * mute of false and — the part that shows — no description or name at all.
     * That is what put blank rows in the mixer: only the defaults and the
     * streams were tracked, so every other device listed itself as nothing.
     *
     * Everything with an audio interface is tracked, which is every node the
     * mixer can show.
     */
    PwObjectTracker {
        objects: {
            const tracked = []
            for (const node of Pipewire.nodes.values) {
                if (node && node.audio) tracked.push(node)
            }
            return tracked
        }
    }

    function toggleMute(): void {
        if (sink?.audio) sink.audio.muted = !sink.audio.muted
    }

    /** Make a sink or source the default one. */
    function makeDefault(node, isSink): void {
        if (!node) return
        if (isSink) Pipewire.preferredDefaultAudioSink = node
        else Pipewire.preferredDefaultAudioSource = node
    }
}
