import "../core"
import QtQuick
import QtQuick.Layouts

// Time and date, leftmost on the bar.
//
// HH:MM in bold, then the seconds at the same size in regular weight — a single
// Text cannot change weight part-way through, so the clock is three of them.
// The seconds hug the minutes; the day and date sit a gap away.
//
// White type on a surface that carries the evening warmth.
Pill {
    // The evening walk, now on the surface rather than the type. Purple at
    // 22:00, orange by 09:00, and back to purple when the window ends.
    attention: Math.pow(Situation.clockTint(ticker.now), Situation.eveningWeight)

    RowLayout {
        spacing: 1

        Text {
            text: Qt.formatDateTime(ticker.now, "HH:mm")
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLarge
            font.bold: true
        }

        Text {
            // The colon rides with the seconds. Bold stops at the minutes, as
            // asked, and a bare "12" after "04:33" reads as a separate number.
            // Grey: it is the part that changes every second, and the eye
            // should not be pulled to it.
            text: `:${Qt.formatDateTime(ticker.now, "ss")}`
            // Grey, like the year: the recessed parts stay neutral while the
            // bold ones carry the time of day.
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLarge
        }
    }

    // The day and the date in bold, the year not: bold, regular, bold across
    // three Texts, because a single Text cannot change weight mid-string.
    RowLayout {
        spacing: 0

        Text {
            text: Qt.formatDateTime(ticker.now, "ddd")
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Text {
            // The hyphen goes with the year, not with the date: the bold run
            // starts at the month, so the separator stays in the greyed part.
            text: Qt.formatDateTime(ticker.now, " yyyy-")
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Text {
            text: Qt.formatDateTime(ticker.now, "MM-dd")
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
    }

    // One tick a second now that the seconds are shown, and the first tick on
    // start so the bar does not open with an empty pill.
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
