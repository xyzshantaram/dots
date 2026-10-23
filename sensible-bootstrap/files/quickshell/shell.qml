// Starter quickshell config for live UI development.
//
// One layer-shell bar across the top: a live clock on the left, a label on
// the right. Enough to see a surface appear and to reload against while
// building the real shell.
//
//   qs -p ~/.config/quickshell        run it
//   qs -p ~/.config/quickshell       re-run after an edit (replaces the instance)
//
// niri starts it via `spawn-at-startup "qs"` (see 110-niri.ts).

import QtQuick
import QtQuick.Layouts
import Quickshell

ShellRoot {
    PanelWindow {
        anchors {
            top: true
            left: true
            right: true
        }
        implicitHeight: 28
        color: "#1b1b1b"

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 12

            Text {
                color: "#e0e0e0"
                font.family: "FantasqueSansM Nerd Font Mono"
                font.pixelSize: 13
                text: Qt.formatDateTime(clock.now, "HH:mm:ss")
            }

            Item { Layout.fillWidth: true }

            Text {
                color: "#8a8a8a"
                font.family: "FantasqueSansM Nerd Font Mono"
                font.pixelSize: 13
                text: "quickshell"
            }
        }

        Timer {
            id: clock
            property date now: new Date()
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: now = new Date()
        }
    }
}
