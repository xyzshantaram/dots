import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../core"

// One per output. Blurred desktop wallpaper — the image swaybg is showing,
// read from the same state file WezTerm uses — clock, date, password.

WlSessionLockSurface {
    id: surface

    // A transparent WlSessionLockSurface is buggy, so black underneath.
    color: "black"

    property string wall: ""

    // A plain Timer, not SystemClock: SystemClock's timer is monotonic and
    // does not recover from hibernate, which leaves a stale clock on a lock
    // screen. new Date() reads the system clock on the next tick.
    property var now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: surface.now = new Date()
    }

    // The image the desktop is showing, not a new random one. wallpaper-random
    // records its pick in $XDG_RUNTIME_DIR/current-wallpaper and WezTerm reads
    // the same file; this surface is per output, so reading one path is also
    // what keeps two monitors from locking onto different images.
    Process {
        id: desktopWall
        command: ["sh", "-c", "cat \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/current-wallpaper\" 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: surface.wall = text.trim()
        }
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        source: surface.wall === "" ? "" : "file://" + surface.wall
        visible: surface.wall !== ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: surface.width
        sourceSize.height: surface.height

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            blurMultiplier: 1.0
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !wallpaper.visible
        color: Theme.surface
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        opacity: 0.45
    }

    Column {
        anchors.centerIn: parent
        spacing: 16

        Item {
            id: clockBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: clockRow.width
            height: clockRow.height

            Row {
                id: clockRow
                spacing: 0

                Text {
                    text: Qt.formatDateTime(surface.now, "HH")
                    color: Theme.text
                    font.family: "Inter Display"
                    font.pixelSize: 144
                    font.weight: Font.Light
                }
                Text {
                    text: ":"
                    color: Theme.text
                    opacity: 0.35
                    font.family: "Inter Display"
                    font.pixelSize: 144
                    font.weight: Font.Light
                }
                Text {
                    text: Qt.formatDateTime(surface.now, "mm")
                    color: Theme.text
                    font.family: "Inter Display"
                    font.pixelSize: 144
                    font.weight: Font.Light
                }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowVerticalOffset: 4
                shadowBlur: 1.0
                shadowOpacity: 0.45
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(surface.now, "dddd · MMMM d")
            color: Theme.text
            opacity: 0.85
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.letterSpacing: 0.5
        }

        Rectangle {
            id: inputCard
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360
            height: inputCol.height + 32
            radius: Theme.radiusCard
            color: Qt.rgba(1, 1, 1, 0.10)
            border.color: Qt.rgba(1, 1, 1, 0.18)
            border.width: 1

            Column {
                id: inputCol
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 16
                    rightMargin: 16
                }
                spacing: 10

                Rectangle {
                    id: pwBox
                    width: parent.width
                    height: 40
                    radius: Theme.radiusSmall
                    color: Qt.rgba(0, 0, 0, 0.45)
                    opacity: LockService.pamChecking ? 0.45 : 1.0

                    border.width: 1
                    border.color: LockService.pamError !== ""
                        ? Theme.alert
                        : (passField.activeFocus ? Theme.text : Qt.rgba(1, 1, 1, 0.20))

                    TextInput {
                        id: passField
                        anchors {
                            fill: parent
                            leftMargin: 14
                            rightMargin: 14
                        }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLarge
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        selectByMouse: false
                        clip: true
                        readOnly: LockService.pamChecking
                        Component.onCompleted: forceActiveFocus()

                        Keys.onPressed: event => {
                            if (event.isAutoRepeat) {
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (!LockService.pamChecking && passField.text.length > 0)
                                    LockService.respond(passField.text);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                if (!LockService.pamChecking) passField.text = "";
                                event.accepted = true;
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: LockService.pamError !== ""
                        ? LockService.pamError
                        : (LockService.pamMessage || "Locked")
                    color: LockService.pamError !== "" ? Theme.alert : Theme.text
                    opacity: LockService.pamError !== "" ? 1.0 : 0.7
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }

    // Two actions, 200 above the bottom edge, each asking twice.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 200
        spacing: 12

        LockAction {
            label: "Shut Down"
            glyph: "\uDB81\uDC25"
            command: ["systemctl", "poweroff"]
        }

        LockAction {
            label: "Sleep"
            glyph: "\uDB82\uDD04"
            command: ["systemctl", "hibernate"]
        }
    }

    Connections {
        target: LockService

        function onLockedChanged() {
            if (LockService.locked) {
                passField.text = "";
                Qt.callLater(() => passField.forceActiveFocus());
            }
        }

        function onPamErrorChanged() {
            if (LockService.pamError !== "") {
                passField.text = "";
                Qt.callLater(() => passField.forceActiveFocus());
            }
        }
    }
}
