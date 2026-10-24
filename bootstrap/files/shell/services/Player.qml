pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Now playing, off MPRIS.
//
// Quickshell talks to the players over D-Bus itself, so playerctl is never in
// the path: this reads the interface the players already publish.
//
// One player at a time — the first one actually playing, or failing that the
// first one that exists. Two album covers in a bar is a jukebox, not a status
// line, and picking is what the control centre is for.
Singleton {
    id: root

    readonly property var players: Mpris.players.values

    readonly property var player: players.find((p) => p.isPlaying) ?? players[0] ?? null
    readonly property bool present: player !== null

    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string art: player?.trackArtUrl ?? ""
    readonly property bool playing: player?.isPlaying ?? false

    /** Seconds, and whether either of them means anything. */
    readonly property real position: player?.position ?? 0
    readonly property real length: player?.length ?? 0
    readonly property bool seekable: (player?.canSeek ?? false) && length > 0

    /**
     * The clock the panel draws, which is ours rather than the player's.
     *
     * MPRIS publishes Position when something happens, not once a second —
     * Spotify reports it at track changes and seeks and otherwise leaves it
     * alone — so a bar bound straight to it sits still. The timer advances
     * between reports, and a report that is ahead wins, so it never drifts far.
     */
    property real elapsed: 0

    onPositionChanged: elapsed = position
    onTitleChanged: elapsed = position
    onPresentChanged: elapsed = position

    Timer {
        interval: 1000
        running: root.playing
        repeat: true
        onTriggered: root.elapsed = root.position > root.elapsed
            ? root.position
            : (root.length > 0
                ? Math.min(root.length, root.elapsed + 1)
                : root.elapsed + 1)
    }

    function togglePlaying(): void {
        if (player?.canTogglePlaying) player.togglePlaying()
    }

    function next(): void {
        if (player?.canGoNext) player.next()
    }

    function previous(): void {
        if (player?.canGoPrevious) player.previous()
    }

    /**
     * Seek takes an offset in seconds, not a position, so the caller converts.
     * Guarded because a player that cannot seek drops the request silently
     * otherwise, and a slider that moves without the music following is worse
     * than one that does not move.
     */
    function seekTo(seconds): void {
        if (!seekable) return
        player.seek(seconds - position)
    }
}
