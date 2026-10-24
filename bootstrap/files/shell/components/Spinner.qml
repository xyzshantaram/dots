import QtQuick
import "../core"

// A turning arc, for work that is under way and cannot say how long.
Text {
    id: spinner

    text: "\uf110"
    color: Theme.textMuted
    font.family: Theme.iconFont
    font.pixelSize: Theme.fontSize + 3

    NumberAnimation on rotation {
        running: spinner.visible
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
    }
}
