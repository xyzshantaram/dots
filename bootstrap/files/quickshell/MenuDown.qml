import QtQuick
import "services"

// The control centre's door: the chevron at the far right of the bar.
//
// It is a Pill like everything else, so it sits in the same rhythm as the
// widgets beside it even though it opens something rather than reporting
// something.
Pill {
    id: root

    property bool menuOpen: false

    /** Per glyph, by eye: see the note in Tray.qml. */
    property int glyphNudgeX: 2

    Item {
        implicitWidth: glyph.implicitWidth
        implicitHeight: glyph.implicitHeight

        Text {
            id: glyph

            // nf-md-menu_down, U+F035D. Reads as "there is more below this",
            // which is what the panel is.
            text: "\uDB80\uDF5D"

            color: root.menuOpen ? Theme.calm : Theme.text
            font.family: Theme.iconFont
            font.pixelSize: Theme.glyphSize
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.glyphNudgeX
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: Hover.show(root, mapToItem(null, width / 2, 0).x)
        onExited: Hover.hide(root)
        onClicked: root.menuOpen = !root.menuOpen
    }
}
