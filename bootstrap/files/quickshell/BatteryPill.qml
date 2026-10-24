import QtQuick
import QtQuick.Layouts
import "services"

// The battery: hours when it is running the machine, a percentage while it
// charges.
//
// The choice is not arbitrary. Unplugged, "3h 20m" is an answer and "47%" is a
// question you have to convert; plugged in, the percentage is the thing that is
// moving and the hours-to-full is a number nobody reads.
//
// The colour is the shell's attention ramp — purple with plenty in it, orange
// as it empties — and it runs the same way in both cases, because running out
// of battery is the same fact whether or not a cable is in.
Pill {
    id: root

    visible: Battery.present

    readonly property string tip: Battery.onBattery
        ? `Battery: ${Math.round(Battery.level * 100)}%` +
          (Battery.remaining ? `\n${Battery.remaining} remaining` : "")
        : `Battery: ${Math.round(Battery.level * 100)}%` +
          (Battery.toFull ? `\n${Battery.toFull} to full` : "")

    // White when there is plenty, orange as it empties, and back again as it
    // fills. warmth, not blend: this is a level, not an attention score, and
    // charging is not a state worth a colour of its own.
    readonly property color tint: Situation.warmth(Situation.batteryScore(Battery.level * 100))

    // One reading at a time: hours on battery, percentage on a cable.
    readonly property string reading: Battery.onBattery
        ? (Battery.remaining || "—")
        : `${Math.round(Battery.level * 100)}%`

    Item {
        implicitWidth: cell.implicitWidth
        implicitHeight: cell.implicitHeight

        Text {
            id: cell

            /**
             * Material Design Icons' cells, one per ten percent.
             *
             * battery_10 through battery_80 are contiguous from U+F007A, so the
             * step is computed rather than written out eight times. The three
             * exceptions are the ones with meaning beyond a level: an empty
             * outline below ten, a heart when it is holding at the top of the
             * charge on a cable, and the plain cell when it is full and running
             * the machine.
             */
            text: {
                const pct = Math.round(Battery.level * 100)
                if (pct < 10) return "\uDB80\uDC8E"                        // battery_outline, U+F008E
                if (!Battery.onBattery && !Battery.charging && pct >= 85)  // holding, plugged
                    return "\uDB84\uDE0F"                                  // battery_heart, U+F120F
                if (Battery.onBattery && pct >= 80)                        // full, unplugged
                    return "\uDB80\uDC79"                                  // battery, U+F0079

                const step = Math.max(10, Math.min(80, Math.floor(pct / 10) * 10))
                return String.fromCodePoint(0xf0079 + step / 10)
            }

            color: root.tint
            font.family: Theme.iconFont
            font.pixelSize: Theme.glyphSize
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.glyphNudgeX
        }
    }

    Text {
        text: root.reading
        color: root.tint
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
        // A left margin is space on the left, which pushes the text right. The
        // negative right margin I tried first did the opposite, since it
        // extends the cell's right edge rather than moving the item.
        Layout.leftMargin: 4
    }

    /** Per glyph, by eye: see the note in Tray.qml. */
    property int glyphNudgeX: 0

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: Hover.show(root, mapToItem(null, width / 2, 0).x)
        onExited: Hover.hide(root)
    }
}
