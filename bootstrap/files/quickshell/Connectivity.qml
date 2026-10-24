import QtQuick
import "services"

// Bluetooth and the network, in one pill, bluetooth on the left.
//
// Two services and one surface: both answer "is this machine connected to
// something", and two pills for that was one pill too many.
//
// Click still opens the bluetooth menu, since it is the only panel of the two —
// the network answers in the tooltip, where an address belongs.
Pill {
    id: root

    readonly property string tip: {
        const bluetooth = !BT.enabled
            ? "Bluetooth off"
            : BT.connectedCount === 0
                ? "Bluetooth: not connected"
                : `Bluetooth: ${BT.connectedCount} connected`

        const net = Net.addresses.length === 0
            ? "Offline"
            : `${Net.useEthernet ? "Ethernet" : "Wi-Fi"}: ${Net.addresses[0]}`

        return `${bluetooth}\n${net}`
    }

    property bool menuOpen: false
    property real dropdownX: 0

    /** Per glyph, by eye: see the note in Tray.qml. */
    property int glyphNudgeX: 0
    property int networkNudgeX: 2

    /**
     * Whether the network has something real to show.
     *
     * One value for both the glyph and its colour, so the slashed icon can
     * never be drawn in the colour that means "connected" — which is what an
     * online-but-signal-less link did.
     */
    readonly property bool netLive: Net.online && (Net.useEthernet || Net.signal > 0)

    Item {
        // Always present. With no adapter at all this falls through to the
        // crossed-out glyph, which is the honest answer and keeps the pill from
        // changing width as hardware comes and goes.
        implicitWidth: bluetoothGlyph.implicitWidth
        implicitHeight: bluetoothGlyph.implicitHeight

        Text {
            id: bluetoothGlyph

            // Three states, three glyphs: connected, on but idle, off. Above
            // U+FFFF, so each is written as its UTF-16 pair.
            text: BT.connectedCount > 0
                ? "\uDB80\uDCB1"      // nf-md-bluetooth_connect
                : BT.enabled
                    ? "\uDB80\uDCAF"  // nf-md-bluetooth
                    : "\uDB80\uDCB2"  // nf-md-bluetooth_off

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

    Item {
        implicitWidth: networkGlyph.implicitWidth
        implicitHeight: networkGlyph.implicitHeight

        Text {
            id: networkGlyph

            // Always one of five: the slashed set when offline, the wired
            // glyph, then the four bars. Material Design Icons, all above
            // U+FFFF.
            text: !root.netLive ? "\uDB82\uDD2D"                                // wifi_strength_off
                : Net.useEthernet ? "\uDB84\uDC87"                              // nf-md-router_network, U+F1087
                : Net.signal >= 0.75 ? "\uDB82\uDD28"                           // wifi_strength_4
                : Net.signal >= 0.5 ? "\uDB82\uDD25"                            // wifi_strength_3
                : Net.signal >= 0.25 ? "\uDB82\uDD22"                           // wifi_strength_2
                : "\uDB82\uDD1F"                                                // wifi_strength_1

            color: root.netLive ? Theme.text : Theme.textDim
            font.family: Theme.iconFont
            font.pixelSize: Theme.glyphSize
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.networkNudgeX
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
        if (!BT.available) return
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
