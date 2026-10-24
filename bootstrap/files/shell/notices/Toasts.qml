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
// panel.
Item {
    id: root

    required property var server

    /** Hidden while a float owns the corner the banners would land in. */
    property bool suppressed: false

    readonly property var notes: root.server?.trackedNotifications?.values ?? []

    visible: root.notes.length > 0 && !root.suppressed
    z: 7

    readonly property int inset: 8

    width: 336
    // Without this the item was 0 tall and its rectangle never reached the
    // window's input mask, so the banner could be seen and not clicked.
    height: column.implicitHeight
    x: root.parent ? root.parent.width - width - root.inset : 0
    y: Theme.barHeight + 8

    /** Newest first: the one you just received should not be at the bottom. */
    Column {
        id: column

        width: parent.width
        spacing: root.inset

        Repeater {
            model: root.notes

            // The id is the point: a Notice is its own file with its own
            // context, so `note: modelData` there is a reference error.
            Item {
                id: holder

                required property var modelData

                width: column.width
                height: notice.implicitHeight

                Notice {
                    id: notice
                    width: parent.width
                    note: holder.modelData
                }
            }
        }
    }
}
