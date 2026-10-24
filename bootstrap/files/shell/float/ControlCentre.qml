import "../core"
import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// The control centre: what the bar only has room to hint at.
//
// A PopupWindow, like the mixer — the bar's headroom is for tooltips and short
// menus, and this one is tall and scrolls in spirit even if it does not yet.
// The anchor maths is the mixer's, flipped to the right edge because this opens
// from the last widget on the bar.
//
// The notification server is passed in rather than created here: it has to
// outlive the panel, and there can only be one. It lives on Bar, outside the
// per-screen Variants, so a second monitor does not try to claim the D-Bus name
// a second time.
PopupWindow {
    id: root

    required property Item anchorItem
    required property var server

    color: "transparent"
    implicitWidth: 336
    implicitHeight: body.height + 16

    anchor.item: root.anchorItem
    // Breathing room: eight to the left, which reads as eight off the right
    // edge of the screen since this hangs off the last widget on the bar, and
    // eight below the strip.
    anchor.rect.x: root.anchorItem ? -(root.width - root.anchorItem.width) - 8 : 0
    anchor.rect.y: root.anchorItem ? root.anchorItem.height + 8 : 0
    anchor.adjustment: PopupAdjustment.SlideX

    /** A toggle in the quick row: glyph, label, and whether it is on. */
    component Chip: Rectangle {
        id: chip

        required property string glyph
        required property string label
        required property bool on
        required property var activate

        width: 158
        height: 34
        radius: Theme.radiusSmall
        color: chip.on ? Theme.calmDeep : Theme.surface
        border.width: 1
        border.color: chip.on ? Theme.calmBright : Theme.border

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: chip.glyph
            color: chip.on ? Theme.text : Theme.textMuted
            font.family: Theme.iconFont
            font.pixelSize: Theme.iconSize
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10 + Theme.iconSize + 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label
            color: chip.on ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activate()
        }
    }

    Rectangle {
        id: body

        width: parent.width
        height: column.implicitHeight + 28
        color: Theme.surfaceRaised
        radius: Theme.radiusSmall
        border.width: 1
        border.color: Theme.border

        Column {
            id: column
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Text {
                text: "CONTROL CENTRE"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            // ---- quick toggles, two to a row
            Row {
                spacing: 8

                Chip {
                    glyph: "\uDB82\uDD2D"   // wifi_strength_off, standing in for the radio
                    label: "Wi-Fi"
                    on: Net.radioEnabled
                    activate: () => {
                        if (Net.radio) Net.radio.enabled = !Net.radio.enabled
                    }
                }

                Chip {
                    glyph: "\uDB80\uDCB1"   // bluetooth_connect
                    label: "Bluetooth"
                    on: BT.enabled
                    activate: () => BT.toggleEnabled()
                }
            }

            Row {
                spacing: 8

                Chip {
                    glyph: "\uf0e7"         // bolt
                    label: `Power: ${Tuned.label}`
                    on: Tuned.active === "throughput-performance"
                    activate: () => Tuned.cycle()
                }

                Chip {
                    glyph: "\uf017"         // clock
                    label: "Caffeine"
                    on: power.caffeine
                    activate: () => power.caffeine = !power.caffeine
                }
            }

            Row {
                spacing: 8

                Chip {
                    glyph: "\uf0f3"         // bell
                    label: "Don't disturb"
                    on: root.server?.doNotDisturb ?? false
                    activate: () => {
                        if (root.server) root.server.doNotDisturb = !root.server.doNotDisturb
                    }
                }
            }

            /**
             * Power profile and caffeine.
             *
             * The profile is a dummy: powerprofilesctl is not installed on this
             * machine, and 40-packages.ts now lists power-profiles-daemon. Once
             * its unit is enabled this cycles the real thing — the shape of the
             * control is right, it just does not reach anything yet.
             *
             * Caffeine is real, and is just a process that holds an inhibitor
             * for as long as the toggle is on. Stopping the process releases it,
             * which is the whole mechanism.
             */
            QtObject {
                id: power
                property string profile: "balanced"
                property bool caffeine: false
            }

            Process {
                running: power.caffeine
                command: [
                    "systemd-inhibit", "--what=idle:sleep",
                    "--why=Caffeine, from the control centre",
                    "sleep", "infinity",
                ]
            }

            Rectangle { width: column.width; height: 1; color: Theme.border }

            // ---- dictation, the whole stack rather than the pill's one word
            Text {
                text: "DICTATION"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Row {
                spacing: 8

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: Voxtype.busy ? Theme.alert : Dictation.server === "active" ? Theme.calm : Theme.textDim
                }

                Text {
                    text: Dictation.summary
                    color: Voxtype.busy ? Theme.text : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            Text {
                visible: Dictation.detail !== ""
                width: column.width
                text: Dictation.detail
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Rectangle { width: column.width; height: 1; color: Theme.border }

            // ---- now playing, with the transport the bar has no room for
            Text {
                text: "NOW PLAYING"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Text {
                visible: !Player.present
                text: "Nothing playing"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                visible: Player.present
                spacing: 10

                Rectangle {
                    width: 44
                    height: 44
                    radius: 6
                    color: Theme.surface
                    clip: true

                    Image {
                        anchors.fill: parent
                        visible: Player.art !== ""
                        source: Player.art
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 88
                        sourceSize.height: 88
                    }
                }

                Column {
                    width: column.width - 54
                    spacing: 2

                    Text {
                        width: parent.width
                        text: Player.title || "—"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: Player.artist
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                }
            }

            Row {
                visible: Player.present
                spacing: 14

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf048"   // step-backward
                    color: Player.player?.canGoPrevious ? Theme.text : Theme.textDim
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.iconSize

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Player.previous()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Player.playing ? "\uf04c" : "\uf04b"   // pause / play
                    color: Theme.text
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.iconSize + 4

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Player.togglePlaying()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf051"   // step-forward
                    color: Player.player?.canGoNext ? Theme.text : Theme.textDim
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.iconSize

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Player.next()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: seeker.elapsed
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            /**
             * The seek bar. One control for both the bar and the handle, since
             * a 4px target is not something to ask anyone to hit — the same
             * reasoning as the mixer's levels.
             */
            Item {
                id: seeker

                visible: Player.present
                width: column.width
                height: 16

                function clock(seconds): string {
                    const s = Math.max(0, Math.floor(seconds))
                    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
                }

                readonly property string elapsed: clock(Player.position)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.border
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Player.length > 0 ? parent.width * Math.min(1, Player.position / Player.length) : 0
                    height: 4
                    radius: 2
                    color: Player.seekable ? Theme.calmBright : Theme.textDim
                }

                Rectangle {
                    visible: Player.seekable
                    anchors.verticalCenter: parent.verticalCenter
                    x: (Player.length > 0 ? parent.width * Math.min(1, Player.position / Player.length) : 0) - width / 2
                    width: 12
                    height: 12
                    radius: 6
                    color: Theme.text
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -4
                    anchors.bottomMargin: -4
                    cursorShape: Player.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor

                    onPressed: (mouse) => Player.seekTo(mouse.x / width * Player.length)
                    onPositionChanged: (mouse) => {
                        if (pressed) Player.seekTo(mouse.x / width * Player.length)
                    }
                }
            }

            Rectangle { width: column.width; height: 1; color: Theme.border }

            // ---- notifications, last: they arrive and leave on their own
            Text {
                text: "NOTIFICATIONS"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Text {
                visible: (root.server?.trackedNotifications?.values?.length ?? 0) === 0
                text: root.server ? "Nothing to report" : "No notification server"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Repeater {
                model: root.server?.trackedNotifications?.values ?? []

                Item {
                    id: note

                    required property var modelData

                    width: column.width
                    height: noteColumn.implicitHeight + 12

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: noteArea.containsMouse ? Theme.surface : "transparent"
                    }

                    Column {
                        id: noteColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: `${note.modelData.appName ?? ""} · ${note.modelData.summary ?? ""}`
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: (note.modelData.body ?? "") !== ""
                            width: parent.width
                            text: note.modelData.body ?? ""
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: noteArea
                        anchors.fill: parent
                        hoverEnabled: true
                        // Clicking dismisses: the panel is not a notification
                        // daemon, and there is nowhere else for a click to go.
                        cursorShape: Qt.PointingHandCursor
                        onClicked: note.modelData.dismiss()
                    }
                }
            }
        }
    }
}
