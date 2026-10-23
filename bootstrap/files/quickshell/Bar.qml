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
            implicitHeight: Theme.barHeight
            // The window is the full bar strip but paints only the pills, so
            // the wallpaper shows through everywhere else.
            color: "transparent"
            // Reserve only the strip, so windows tile below the bar.
            exclusiveZone: Theme.barHeight

            RowLayout {
                anchors.fill: parent
                // A quarter of the layout gap: enough for the pills to read as
                // floating, tight enough that the bar stays slim. Equal on all
                // four sides, which is what a RowLayout's vertical centring of
                // each pill then makes visible.
                anchors.margins: Theme.gap / 4
                spacing: Theme.gap

                // Left: when it is, what is focused, and what is playing.
                Clock {}
                WindowTitle {}

                // The middle is deliberately empty: the bar is a left cluster
                // and a right cluster with space between them. This spacer is
                // what holds them apart.
                Item { Layout.fillWidth: true }

                // Right: state that changes on its own — dictation first, then
                // the metric bars and the status cluster.
                VoxtypePill {}
            }
        }
    }
}
