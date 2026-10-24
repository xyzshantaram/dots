import QtQuick
import Quickshell.Widgets
import "../core"

// The tray's dropdown: each item's icon and title, and clicking one activates
// it — the same thing a left click on an icon used to do, now with a name
// beside it so you can tell what you are clicking.
//
// It takes the widget rather than its values, because what it needs is at the
// pointer: the icon's position on screen and whether the menu should be up.
// Passing the numbers in would put the same arithmetic in two files.
Item {
    id: root

    required property var tray

    visible: root.tray.menuOpen && root.tray.items.length > 0
    z: 8

    width: 220
    height: column.implicitHeight + 12
    y: Theme.barHeight + 4
    x: Math.max(4, Math.min(root.parent.width - width - 4, root.tray.dropdownX - width / 2))

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Theme.border
    }

    Column {
        id: column
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.tray.items

            Item {
                id: entry

                required property var modelData

                width: 204
                height: 28

                IconImage {
                    id: entryIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconSize
                    height: Theme.iconSize
                    source: entry.modelData.icon
                }

                Text {
                    anchors.left: entryIcon.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.title ?? entry.modelData.id
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        entry.modelData.activate()
                        root.tray.closeMenu()
                    }
                }
            }
        }
    }

    // No hover handler: the menu opens on a click of the puzzle piece, so there
    // is nothing to keep alive while the pointer crosses the gap to it.
}
