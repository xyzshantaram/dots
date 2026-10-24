import QtQuick
import "services"

// Output volume, and the microphone only when it is actually muted.
//
// The speaker carries the level in three steps — off, quiet, loud — because a
// bar has room for a shape and not for a number. The number is in the tooltip.
// Muted is orange: that is a state you did not ask for, which is what the ramp
// is for.
//
// No microphone glyph unless the microphone is muted. A silent bar should not
// carry a permanent "the microphone is fine" light — the same reason the
// dictation pill only exists while it has something to say.
Pill {
    id: root

    // Both directions, named: which device is actually playing is the thing you
    // cannot see from a speaker glyph, and on a laptop with two microphones it
    // is the same question on the input side.
    readonly property string tip:
        `${Audio.sinkName}: ${Math.round(Audio.volume * 100)}%\n` +
        `${Audio.sourceName}: ${Math.round(Audio.sourceVolume * 100)}%`

    // Both glyphs sit in their own Item so the nudge below can move the ink
    // without moving the layout item — anchors are ignored on a layout child,
    // and a layout child is what a bare Text would be here.
    Item {
        implicitWidth: speaker.implicitWidth
        implicitHeight: speaker.implicitHeight

        Text {
            id: speaker

            text: Audio.level === "off" ? "\uf026"      // nf-fa-volume_off
                : Audio.level === "low" ? "\uf027"      // nf-fa-volume_down
                : "\uf028"                              // nf-fa-volume_up
            color: Audio.muted ? Theme.alert : Theme.text
            font.family: Theme.iconFont
            font.pixelSize: Theme.glyphSize
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            anchors.centerIn: parent
            // The muted glyph is drawn differently inside its advance from the
            // three speaker glyphs, so it does not want the same nudge.
            anchors.horizontalCenterOffset: Audio.muted ? 0 : root.glyphNudgeX
        }
    }

    Item {
        visible: Audio.micMuted
        implicitWidth: mic.implicitWidth
        implicitHeight: mic.implicitHeight

        Text {
            id: mic

            // nf-md-microphone_off, U+F036D — crossed out, because this glyph
            // only ever appears when the microphone is muted. Above U+FFFF, so
            // it is the UTF-16 pair the encoder produces.
            text: "\uDB80\uDF6D"
            color: Theme.alert
            font.family: Theme.iconFont
            font.pixelSize: Theme.glyphSize
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.glyphNudgeX
        }
    }

    /** Per glyph, by eye: see the note in Tray.qml. */
    property int glyphNudgeX: 2

    /** Click opens the mixer; muting lives in there now. */
    property bool menuOpen: false

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        // Left opens the mixer, middle mutes without opening anything — the
        // gesture you want mid-sentence, when a panel would be in the way.
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) Audio.toggleMute()
            else root.menuOpen = !root.menuOpen
        }
        onEntered: Hover.show(root, mapToItem(null, width / 2, 0).x)
        onExited: Hover.hide(root)
    }
}
