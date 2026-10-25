import "../components"
import "../core"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"

// The control centre: what the bar only has room to hint at.
//
// A PanelWindow, not a PopupWindow like the mixer. A PopupWindow is a menu
// surface and never takes the keyboard: forceActiveFocus left activeFocus false
// and not one key arrived, however the focus was asked for. Every surface in
// the reference shell that accepts typing — launcher, clipboard, settings — is
// a PanelWindow with exclusive keyboard, which is what this is now.
//
// The notification server is passed in rather than created here: it has to
// outlive the panel, and there can only be one. It is a singleton under
// services/, so one server is shared by every screen's window and the D-Bus
// name is claimed exactly once.
PanelWindow {
    id: root

    required property Item anchorItem
    required property var server

    color: "transparent"
    implicitWidth: 336
    implicitHeight: body.height + 16

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    // Eight off the right edge and eight under the strip, which is where the
    // anchor arithmetic used to put it. PanelWindow's own anchors, not
    // WlrLayershell's: the latter takes an opaque value type and cannot be
    // written as Top | Right.
    anchors.top: true
    anchors.right: true
    margins.top: Theme.barHeight + 8
    margins.right: 8
    exclusionMode: ExclusionMode.Ignore

    // Scanning wakes the radio, so it only happens while the panel is up and the
    // network list is the one being looked at.
    property bool wifiOpen: false
    property bool bluetoothOpen: false
    property bool powerOpen: false

    /** Two chips and their gap make up the column exactly. */
    readonly property int chipWidth: (implicitWidth - 36) / 2

    onVisibleChanged: Wifi.watching = visible && wifiOpen
    onWifiOpenChanged: Wifi.watching = visible && wifiOpen
    /** Place the tooltip under whichever chip asked for one. */
    function showTip(source): void {
        tip.content = source.tip
        const p = source.mapToItem(body, 0, source.height + 4)
        tip.x = Math.max(8, Math.min(body.width - tip.width - 8, p.x))
        tip.y = p.y
    }

    onBluetoothOpenChanged: {
        if (visible && bluetoothOpen) BT.discover();
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
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            // ---- quick toggles, two to a row
            Row {
                spacing: 8

                Chip {
                    width: root.chipWidth
                    glyph: "\uDB82\uDD2D"   // wifi_strength_off, standing in for the radio
                    label: "Wi-Fi"
                    detail: Wifi.current
                    detailColor: Theme.alert
                    on: Wifi.enabled
                    chevron: true
                    expanded: root.wifiOpen
                    expand: () => root.wifiOpen = !root.wifiOpen
                    // The radio's switch is in the list's header: the chip opens
                    // the list, and turning the radio off is an action taken
                    // where you can see what it affects.
                    activate: () => root.wifiOpen = !root.wifiOpen
                }

                Chip {
                    width: root.chipWidth
                    glyph: "\uDB80\uDCB1"   // bluetooth_connect
                    label: "Bluetooth"
                    detail: BT.connectedLabel
                    detailColor: Theme.alert
                    on: BT.enabled
                    chevron: true
                    expanded: root.bluetoothOpen
                    expand: () => root.bluetoothOpen = !root.bluetoothOpen
                    activate: () => root.bluetoothOpen = !root.bluetoothOpen
                }
            }

            Row {
                spacing: 8

                Chip {
                    width: root.chipWidth
                    glyph: "\uf0e7"         // bolt
                    label: Tuned.label
                    on: Tuned.active === "throughput-performance"
                    chevron: true
                    expanded: root.powerOpen
                    expand: () => root.powerOpen = !root.powerOpen
                    tip: `Power profile: ${Tuned.label}`
                    onTipRequested: (source) => root.showTip(source)
                    onTipCleared: tip.content = ""
                    activate: () => root.powerOpen = !root.powerOpen
                }

                Chip {
                    width: root.chipWidth
                    glyph: "\uf017"         // clock
                    label: "Caffeine"
                    on: power.caffeine
                    activate: () => power.caffeine = !power.caffeine
                }
            }

            Row {
                spacing: 8

                Chip {
                    width: root.chipWidth
                    glyph: "\uDB80\uDF6C"   // microphone
                    label: "Dictation"
                    detail: Dictation.byline
                    detailColor: Theme.alert
                    on: Dictation.running
                    activate: () => Dictation.toggle()
                }
            }

            /**
             * Caffeine is a process that holds an inhibitor for as long as the
             * toggle is on. Stopping the process releases it, which is the whole
             * mechanism.
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

            // Only with a list open: the rule below the chips and the one above
            // dictation are the same line when both lists are shut.
            Rectangle {
                visible: root.wifiOpen || root.bluetoothOpen
                width: column.width
                height: 1
                color: Theme.border
            }

            // ---- networks, only while the Wi-Fi chip's chevron says so
            Item {
                visible: root.wifiOpen
                width: column.width
                height: 22

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "NETWORKS"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Spinner {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Wifi.scanning
                    }

                    Switch {
                        on: Wifi.enabled
                        toggle: () => Wifi.radio(!Wifi.enabled)
                    }
                }
            }

            Text {
                visible: root.wifiOpen && Wifi.networks.length === 0
                text: !Wifi.enabled ? "Wi-Fi is off"
                    : Wifi.scanning ? "Scanning…"
                    : "Nothing in range"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            // Four rows at a time; the rest is a flick away. Row plus gap is 40,
            // so that four times over — or the list itself when it is shorter.
            Flickable {
                id: networksView

                visible: root.wifiOpen
                width: column.width
                height: Math.min(4 * 40, networksColumn.height)
                contentHeight: networksColumn.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                Column {
                    id: networksColumn
                    width: networksView.width
                    spacing: 4

                    Repeater {
                        model: Wifi.networks

                    Column {
                        id: network

                        required property var modelData

                        width: column.width
                        spacing: 4

                        Entry {
                            title: network.modelData.ssid
                            isActive: network.modelData.active
                            glyph: network.modelData.signal >= 75 ? "\uDB82\uDCBE"   // signal_cellular_3
                                : network.modelData.signal >= 50 ? "\uDB82\uDCBD"    // signal_cellular_2
                                : network.modelData.signal >= 25 ? "\uDB82\uDCBC"    // signal_cellular_1
                                : "\uDB82\uDCBF"                                      // signal_cellular_outline
                            hint: network.modelData.secured && !network.modelData.active ? "\uf023" : ""
                            action: () => network.modelData.active
                                ? Wifi.disconnect(network.modelData.ssid)
                                : Wifi.connect(network.modelData.ssid, "")
                        }

                        // The passphrase, inline under the row it belongs to.
                        Rectangle {
                            visible: Wifi.needsPassword === network.modelData.ssid
                            // Ask for the keyboard, then hand the field active
                            // focus. A bound `focus` does nothing on its own:
                            // nothing grants active focus in a panel whose
                            // window never took the keyboard.
                            onVisibleChanged: {
                                if (visible) Qt.callLater(() => passphrase.forceActiveFocus());
                            }
                            width: parent.width
                            height: 32
                            radius: 10
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border

                            TextInput {
                                id: passphrase

                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                focus: parent.visible
                                echoMode: TextInput.Password
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                selectionColor: Theme.calmBright
                                selectedTextColor: Theme.text

                                onAccepted: {
                                    const secret = text;
                                    text = "";
                                    Wifi.submit(secret);
                                }

                                Keys.onEscapePressed: Wifi.cancel()

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: passphrase.text === ""
                                    text: "Passphrase, then Enter"
                                    color: Theme.textDim
                                    font: passphrase.font
                                }
                            }
                        }
                    }
                }
            }
            }

            // ---- bluetooth, only while its chevron says so
            Item {
                visible: root.bluetoothOpen
                width: column.width
                height: 22

                Text {
                    id: bluetoothHeading
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BLUETOOTH"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !BT.available
                        text: "no adapter"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Switch {
                        on: BT.enabled
                        toggle: () => BT.toggleEnabled()
                    }
                }
            }

            Column {
                visible: root.bluetoothOpen
                width: column.width
                spacing: 4

                Repeater {
                    model: BT.known

                    Column {
                        id: device

                        required property var modelData

                        width: column.width
                        spacing: 4

                        Entry {
                            title: device.modelData.name || device.modelData.address
                            isActive: device.modelData.connected
                            glyph: device.modelData.connected
                                ? "\uDB80\uDCB1"   // bluetooth_connect
                                : "\uDB80\uDCAF"   // bluetooth
                            action: () => BT.toggleDevice(device.modelData)
                        }
                    }
                }
            }

            Text {
                visible: root.bluetoothOpen && BT.known.length === 0
                text: BT.enabled ? "Nothing paired" : "Bluetooth is off"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            // What is in range and not ours yet. Discovery runs for a window
            // when the list opens, so this fills in as devices answer.
            Item {
                visible: root.bluetoothOpen && (BT.nearby.length > 0 || BT.scanning)
                width: column.width
                height: 18

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AVAILABLE"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Spinner {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: BT.scanning
                }
            }

            Column {
                visible: root.bluetoothOpen
                width: column.width
                spacing: 4

                Repeater {
                    model: BT.nearby

                    Column {
                        id: candidate

                        required property var modelData

                        width: column.width
                        spacing: 4

                        Entry {
                            title: candidate.modelData.name || candidate.modelData.address
                            isActive: false
                            glyph: "\uDB80\uDCAF"   // bluetooth
                            action: () => BT.pair(candidate.modelData)
                        }
                    }
                }
            }

            Text {
                visible: root.wifiOpen && Wifi.error !== ""
                width: column.width
                text: Wifi.error
                color: Theme.alert
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            // ---- power profiles, only while the bolt's chevron says so
            Rectangle {
                visible: root.powerOpen
                width: column.width
                height: 1
                color: Theme.border
            }

            Item {
                visible: root.powerOpen
                width: column.width
                height: 16

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "POWER PROFILE"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }
            }

            Column {
                visible: root.powerOpen
                width: column.width
                spacing: 4

                Repeater {
                    model: Tuned.profiles

                    // An outer item so modelData exists: an inline component
                    // has its own context and cannot see the delegate's, so
                    // every use below goes through this id.
                    Column {
                        id: profile

                        required property var modelData

                        width: column.width
                        spacing: 4

                        Entry {
                            title: Tuned.pretty(profile.modelData)
                            isActive: Tuned.active === profile.modelData
                            glyph: "\uf0e7"        // bolt
                            // The current profile is marked, not left: clicking
                            // it applies it again rather than asking to confirm.
                            activeGlyph: "\uf00c"
                            confirms: false
                            action: () => Tuned.apply(profile.modelData)
                        }
                    }
                }
            }

            Rectangle { width: column.width; height: 1; color: Theme.border }

            // ---- now playing, with the transport the bar has no room for
            Text {
                text: "NOW PLAYING"
                color: Theme.text
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

            // Cover above the two lines, everything centred on the panel's axis:
            // beside each other the block reads left-heavy, because the text
            // inside it is left-aligned.
            Column {
                visible: Player.present
                width: parent.width
                spacing: 6

                Rectangle {
                    width: 64
                    height: 64
                    radius: 8
                    color: Theme.surface
                    clip: true
                    anchors.horizontalCenter: parent.horizontalCenter

                    Image {
                        anchors.fill: parent
                        visible: Player.art !== ""
                        source: Player.art
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 128
                        sourceSize.height: 128
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Player.title || "—"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Player.artist
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }

            Row {
                visible: Player.present
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 24

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf048"   // step-backward
                    color: Player.player?.canGoPrevious ? Theme.text : Theme.textDim
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.iconSize + 4

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
                    font.pixelSize: Theme.iconSize + 12

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
                    font.pixelSize: Theme.iconSize + 4

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Player.next()
                    }
                }
            }

            /**
             * The seek bar, full width, with the elapsed time to its left.
             *
             * One control for both the bar and the handle, since a 4px target is
             * not something to ask anyone to hit — the same reasoning as the
             * mixer's levels.
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

                Text {
                    id: elapsedText

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    text: seeker.clock(Player.elapsed)
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Item {
                    id: bar

                    anchors.left: elapsedText.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.border
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Player.length > 0 ? parent.width * Math.min(1, Player.elapsed / Player.length) : 0
                        height: 4
                        radius: 2
                        color: Player.seekable ? Theme.calmBright : Theme.textDim
                    }

                    Rectangle {
                        visible: Player.seekable
                        anchors.verticalCenter: parent.verticalCenter
                        x: (Player.length > 0 ? parent.width * Math.min(1, Player.elapsed / Player.length) : 0) - width / 2
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
            }

            Rectangle { width: column.width; height: 1; color: Theme.border }

            // ---- notifications, last: they arrive and leave on their own
            Text {
                text: "NOTIFICATIONS"
                color: Theme.text
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

                // A Notice is its own file with its own context, so it cannot
                // see the delegate's modelData; the id carries it across.
                Item {
                    id: noteHolder

                    required property var modelData

                    width: column.width
                    height: notice.implicitHeight

                    Notice {
                        id: notice
                        width: parent.width
                        note: noteHolder.modelData
                    }
                }
            }
        }

        // A chip's label, whole, while the pointer is on it. Inside the body so
        // it cannot spill outside the panel.
        Rectangle {
            id: tip

            property string content: ""

            visible: content !== ""
            z: 20
            width: tipLabel.implicitWidth + 16
            height: tipLabel.implicitHeight + 8
            radius: 6
            color: Theme.surfacePill
            border.width: 1
            border.color: Theme.border

            Text {
                id: tipLabel
                anchors.centerIn: parent
                text: tip.content
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
