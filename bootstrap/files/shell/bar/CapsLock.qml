import "../core"
import QtQuick
import "../services"

// Caps lock, and only while it is on.
//
// Orange, because that is what this shell's ramp means: a state you did not ask
// for and might not notice. The pill is absent the rest of the time — a light
// that is always lit says nothing.
//
// Not to be confused with this machine's CapsLock *key*, which keyd turns into
// Meta. The lock itself is on Alt+CapsLock (files/keyd/default.conf), and that
// is what this reports.
Pill {
    id: root

    visible: Keyboard.capsLock

    readonly property string tip: "Caps Lock"

    Item {
        // The glyph's own box, so the nudge below moves the ink inside it
        // without the pill moving with it.
        implicitWidth: glyph.implicitWidth
        implicitHeight: glyph.implicitHeight

        Text {
            id: glyph

            // Chosen by eye; U+F0A9B is above U+FFFF, so it is the UTF-16 pair
            // the encoder produces rather than one escape.
            text: "\uDB82\uDE9B"
            color: Theme.alert
            font.family: Theme.iconFont
            font.pixelSize: Theme.glyphSize
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.glyphNudgeX
        }
    }

    /**
     * How far this glyph's ink sits from where its box says it should.
     *
     * Per glyph, not per theme: each one is drawn differently inside its own
     * advance, and a number that centres one of them will push another off.
     */
    property int glyphNudgeX: 2

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: Hover.show(root, mapToItem(null, width / 2, 0).x)
        onExited: Hover.hide(root)
    }
}
