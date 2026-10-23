import QtQuick
import QtQuick.Layouts
import Quickshell

// The bar: one layer-shell surface per screen, a left cluster, a right cluster
// and nothing in between.
//
// Variants over Quickshell.screens is what puts the same bar on every monitor.
// Without it a bare PanelWindow attaches to one arbitrary screen, which on a
// laptop is usually the right one by luck and never is once a second monitor
// appears.
//
// The window is taller than the strip. The strip reserves space and takes
// input; the extra height below it is where the tooltip is drawn, and the mask
// is what stops that height taking clicks meant for the window underneath.
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

            implicitHeight: Theme.barHeight + Theme.tooltipHeadroom
            // The window is the full strip but paints only the pills, so the
            // wallpaper shows through everywhere else.
            color: "transparent"
            // Reserve only the strip, so windows tile below the bar and the
            // tooltip can float over whatever is there.
            exclusiveZone: Theme.barHeight

            // Everything below the strip is click-through.
            mask: Region {
                x: 0
                y: 0
                width: window.width
                height: Theme.barHeight
            }

            RowLayout {
                anchors.fill: parent
                // A quarter of the layout gap: enough for the pills to read as
                // floating, tight enough that the bar stays slim. Equal on all
                // four sides, which is what a RowLayout's vertical centring of
                // each pill then makes visible.
                //
                // Set before the bottom margin, which overrides that one edge:
                // the row gets the strip, and the leftover height below it is
                // the tooltip's to draw in.
                anchors.margins: Theme.gap / 4
                anchors.bottomMargin: Theme.tooltipHeadroom
                spacing: Theme.gap

                // Left: when it is, what is focused, and what is playing.
                Clock {}
                WindowTitle {}

                // The middle is deliberately empty: the bar is a left cluster
                // and a right cluster with space between them. This spacer is
                // what holds them apart.
                Item { Layout.fillWidth: true }

                // Right: state that changes on its own — dictation first, then
                // the metric icons, then the status cluster.
                VoxtypePill {}
                Metrics {}
            }

            // The one tooltip, drawn under the strip at whichever widget asked
            // for it. Clamped to the window so a widget near an edge does not
            // push half of it off screen.
            Item {
                id: tooltip

                visible: Hover.text !== ""
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
        }
    }
}
