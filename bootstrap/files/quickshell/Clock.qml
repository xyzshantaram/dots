import QtQuick
import QtQuick.Layouts

// Time and date, leftmost on the bar. White, as asked — this is the one thing
// up there that gets read rather than glanced at.
Pill {
    Text {
        text: Qt.formatDateTime(ticker.now, "HH:mm")
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLarge
        font.bold: true
    }

    Text {
        text: Qt.formatDateTime(ticker.now, "ddd d MMM")
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // One tick a minute is enough for a clock that shows no seconds, and the
    // first tick is on start so the bar does not open with an empty pill.
    Timer {
        id: ticker
        property date now: new Date()
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: now = new Date()
    }
}
