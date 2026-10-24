import QtQuick
import QtQuick.Layouts
import "services"

// What is playing, beside the window title and only while something is.
//
// Cover and name, cut short. The bar is a status line — the transport and the
// seek bar need room this strip does not have, and they live in the control
// centre, which is one click away and always in the same place.
Item {
    id: root

    visible: Player.present
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Rectangle {
            // A square that clips: cover art is not always square, and an
            // unclipped one changes the height of the whole bar.
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            radius: 4
            color: Theme.surfaceRaised
            clip: true

            Image {
                anchors.fill: parent
                visible: Player.art !== ""
                source: Player.art
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 40
                sourceSize.height: 40
            }
        }

        Text {
            Layout.maximumWidth: 220
            text: Player.label
            color: Player.playing ? Theme.textMuted : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: Hover.show(root, mapToItem(null, width / 2, 0).x)
        onExited: Hover.hide(root)
        onClicked: Player.togglePlaying()
    }
}
