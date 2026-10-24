import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import "../core"

// One notification, drawn the same way in the panel list and in the banner.
//
// Orange on the outside and nothing else: the card is one surface with a darker
// strip along the bottom for the sender's actions, so the parts are separated by
// tone rather than by lines. The close is an X on the app's line, not a button —
// dismissing is not one of the sender's actions, and a button beside "Reply"
// reads as one.
Rectangle {
    id: card

    required property var note

    /** critical, normal, low — UPower's own vocabulary. */
    readonly property int urgency: card.note?.urgency ?? 1
    readonly property var actions: card.note?.actions ?? []
    readonly property string body: card.note?.body ?? ""
    readonly property string summary: card.note?.summary ?? ""
    readonly property bool hasReply: (card.note?.hasInlineReply ?? false)
        || card.actions.some((a) => a.identifier === "reply")
    /** The actions worth a button: "default" is the card itself. */
    readonly property var buttons: card.actions.filter(
        (a) => a.identifier !== "default"
            && !(card.replying && a.identifier === "reply"))
    readonly property bool hasStrip: card.buttons.length > 0 || card.replying

    /** The reply field is not shown until Reply is pressed. */
    property bool replying: false

    /** Send what is in the reply field and clear the notification away: an
     *  answered notification has no business staying on screen. */
    function send(text): void {
        const trimmed = String(text ?? "").trim();
        if (trimmed === "") return;
        card.note.sendInlineReply(trimmed);
        card.note.dismiss();
        reply.text = "";
    }

    width: parent ? parent.width : 0
    implicitHeight: 12 + content.implicitHeight + 10 + strip.height
    radius: 12
    // The middle tone of the three: the panel behind it is surfaceRaised, the
    // action strip surface. The outline is drawn over everything instead of by
    // the card itself, so it is not interrupted where the strip meets the edge.
    color: Theme.surfacePill

    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.alert
        z: 10
    }

    Column {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        spacing: 8

        // An Item, not a Row: the name anchors to the close on its right, and
        // anchors inside a positioner are undefined — the name came out with no
        // width and no app was ever drawn.
        Item {
            width: parent.width
            height: 20

            // The app's own icon, which is a themed name rather than a path.
            IconImage {
                id: appIcon

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 18 : 0
                height: 18
                // appIcon is a themed name, not a path: it has to go through the
                // icon theme lookup or IconImage has nothing to open.
                source: card.note?.appIcon ? Quickshell.iconPath(card.note.appIcon, true) : ""
                visible: (card.note?.appIcon ?? "") !== ""
            }

            Text {
                anchors.left: appIcon.right
                anchors.leftMargin: 8
                anchors.right: close.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: card.note?.appName ?? ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                id: close

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf00d"   // times
                color: closeArea.containsMouse ? Theme.text : Theme.textMuted
                font.family: Theme.iconFont
                font.pixelSize: Theme.fontSize

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.note.dismiss()
                }
            }
        }

        Text {
            visible: text !== ""
            width: parent.width
            // The sender's two fields read as one sentence, which is how every
            // messaging client puts them: "Mom: Hey, how are you?"
            text: card.summary !== "" && card.body !== ""
                ? `${card.summary}: ${card.body}`
                : (card.summary || card.body)
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // The attachment, when the sender included one.
        Image {
            visible: (card.note?.image ?? "") !== ""
            width: parent.width
            height: visible ? sourceSize.height : 0
            source: card.note?.image ?? ""
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 312
            asynchronous: true
        }
    }

    // The action strip: darker than the body, rounded only at the bottom, so the
    // card still reads as one shape with no line across it.
    Rectangle {
        id: strip

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: card.hasStrip ? actionsRow.implicitHeight + 16 : 0
        visible: card.hasStrip
        color: Theme.surface
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: 11
        bottomRightRadius: 11

        Column {
            id: actionsRow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            // The sender's actions, centred. Each is the sender's own label and
            // the sender's own verb — invoke() is the notification's.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                visible: card.buttons.length > 0

                Repeater {
                    model: card.buttons

                    Rectangle {
                        id: action

                        required property var modelData

                        width: actionText.implicitWidth + 20
                        height: 26
                        radius: 8
                        color: actionArea.containsMouse ? Theme.calmBright : Theme.calm

                        Text {
                            id: actionText
                            anchors.centerIn: parent
                            text: action.modelData?.text ?? ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        MouseArea {
                            id: actionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Reply opens the field rather than invoking the
                            // action; the field is what the action is for.
                            onClicked: action.modelData.identifier === "reply"
                                ? card.replying = true
                                : action.modelData.invoke()
                        }
                    }
                }
            }

            // Reply in place, with a send button beside it. Enter works too,
            // but a field with nothing to press reads as unfinished.
            Row {
                visible: card.replying
                width: parent.width
                height: visible ? 30 : 0
                spacing: 8

                TextField {
                    id: reply

                    // Ready to type the moment Reply is pressed.
                    focus: visible
                    width: parent.width - send.width - parent.spacing
                    height: 30
                    placeholderText: card.note?.inlineReplyPlaceholder ?? "Reply"
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    selectByMouse: true

                    background: Rectangle {
                        radius: 8
                        color: Theme.surfacePill
                        border.width: 1
                        border.color: reply.activeFocus ? Theme.calmBright : Theme.border
                    }

                    onAccepted: card.send(reply.text)
                }

                Rectangle {
                    id: send

                    width: sendLabel.implicitWidth + 20
                    height: 30
                    radius: 8
                    color: reply.text.trim() === ""
                        ? Theme.surfacePill
                        : (sendArea.containsMouse ? Theme.calmBright : Theme.calm)

                    Text {
                        id: sendLabel
                        anchors.centerIn: parent
                        text: "Send"
                        color: reply.text.trim() === "" ? Theme.textDim : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        id: sendArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.send(reply.text)
                    }
                }
            }
        }
    }
}
