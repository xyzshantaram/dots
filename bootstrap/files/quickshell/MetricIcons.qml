import QtQuick
import QtQuick.Layouts
import "services"

// CPU and memory as two icons in a row, with a tooltip carrying the numbers.
//
// Colour is the signal: white at rest, orange as the load climbs, using the
// same ramp as the evening clock. There is no bar to read, which is the trade —
// a load at 40% looks like a load at 20% — so the percentages live in the
// tooltip, where a number can be read rather than inferred from a hue.
//
// Disk was the third of these and is gone: it lives at whatever it lives at and
// drifts, so a threshold tuned to CPU leaves it permanently tinted and saying
// nothing. It belongs in the control centre as a panel.
//
// The glyphs are Font Awesome's, which is the set every nerd font carries: a
// microchip and a server for memory. Sized at Theme.glyphSize because their ink
// only fills part of the em box.
Item {
    id: root

    // Sized by the pill, which is sized by its row. The Item exists only to
    // carry a hover area larger than the glyphs themselves — a 22px icon is a
    // mean target for a pointer.
    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    /**
     * Read by the bar's tooltip while the pointer is here.
     *
     * CPU as a percentage, memory as the amount in use and the percentage it
     * represents — "12.3G / 38%" answers both "am I close to the limit" and
     * "how much is that", which a percentage alone leaves you guessing at.
     */
    readonly property string tip:
        `CPU: ${Math.round(Metrics.cpu * 100)}%\n` +
        `Mem: ${Metrics.memoryGb.toFixed(1)}G / ${Math.round(Metrics.memory * 100)}%`

    Pill {
        id: pill

        Row {
            spacing: Theme.gap

            Repeater {
                model: [
                    { label: "cpu", glyph: "\uf2db", value: Metrics.cpu },
                    { label: "mem", glyph: "\uf233", value: Metrics.memory },
                ]

                Text {
                    required property var modelData

                    text: modelData.glyph
                    color: Situation.loadColour(modelData.value)
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.glyphSize

                    // The sample arrives every two seconds, so without this the
                    // colour would step rather than travel.
                    Behavior on color {
                        ColorAnimation { duration: Theme.blendMs }
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        // null maps to scene coordinates, which for a layer surface are its own
        // window's — which is what the bar's tooltip positions against.
        onEntered: Hover.show(root, mapToItem(null, width / 2, 0).x)
        onExited: Hover.hide(root)
    }
}
