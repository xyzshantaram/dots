import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// The bar: one layer-shell surface per screen, a left cluster, a right cluster
// and nothing in between.
//
// Variants over Quickshell.screens is what puts the same bar on every monitor.
// Without it a bare PanelWindow attaches to one arbitrary screen, which on a
// laptop is usually the right one by luck and never is once a second monitor
// appears.
//
// The window is much taller than the strip. The strip reserves space and takes
// input; everything below it is where the tooltip and the tray's dropdown are
// drawn, and the mask is what stops that height taking clicks meant for
// whatever is underneath.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window

            required property var modelData
            screen: window.modelData

            anchors {
                top: true
                left: true
                right: true
            }

            implicitHeight: Theme.barHeight + Theme.menuHeadroom
            // The window is the full strip but paints only the pills, so the
            // wallpaper shows through everywhere else.
            color: "transparent"
            // Reserve only the strip, so windows tile below the bar and the
            // popups can float over whatever is there.
            exclusiveZone: Theme.barHeight

            // The strip takes input, and so does the dropdown while it is up.
            // Everything else in the window is click-through.
            mask: Region {
                x: 0
                y: 0
                width: window.width
                height: Theme.barHeight

                // The geometry is given twice on purpose: `item` is what the
                // region actually measures, while the explicit bindings are
                // what notice the panel moving to a different widget and ask
                // for a rebuild.
                Region {
                    item: trayMenu.visible ? trayMenu : null
                    x: trayMenu.x
                    y: trayMenu.y
                    width: trayMenu.visible ? trayMenu.width : 0
                    height: trayMenu.visible ? trayMenu.height : 0
                }
            }

            RowLayout {
                anchors.fill: parent
                // A quarter of the layout gap: enough for the pills to read as
                // floating, tight enough that the bar stays slim. Equal on all
                // four sides, which is what a RowLayout's vertical centring of
                // each pill then makes visible.
                //
                // The bottom margin is overridden to the whole headroom, so the
                // row occupies the strip and the leftover height below it
                // belongs to the popups.
                anchors.margins: Theme.gap / 4
                anchors.bottomMargin: Theme.menuHeadroom
                spacing: Theme.gap

                // Left: when it is, what is focused, and what is playing.
                Clock {}
                WindowTitle {}

                // The middle is deliberately empty: the bar is a left cluster
                // and a right cluster with space between them. This spacer is
                // what holds them apart.
                Item { Layout.fillWidth: true }

                // Right, in the order they were asked for: dictation, the two
                // metric icons, the tray, then volume, bluetooth, network and
                // battery.
                VoxtypePill {}
                Metrics {}

                // Named, because the bar draws its dropdown.
                Tray { id: tray }
            }

            // The one tooltip, drawn under the strip at whichever widget asked
            // for it. Clamped to the window so a widget near an edge does not
            // push half of it off screen.
            Item {
                id: tooltip

                // Hidden while the tray menu is open: both would sit in the same
                // place, and the menu is the one the pointer is heading for.
                visible: Hover.text !== "" && !tray.menuOpen
                z: 10

                width: label.implicitWidth + 16
                height: label.implicitHeight + 10
                y: Theme.barHeight + 4
                x: Math.max(4, Math.min(window.width - width - 4, Hover.anchorX - width / 2))

                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.border
                }

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: Hover.text
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            // The tray's dropdown: each item's icon and title, and clicking one
            // activates it — the same thing a left click on an icon used to do,
            // now with a name beside it so you can tell what you are clicking.
            Item {
                id: trayMenu

                visible: tray.menuOpen && tray.items.length > 0
                z: 11

                width: 220
                height: column.implicitHeight + 12
                y: Theme.barHeight + 4
                x: Math.max(4, Math.min(window.width - width - 4, tray.dropdownX - width / 2))

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
                        model: tray.items

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
                                    tray.closeMenu()
                                }
                            }
                        }
                    }
                }

                // No hover handler here any more. The menu opens on a click of
                // the puzzle piece, so there is nothing to keep alive while the
                // pointer crosses the gap to it.
            }
        }
    }
}
