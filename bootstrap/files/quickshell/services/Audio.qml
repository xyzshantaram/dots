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
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false

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

    readonly property var sinks: nodesWhere((n) => n.isSink && !n.isStream)
    readonly property var sources: nodesWhere((n) => !n.isSink && !n.isStream)

    /**
     * Applications producing audio.
     *
     * Filtered by media.class rather than by isSink, because the meaning of
     * isSink for a stream varies by stream; the class string does not.
     */
    readonly property var streams: nodesWhere((n) =>
        n.isStream && (n.properties?.["media.class"] ?? "") === "Stream/Output/Audio")

    /**
     * Nodes have to be subscribed to before their properties mean anything.
     *
     * Until one is tracked, `defaultAudioSink` exists as an object with a
     * volume of zero and a mute of false — which reads as a perfectly silent
     * machine rather than as a node nobody has asked about. Streams are tracked
     * for their properties too, which is where the application name lives.
     */
    PwObjectTracker {
        objects: {
            const tracked = [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
            for (const node of Pipewire.nodes.values) {
                if (node && node.audio && node.isStream) tracked.push(node)
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
