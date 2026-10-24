import QtQuick
import "../core"

// A quick control in the control centre: a glyph, a label, an optional second
// line, and optionally a chevron that opens a list underneath.
//
// The chip lights when it is on, brightens under the pointer, and keeps the
// chevron as its own target — turning a radio on and opening the radio's list
// are different actions on the same 150px surface.
//
// Width is the caller's: two chips plus the gap have to add up to the panel's
// column exactly, and a component that guessed would be wrong on the next panel.
Rectangle {
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

    /** Shown on hover, by the caller, for a label that the width cuts short. */
    property string tip: ""

    /** Ask the caller to place a tooltip for this chip, and to take it away. */
    signal tipRequested(var source)
    signal tipCleared()

    height: 42
    radius: Theme.radiusSmall
    color: chipArea.containsMouse
        ? (chip.on ? Theme.calm : Theme.surfacePill)
        : (chip.on ? Theme.calmDeep : Theme.surface)
    border.width: 1
    border.color: chip.on ? Theme.calmBright : Theme.border

    Behavior on color { ColorAnimation { duration: 120 } }

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

    // Its own target, not part of the whole-chip click, and declared before the
    // chip's MouseArea with a z so that area cannot swallow it.
    Item {
        id: chevronBox

        visible: chip.chevron
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
            if (chip.tip !== "") chip.tipRequested(chip);
        }
        onExited: chip.tipCleared()
    }
}
