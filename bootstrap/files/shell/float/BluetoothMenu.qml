import QtQuick
import ".."
import "../core"
import "../services"

// The bluetooth menu: the radio on or off, then the devices we can connect to.
//
// As with TrayMenu it takes the widget, so the position and the open state come
// from the one place that knows them.
Item {
    id: root

    required property var bt

    visible: root.bt.menuOpen && BT.available
    z: 8

    width: 240
    height: btColumn.implicitHeight + 12
    y: Theme.barHeight + 4
    x: Math.max(4, Math.min(root.parent.width - width - 4, root.bt.dropdownX - width / 2))

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSmall
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Theme.border
    }

    Column {
        id: btColumn
        anchors.centerIn: parent
        spacing: 2

        // The radio itself: one row, one toggle.
        Item {
            width: 220
            height: 28

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: BT.enabled ? "Bluetooth on" : "Bluetooth off"
                color: BT.enabled ? Theme.text : Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: BT.toggleEnabled()
            }
        }

        Rectangle {
            width: 220
            height: 1
            color: Theme.border
        }

        Repeater {
            model: BT.known

            Item {
                id: deviceRow

                required property var modelData

                width: 220
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: state.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: deviceRow.modelData.name ?? deviceRow.modelData.address
                    color: deviceRow.modelData.connected ? Theme.text : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }

                Text {
                    id: state
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: deviceRow.modelData.connected ? "connected" : ""
                    color: Theme.alert
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: BT.toggleDevice(deviceRow.modelData)
                }
            }
        }

        Text {
            visible: BT.known.length === 0
            text: "No paired devices"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
