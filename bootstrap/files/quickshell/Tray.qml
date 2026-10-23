import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

// The system tray, as one puzzle piece that opens its contents on click.
//
// On click rather than hover: a hover menu has to be reached across a gap, and
// the pointer crossing that gap leaves the icon, which would close the menu
// again. A click does not have that problem.
//
// The dropdown is drawn by the bar, not here, for the same reason the tooltip
// is: a Pill hands its children to an inner row, so a widget has nowhere to put
// a panel of its own. This widget only says whether it is open, what is in it,
// and where to point.
Pill {
    id: root

    visible: items.length > 0

    /** Read by the bar to build the dropdown. */
    readonly property var items: SystemTray.items.values

    property bool menuOpen: false
    /** Where the dropdown should be centred, in window coordinates. */
    property real dropdownX: 0

    readonly property string tip: "System tray"

    Item {
        // The glyph's own box, so Theme.glyphOffsetX can move the ink inside it
        // without the pill moving with it.
        implicitWidth: glyph.implicitWidth
        implicitHeight: glyph.implicitHeight

        Text {
            id: glyph

            // Material Design Icons' puzzle-outline, U+F0A66. Above U+FFFF, so
            // QML needs it as a UTF-16 surrogate pair rather than one escape —
            // the pair is what the UTF-16 encoder produces for the codepoint,
            // not arithmetic worked out by hand.
            text: "\uDB82\uDE66"
            color: Theme.text
            font.family: Theme.iconFont
            font.pixelSize: Theme.glyphSize
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: Theme.glyphOffsetX
        }
    }

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

    /** Called by the bar once an entry has been activated. */
    function closeMenu(): void {
        menuOpen = false
    }
}
