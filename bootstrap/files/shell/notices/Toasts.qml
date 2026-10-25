import QtQuick
import ".."
import "../core"
import "../components"

// Notification banners, hanging under the strip at the panel's right edge.
//
// Positioned from the window rather than from a bar widget: mapping the
// menu-down chevron's corner gave x = 0, which put the first banner at -310 and
// off the left of the screen. The right edge is what these line up with, and
// the window knows where that is.
//
// They are Items in the shell's own window rather than another PopupWindow,
// which is what lets them sit in ordinary z-order against the catcher and the
// panel. There is one of these per output now, and only the one under the
// pointer takes a new banner: a note that arrives while this screen is focused
// stays on this screen, even after the pointer moves away.
Item {
    id: root

    required property var server

    /** Whether this is the output under the pointer; see Shell.qml. */
    required property bool active

    /** Hidden while a float owns the corner the banners would land in. */
    property bool suppressed: false

    readonly property var tracked: root.server?.trackedNotifications?.values ?? []

    /**
     * Ids whose banner has already run its ten seconds.
     *
     * Without this, re-reading the bus on the next change would put an expired
     * banner straight back up, because the notification itself is still
     * tracked — the panel's list is meant to keep it.
     */
    property var spent: ({})

    /** The banners this output has taken, newest first. */
    ListModel { id: shown }

    visible: shown.count > 0 && !root.suppressed
    z: 7

    readonly property int inset: 8

    width: 336
    // Without this the item was 0 tall and its rectangle never reached the
    // window's input mask, so the banner could be seen and not clicked.
    height: column.implicitHeight
    x: root.parent ? root.parent.width - width - root.inset : 0
    y: Theme.barHeight + 8

    function noteById(id): var {
        for (let i = 0; i < root.tracked.length; i++) {
            if (root.tracked[i].id === id) return root.tracked[i]
        }
        return null
    }

    function remove(id): void {
        for (let i = 0; i < shown.count; i++) {
            if (shown.get(i).noteId === id) {
                shown.remove(i)
                return
            }
        }
    }

    /**
     * Reconcile the banners against the bus.
     *
     * Closed notifications lose their banner, expired ones are not revived, and
     * if this is the focused output every new note gets one.
     */
    function take(): void {
        const live = root.tracked

        for (const key in root.spent) {
            const id = Number(key)
            if (!live.some((n) => n.id === id)) delete root.spent[key]
        }

        for (let i = shown.count - 1; i >= 0; i--) {
            const id = shown.get(i).noteId
            if (!live.some((n) => n.id === id)) shown.remove(i)
        }

        if (!root.active) return

        // Oldest first, each inserted at the top, so the newest ends up first.
        for (let i = 0; i < live.length; i++) {
            const note = live[i]
            if (root.spent[note.id]) continue
            let held = false
            for (let j = 0; j < shown.count; j++) {
                if (shown.get(j).noteId === note.id) { held = true; break }
            }
            if (!held) shown.insert(0, { noteId: note.id })
        }
    }

    /** Ten seconds are up: record it, fade it out, then forget it. */
    function expire(id): void {
        root.spent[id] = true
        root.remove(id)
    }

    Component.onCompleted: root.take()
    onActiveChanged: root.take()

    Connections {
        target: root.server ? root.server.trackedNotifications : null
        function onValuesChanged() { root.take() }
    }

    Column {
        id: column

        width: parent.width
        spacing: root.inset

        Repeater {
            model: shown

            // A ListModel row rather than the notification object: the notice
            // is looked up by id, so a banner cannot hold a dead object.
            Item {
                id: holder

                required property int index
                required property int noteId

                readonly property var note: root.noteById(holder.noteId)

                width: column.width
                height: notice.implicitHeight

                // The fade. Two timers: one for the ten seconds, one for the
                // 200 ms the opacity animation takes, so the row leaves after
                // it has finished fading rather than before.
                property bool leaving: false
                opacity: holder.leaving ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                }

                Timer {
                    interval: 10000
                    running: true
                    onTriggered: holder.leaving = true
                }

                Timer {
                    interval: 210
                    running: holder.leaving
                    onTriggered: root.expire(holder.noteId)
                }

                Notice {
                    id: notice
                    width: parent.width
                    note: holder.note
                }
            }
        }
    }
}
