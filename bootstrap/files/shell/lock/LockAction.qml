import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// A lock-screen button that asks twice. The first click arms it for four
// seconds; the second runs the command. No dialog to dismiss, and nothing
// dangerous happens from a single stray click on a dark screen.

Rectangle {
    id: root

    required property string label
    property var command: []
    property bool armed: false

    width: Math.max(caption.width + 44, 120)
    height: 40
    radius: Theme.radiusSmall
    color: armed ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08)
    border.width: 1
    border.color: armed ? Theme.text : Qt.rgba(1, 1, 1, 0.18)

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: caption
        anchors.centerIn: parent
        text: root.armed ? root.label + "?" : root.label
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!root.armed) {
                root.armed = true;
                disarm.restart();
                return;
            }
            disarm.stop();
            root.armed = false;
            proc.command = root.command;
            proc.running = true;
        }
    }

    Timer {
        id: disarm
        interval: 4000
        onTriggered: root.armed = false
    }

    Process {
        id: proc
        command: []
    }
}
