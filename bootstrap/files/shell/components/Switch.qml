import QtQuick
import "../core"

// A radio's switch: on is orange, off is a surface.
//
// Deliberately larger than the 11px heading it sits beside — this is the control
// for the list under it, and it should be the easiest thing in the row to hit.
Item {
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

            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggle()
    }
}
