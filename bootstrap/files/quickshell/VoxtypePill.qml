import QtQuick
import QtQuick.Layouts
import "services"

// The dictation pill, and only when there is something to say.
//
// Idle means it is not on screen at all — the bar should not carry a permanent
// "everything is fine" light. Recording is the orange microphone with a red dot
// pulsing beside it; processing is a white spinner.
//
// Both colours are deliberately outside the calm/alert ramp: "the microphone is
// open" is a different statement from "something needs attention", and mixing
// the two would make the ramp mean two things.
Pill {
    visible: Voxtype.busy

    Text {
        // The microphone is the constant: it says what the pill is about. It
        // stays for as long as the daemon is busy, whether it is taking audio
        // or working on what it already took.
        visible: Voxtype.busy
        text: "\uf130"   // nf-fa-microphone
        color: Theme.alert
        font.family: Theme.iconFont
        font.pixelSize: Theme.iconSize
    }

    // The dot breathes rather than blinks: a hard on/off reads as an error
    // indicator, a fade reads as something happening. Only while capturing —
    // once the microphone is closed there is nothing to warn about.
    Rectangle {
        visible: Voxtype.recording
        Layout.alignment: Qt.AlignVCenter
        width: 8
        height: 8
        radius: 4
        color: Theme.recording

        SequentialAnimation on opacity {
            running: Voxtype.recording
            loops: Animation.Infinite
            NumberAnimation { to: 0.2; duration: 520; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutQuad }
        }
    }

    Text {
        visible: Voxtype.processing
        text: "\uf110"   // nf-fa-spinner
        color: Theme.text
        font.family: Theme.iconFont
        font.pixelSize: Theme.iconSize
        // Centred on itself, or the glyph orbits the corner of its box.
        transformOrigin: Item.Center

        RotationAnimator on rotation {
            running: Voxtype.processing
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 1200
        }
    }
}
