import QtQuick
import "../core"
import "../services"

// macOS-shaped indicator: a rounded purple square, the white glyph, an orange
// segmented meter, and the device's name under it.

Item {
    id: root

    anchors.centerIn: parent
    anchors.verticalCenterOffset: parent.height * 0.25
    width: 192
    height: 192

    visible: OsdService.shown
    opacity: OsdService.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 110 } }

    Rectangle {
        anchors.fill: parent
        radius: 24
        color: Qt.rgba(Theme.surfacePill.r, Theme.surfacePill.g, Theme.surfacePill.b, 0.72)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
            text: OsdService.glyph
            color: Theme.text
            opacity: OsdService.muted ? 0.45 : 1
            font.family: Theme.iconFont
            font.pixelSize: 110
        }

        Row {
            id: meter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: name.top
            anchors.bottomMargin: 10
            spacing: 2

            Repeater {
                model: 16

                delegate: Rectangle {
                    required property int index
                    width: 7
                    height: 7
                    radius: 2
                    color: index < Math.round(OsdService.value * 16)
                        ? Theme.alert
                        : Qt.rgba(1, 1, 1, 0.18)
                }
            }
        }

        Text {
            id: name
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            text: OsdService.label
            elide: Text.ElideRight
            color: Theme.text
            opacity: 0.75
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
