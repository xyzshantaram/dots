import QtQuick
import "services"

// Bluetooth, as one glyph that opens a menu on click.
//
// The colour carries the state in three steps, since the bar has room for a
// shape and not for a sentence: white when something is connected, muted when
// the radio is up but idle, dim when it is off.
//
// Click opens the menu below the bar — the same arrangement as the tray, and
// drawn by the bar for the same reason: a Pill hands its children to an inner
// row, so a widget cannot draw a panel of its own.
Pill {
    id: root

    visible: BT.available

    readonly property string tip: !BT.enabled
        ? "Bluetooth off"
        : BT.connectedCount === 0
            ? "Bluetooth: not connected"
            : `Bluetooth: ${BT.connectedCount} connected`

    property bool menuOpen: false
    property real dropdownX: 0

    Item {
        implicitWidth: glyph.implicitWidth
        implicitHeight: glyph.implicitHeight

        Text {
            id: glyph

            text: "\uf293"   // nf-fa-bluetooth
            color: !BT.enabled ? Theme.textDim
                : BT.connectedCount > 0 ? Theme.text
                : Theme.textMuted
            font.family: Theme.iconFont
            font.pixelSize: Theme.glyphSize
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.glyphNudgeX
        }
    }

    /** Per glyph, by eye: see the note in Tray.qml. */
    property int glyphNudgeX: 0

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
        onEntered: Hover.show(root, mapToItem(null, width / 2, 0).x)
        onExited: Hover.hide(root)
    }

    function toggle(): void {
        if (menuOpen) {
            menuOpen = false
            return
        }
        dropdownX = mapToItem(null, width / 2, 0).x
        menuOpen = true
    }

    function closeMenu(): void {
        menuOpen = false
    }
}
