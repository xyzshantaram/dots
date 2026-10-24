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

    // Scanning wakes the radio, so it only happens while the panel is up and the
    // network list is the one being looked at.
    property bool wifiOpen: false
    property bool bluetoothOpen: false
    property bool powerOpen: false

    onVisibleChanged: Wifi.watching = visible && wifiOpen
    onWifiOpenChanged: Wifi.watching = visible && wifiOpen
    onBluetoothOpenChanged: {
        if (visible && bluetoothOpen) BT.discover();
    }

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

        /** A second line under the label, for state in a few words. */
        property string detail: ""
        /** Its colour, so one chip can say something the others do not. */
        property color detailColor: Theme.textDim
        /** A chevron, for a chip that opens a list rather than toggling. */
        property bool chevron: false
        /** Whether that list is open; turns the chevron down. */
        property bool expanded: false
        /** What the chevron does. The rest of the chip still calls activate. */
        property var expand: null
        /** Shown on hover, for a label that a narrow chip cuts short. */
        property string tip: ""

        // Fixed, not implicit: the body is 336 wide with 14 either side, and
        // two chips plus their gap have to add up to exactly that. Sized by
        // their content they overran the column and the right margin vanished.
        width: (root.implicitWidth - 36) / 2
        height: chip.detail === "" ? 34 : 42
        radius: Theme.radiusSmall
        color: chipArea.containsMouse
            ? (chip.on ? Theme.calm : Theme.surfacePill)
            : (chip.on ? Theme.calmDeep : Theme.surface)
        border.width: 1
        border.color: chip.on ? Theme.calmBright : Theme.border

        Text {
            id: chipGlyph

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: chip.glyph
            color: chip.on ? Theme.text : Theme.textMuted
            font.family: Theme.iconFont
            font.pixelSize: Theme.iconSize
        }

        Column {
            id: chipText

            anchors.left: chipGlyph.right
            anchors.leftMargin: 8
            anchors.right: chip.chevron ? chevronBox.left : parent.right
            anchors.rightMargin: chip.chevron ? 4 : 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: chip.label
                color: chip.on ? Theme.text : Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }

            Text {
                visible: chip.detail !== ""
                width: parent.width
                text: chip.detail
                color: chip.detailColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }

        // Its own target, not part of the whole-chip click: the chip toggles a
        // radio, the chevron opens the list under it, and they are different
        // actions on the same 150px surface.
        Item {
            id: chevronBox

            visible: chip.chevron
            // The chip's own MouseArea is declared after this one and would
            // otherwise swallow every click and hover meant for the chevron.
            z: 2
            anchors.right: parent.right
            anchors.rightMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 26

            Rectangle {
                anchors.fill: parent
                radius: 7
                color: chevronArea.containsMouse ? Theme.surfacePill : "transparent"
            }

            Text {
                anchors.centerIn: parent
                text: chip.expanded ? "\uf078" : "\uf054"   // chevron-down / right
                color: chip.on ? Theme.text : Theme.textDim
                font.family: Theme.iconFont
                font.pixelSize: Theme.fontSize + 3
            }

            MouseArea {
                id: chevronArea
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (chip.expand) chip.expand();
                }
            }
        }

        MouseArea {
            id: chipArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activate()
            onEntered: {
                if (chip.tip === "") return;
                tip.content = chip.tip;
                const p = chip.mapToItem(body, 0, chip.height + 4);
                tip.x = Math.max(8, Math.min(body.width - tip.width - 8, p.x));
                tip.y = p.y;
            }
            onExited: tip.content = ""
        }
    }

    /**
     * A switch, for a radio that can be on or off.
     *
     * Deliberately larger than the 11px heading it sits beside: this is the
     * control for the list under it, and it should be the easiest thing in the
     * row to hit.
     */
    component Switch: Item {
        id: sw

        required property bool on
        required property var toggle

        width: 40
        height: 22

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: sw.on ? Theme.alert : Theme.surface
            border.width: 1
            border.color: sw.on ? Theme.alert : Theme.border

            Behavior on color { ColorAnimation { duration: 160 } }

            Rectangle {
                width: 16
                height: 16
                radius: 8
                y: 2
                x: sw.on ? parent.width - width - 3 : 3
                color: sw.on ? Theme.text : Theme.textMuted

                Behavior on x { NumberAnimation { duration: 160 } }
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggle()
        }
    }

    /** A turning arc, for work that is under way and cannot say how long. */
    component Spinner: Text {
        id: spinner

        text: "\uf110"   // spinner
        color: Theme.textMuted
        font.family: Theme.iconFont
        font.pixelSize: Theme.fontSize + 3

        NumberAnimation on rotation {
            running: spinner.visible
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
        }
    }

    /**
     * One row in a list of things you can join: outlined, orange while it is the
     * current one, with the action on the right.
     *
     * The action is a chevron to join and a cross to leave — and the cross
     * becomes a check on the first click, because disconnecting on one stray
     * click is not something to make easy.
     */
    component Entry: Column {
        id: entry

        required property string title
        required property bool isActive
        required property string glyph
        /** Small text before the action, for a lock or a state. */
        property string hint: ""
        required property var action

        property bool confirming: false
        /** Whether the action on the current row is something to confirm. */
        property bool confirms: true
        /** The glyph on the current row: a cross, or a tick where a row is not
         * something you can leave. */
        property string activeGlyph: "\uf00d"

        width: column.width
        spacing: 4

        Rectangle {
            id: entryRow

            width: parent.width
            height: 36
            radius: 10
            // A surface rather than an outline: every row is a shade darker than
            // the panel, and only the current one is marked out in orange.
            color: Theme.surface
            border.width: entry.isActive ? 2 : 0
            border.color: Theme.alert

            Text {
                id: entryGlyph

                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: entry.glyph
                color: entry.isActive ? Theme.text : Theme.textMuted
                font.family: Theme.iconFont
                font.pixelSize: Theme.iconSize
            }

            Text {
                anchors.left: entryGlyph.right
                anchors.leftMargin: 10
                anchors.right: entryHint.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: entry.title
                color: entry.isActive ? Theme.text : Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }

            Text {
                id: entryHint

                anchors.right: entryAction.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: entry.hint
                color: entry.isActive ? Theme.alert : Theme.textDim
                font.family: entry.hint === "\uf023" ? Theme.iconFont : Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                id: entryAction

                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: entry.isActive ? (entry.confirming ? "\uf00c" : entry.activeGlyph) : "\uf054"
                color: entry.isActive ? Theme.alert : Theme.textDim
                font.family: Theme.iconFont
                font.pixelSize: entry.confirming ? Theme.fontSize + 3 : Theme.fontSizeSmall
                font.bold: entry.confirming

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: entry.click()
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: entry.click()
            }
        }

        Timer {
            id: confirm
            interval: 2500
            onTriggered: entry.confirming = false
        }

        function click(): void {
            if (!entry.isActive || !entry.confirms) {
                entry.action();
                return;
            }
            if (entry.confirming) {
                entry.confirming = false;
                entry.action();
                return;
            }
            entry.confirming = true;
            confirm.restart();
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
                color: Theme.text
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
                    chevron: true
                    expanded: root.wifiOpen
                    expand: () => root.wifiOpen = !root.wifiOpen
                    // The radio's switch is in the list's header: the chip opens
                    // the list, and turning the radio off is an action taken
                    // where you can see what it affects.
                    activate: () => root.wifiOpen = !root.wifiOpen
                }

                Chip {
                    glyph: "\uDB80\uDCB1"   // bluetooth_connect
                    label: "Bluetooth"
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
                    glyph: "\uf0e7"         // bolt
                    label: Tuned.label
                    on: Tuned.active === "throughput-performance"
                    chevron: true
                    expanded: root.powerOpen
                    expand: () => root.powerOpen = !root.powerOpen
                    tip: `Power profile: ${Tuned.label}`
                    activate: () => root.powerOpen = !root.powerOpen
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
                    glyph: "\uDB80\uDF6C"   // microphone
                    label: "Dictation"
                    detail: Dictation.byline
                    detailColor: Theme.alert
                    on: Dictation.running
                    activate: () => Dictation.toggle()
                }

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
                        on: Net.radioEnabled
                        toggle: () => {
                            if (Net.radio) Net.radio.enabled = !Net.radio.enabled
                        }
                    }
                }
            }

            Text {
                visible: root.wifiOpen && Wifi.networks.length === 0
                text: Wifi.scanning ? "Scanning…" : "Nothing in range"
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
