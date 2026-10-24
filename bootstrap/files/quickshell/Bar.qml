import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "services"

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

                Region {
                    item: btPanel.visible ? btPanel : null
                    x: btPanel.x
                    y: btPanel.y
                    width: btPanel.visible ? btPanel.width : 0
                    height: btPanel.visible ? btPanel.height : 0
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
                // MetricIcons, not Metrics: the service is called Metrics, and
                // importing services/ into this file would put both names in
                // scope at once. A widget named after its service only works
                // until the file needs the service.
                MetricIcons {}

                // Named, because the bar draws its dropdown.
                Tray { id: tray }
                CapsLock {}
                Volume { id: volume }
                BluetoothPill { id: bt }
            }

            // The mixer is its own popup window rather than a panel in the
            // headroom: it grows with the number of applications playing, and a
            // fixed strip has no room for that.
            Mixer {
                id: mixer
                anchorItem: volume
                visible: volume.menuOpen
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

            // The bluetooth menu: the radio on or off, then the devices we can
            // connect to. The same shape as the tray's, and the same note
            // applies — this is the second of these, and the third (network)
            // is where the chrome stops being duplicated.
            Item {
                id: btPanel

                visible: bt.menuOpen && BT.available
                z: 12

                width: 240
                height: btColumn.implicitHeight + 12
                y: Theme.barHeight + 4
                x: Math.max(4, Math.min(window.width - width - 4, bt.dropdownX - width / 2))

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSmall
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.border
                }

                Column {
                    id: btColumn
                    anchors.centerIn: parent
                    spacing: 2

                    // The radio itself: one row, one toggle.
                    Item {
                        width: 220
                        height: 28

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: BT.enabled ? "Bluetooth on" : "Bluetooth off"
                            color: BT.enabled ? Theme.text : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BT.toggleEnabled()
                        }
                    }

                    Rectangle {
                        width: 220
                        height: 1
                        color: Theme.border
                    }

                    Repeater {
                        model: BT.known

                        Item {
                            id: deviceRow

                            required property var modelData

                            width: 220
                            height: 28

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: state.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: deviceRow.modelData.name ?? deviceRow.modelData.address
                                color: deviceRow.modelData.connected ? Theme.text : Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                elide: Text.ElideRight
                            }

                            Text {
                                id: state
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: deviceRow.modelData.connected ? "connected" : ""
                                color: Theme.alert
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: BT.toggleDevice(deviceRow.modelData)
                            }
                        }
                    }

                    Text {
                        visible: BT.known.length === 0
                        text: "No paired devices"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // Only one menu at a time: opening either closes the other, or they
            // stack in the same patch of screen.
            Connections {
                target: bt
                function onMenuOpenChanged() {
                    if (bt.menuOpen) tray.menuOpen = false
                }
            }

            Connections {
                target: tray
                function onMenuOpenChanged() {
                    if (tray.menuOpen) bt.menuOpen = false
                }
            }
        }
    }
}
