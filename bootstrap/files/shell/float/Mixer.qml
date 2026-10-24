import "../core"
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../services"

// The volume mixer.
//
// Two sections: the output with its devices and the applications playing into
// it, then the input with its sources. Per section a mute button, a level and
// the list you can pick from.
//
// A real PopupWindow rather than a panel drawn in the bar's headroom, because
// this one is tall: the headroom exists for tooltips and short menus, and a
// mixer that grows with the number of running applications does not belong in
// a fixed strip. The reference this borrows from anchors its popups exactly
// this way, so the anchor maths below is theirs.
PopupWindow {
    id: root

    required property Item anchorItem

    color: "transparent"
    implicitWidth: 336
    // body.height, not body.implicitHeight: a Rectangle's implicit height is
    // zero, so asking for it sized this popup to the padding alone and clipped
    // everything inside it.
    implicitHeight: body.height + 16

    anchor.item: root.anchorItem
    anchor.rect.x: root.anchorItem ? -(root.width - root.anchorItem.width) / 2 : 0
    anchor.rect.y: root.anchorItem ? root.anchorItem.height + 4 : 0
    anchor.adjustment: PopupAdjustment.SlideX

    /**
     * A mute button, a level and a percentage. The track is 4px so a row stays
     * one line tall, and the whole width of it is draggable: a 4px target is
     * not something to ask anyone to hit.
     */
    component Level: Row {
        id: levelRow

        required property var node

        /** "output" or "input": which glyphs the mute button uses. */
        property string kind: "output"

        spacing: 8

        readonly property bool isMuted: levelRow.node?.audio?.muted ?? false
        readonly property real value: levelRow.node?.audio?.volume ?? 0
        readonly property bool isInput: levelRow.kind === "input"

        Rectangle {
            width: 24
            height: 24
            radius: 6
            color: muteArea.containsMouse ? Theme.surface : "transparent"

            Text {
                anchors.centerIn: parent

                // A microphone for the input, a speaker for the output. Both
                // crossed out when muted, and both at the bar's glyph size — at
                // text size they read as specks beside the track.
                text: levelRow.isInput
                    ? (levelRow.isMuted ? "\uDB80\uDF6D" : "\uDB80\uDF6C")     // mic-off / mic
                    : (levelRow.isMuted ? "\uDB81\uDF5F" : "\uf028")           // volume-mute / volume-high
                color: levelRow.isMuted ? Theme.alert : Theme.text
                font.family: Theme.iconFont
                font.pixelSize: Theme.glyphSize
            }

            MouseArea {
                id: muteArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (levelRow.node?.audio) levelRow.node.audio.muted = !levelRow.node.audio.muted
                }
            }
        }

        Item {
            id: track
            width: levelRow.width - 24 - percentage.width - levelRow.spacing * 2
            height: 16

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Theme.border
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * Math.max(0, Math.min(1, levelRow.value))
                height: 4
                radius: 2
                color: levelRow.isMuted ? Theme.alert : Theme.text
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width * Math.max(0, Math.min(1, levelRow.value)) - width / 2
                width: 12
                height: 12
                radius: 6
                color: Theme.text
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // Widen the hit area vertically without widening the track.
                anchors.topMargin: -4
                anchors.bottomMargin: -4

                function setFrom(x) {
                    if (!levelRow.node?.audio) return
                    levelRow.node.audio.volume = Math.max(0, Math.min(1, x / width))
                }
                onPressed: (mouse) => setFrom(mouse.x)
                onPositionChanged: (mouse) => { if (pressed) setFrom(mouse.x) }
            }
        }

        Text {
            id: percentage
            width: 34
            text: `${Math.round(levelRow.value * 100)}%`
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignRight
        }
    }

    Rectangle {
        id: body

        width: parent.width
        height: column.implicitHeight + 28
        color: Theme.surfaceRaised
        radius: Theme.radiusSmall
        border.width: 1
        border.color: Theme.border

        Column {
            id: column
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            // ---- output
            Text {
                text: "OUTPUT"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Level {
                width: column.width
                node: Audio.sink
            }

            Repeater {
                model: Audio.sinks

                // A plain delegate rather than an inline component. With a
                // component delegate the rows received an object carrying a
                // single `name` — eDP-1, a niri output — and nothing else of a
                // node. Everything undefined but a name is not a PipeWire node,
                // whatever it was; reading modelData directly here works.
                Item {
                    required property var modelData

                    width: column.width
                    height: 36

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        // A surface, like the rows in the control centre, an
                        // orange ring on the one everything is playing into,
                        // and a shade lighter under the pointer.
                        color: sinkArea.containsMouse ? Theme.surfacePill : Theme.surface
                        border.width: modelData === Audio.sink ? 2 : 0
                        border.color: Theme.alert
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: sinkMark.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: Audio.label(modelData, "")
                        color: modelData === Audio.sink ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                    }

                    Text {
                        id: sinkMark
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData === Audio.sink ? "default" : ""
                        color: Theme.alert
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        id: sinkArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.makeDefault(modelData, true)
                    }
                }
            }

            // ---- input
            Rectangle {
                width: column.width
                height: 1
                color: Theme.border
            }

            Text {
                text: "INPUT"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Level {
                width: column.width
                node: Audio.source
                kind: "input"
            }

            Repeater {
                model: Audio.sources

                Item {
                    required property var modelData

                    width: column.width
                    height: 36

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: sourceArea.containsMouse ? Theme.surfacePill : Theme.surface
                        border.width: modelData === Audio.source ? 2 : 0
                        border.color: Theme.alert
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: sourceMark.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: Audio.label(modelData, "")
                        color: modelData === Audio.source ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                    }

                    Text {
                        id: sourceMark
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData === Audio.source ? "default" : ""
                        color: Theme.alert
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        id: sourceArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.makeDefault(modelData, false)
                    }
                }
            }

            // A rule between every pair of sections. The separator before the
            // input section was the only one; three sections need two.
            Rectangle {
                width: column.width
                height: 1
                color: Theme.border
            }

            // ---- applications, last: the two devices are what you come here to
            // set, and what is playing is the detail underneath them.
            Text {
                visible: Audio.streams.length > 0
                text: "APPLICATIONS"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                topPadding: 6
            }

            Repeater {
                model: Audio.streams

                Row {
                    required property var modelData
                    width: column.width
                    spacing: 8

                    Text {
                        width: 84
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.properties?.["application.name"] ?? "application"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }

                    Level {
                        width: parent.width - 84 - parent.spacing
                        node: modelData
                    }
                }
            }
        }
    }
}
