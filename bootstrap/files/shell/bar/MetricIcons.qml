import "../core"
import QtQuick
import QtQuick.Layouts
import "../services"

// CPU and memory as one pill split down the middle: CPU on the left, memory on
// the right, a hairline between them.
//
// Each half carries its own strain as a background, purple at rest and orange
// as the load climbs, using the same ramp as the clock and the battery. The
// glyphs stay white, so the colour is the reading and the type is not.
//
// There is no bar to measure against, which is the trade — a load at 40% looks
// like a load at 20% — so the percentages live in the tooltip, where a number
// can be read rather than inferred from a hue.
//
// Disk was the third of these and is gone: it lives at whatever it lives at and
// drifts, so a threshold tuned to CPU leaves it permanently tinted and saying
// nothing. It belongs in the control centre as a panel.

Item {
    id: root

    implicitWidth: pill.width
    implicitHeight: pill.height

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

    Rectangle {
        id: pill

        readonly property int cellWidth: Theme.glyphSize + 16

        width: cellWidth * 2
        height: Theme.glyphSize + 8
        radius: Theme.pillRadius
        color: "transparent"

        // Each half is rounded only on its outer side, so together they read as
        // one pill with a seam rather than two pills touching.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width / 2
            topLeftRadius: parent.radius
            bottomLeftRadius: parent.radius
            color: Situation.surface(Situation.loadScore(Metrics.cpu * 100))
            Behavior on color { ColorAnimation { duration: Theme.blendMs } }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width / 2
            topRightRadius: parent.radius
            bottomRightRadius: parent.radius
            color: Situation.surface(Situation.loadScore(Metrics.memory * 100))
            Behavior on color { ColorAnimation { duration: Theme.blendMs } }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Qt.rgba(1, 1, 1, 0.18)
        }

        Row {
            anchors.fill: parent
            spacing: 0

            Repeater {
                model: [
                    { label: "cpu", glyph: "\uf2db" },
                    { label: "mem", glyph: "\uf233" },
                ]

                Text {
                    required property var modelData

                    width: pill.width / 2
                    height: pill.height
                    text: modelData.glyph
                    color: Theme.text
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.glyphSize
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
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
