import QtQuick
// TextField is a Controls type, not a QtQuick one. Without this the whole shell
// fails to load with "Type Toasts unavailable" — the same class of mistake as
// the missing QtQuick.Layouts import on BatteryPill earlier.
import QtQuick.Controls
import Quickshell.Widgets
import ".."
import "../core"

// Notification banners, at the control centre's top edge and stacking down.
//
// The position is not a style choice, so it is derived rather than typed in
// twice: the control centre anchors to the chevron with `height + 8` below it
// and eight in from its right edge, and these line up with exactly that. Move
// the panel and the banners follow, because both read the same numbers off the
// same widget.
//
// They are Items in the shell's own window rather than another PopupWindow,
// which is what lets them stack in ordinary z-order against the catcher and the
// panel. A second layer-shell surface would have the same undefined ordering
// problem every other float had.
//
// The body of each banner is the same card the control centre draws, down to
// the tokens — surface, radius, border, type sizes — because two renderings of
// one notification that look different would be worse than either alone. Worth
// extracting into a component when there is a third caller.
Item {
    id: root

    /** The widget the control centre hangs off: the menudown chevron. */
    required property Item anchor

    required property var server

    readonly property var notes: root.server?.trackedNotifications?.values ?? []

    /** The same numbers ControlCentre.qml anchors with. */
    readonly property int inset: 8
    readonly property real anchorX: root.anchor ? root.anchor.mapToItem(null, 0, 0).x : 0
    readonly property real anchorY: root.anchor ? root.anchor.mapToItem(null, 0, 0).y : 0

    visible: root.notes.length > 0
    z: 7

    width: 336
    x: root.anchorX + root.anchor.width - width - root.inset
    y: root.anchorY + root.anchor.height + root.inset

    /** Full-width, right at the top: the newest notification is the one you
     *  just received, and it should not be at the bottom of the pile. */
    Column {
        width: parent.width
        spacing: root.inset

        Repeater {
            model: root.notes

            Rectangle {
                id: banner

                required property var modelData

                /** critical, normal, low — UPower's own vocabulary. */
                readonly property int urgency: modelData?.urgency ?? 1
                readonly property var actions: modelData?.actions ?? []

                width: 336
                height: card.implicitHeight + 20
                radius: Theme.radiusSmall
                color: Theme.surfaceRaised
                border.width: 1
                // Critical gets the alert colour on the edge, not the fill: a
                // red panel is unreadable, and an outlined one still says which
                // notification it is.
                border.color: banner.urgency === 2 ? Theme.alert : Theme.border

                Column {
                    id: card

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 4

                    Row {
                        width: parent.width
                        spacing: 8

                        // The app's own icon, which is a themed name rather
                        // than a path, so it goes through IconImage. The empty
                        // Box keeps a missing icon from shifting the text.
                        IconImage {
                            width: 20
                            height: 20
                            anchors.verticalCenter: parent.verticalCenter
                            source: banner.modelData?.appIcon ?? ""
                            visible: banner.modelData?.appIcon ?? "" !== ""
                        }

                        Text {
                            width: parent.width - 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${banner.modelData?.appName ?? ""} · ${banner.modelData?.summary ?? ""}`
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        visible: (banner.modelData?.body ?? "") !== ""
                        width: parent.width
                        text: banner.modelData?.body ?? ""
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    // The attachment, when the sender included one. Height only
                    // when there is one, so a thumbnailless notification is not
                    // padded out with an empty box.
                    Image {
                        visible: (banner.modelData?.image ?? "") !== ""
                        width: parent.width
                        height: visible ? sourceSize.height : 0
                        source: banner.modelData?.image ?? ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 316
                        asynchronous: true
                    }

                    // Inline actions. Each is the sender's own label and the
                    // sender's own verb — invoke() is the notification's, and
                    // takes the action, rather than the action invoking itself.
                    Flow {
                        width: parent.width
                        spacing: 6
                        visible: banner.actions.length > 0

                        Repeater {
                            model: banner.actions

                            Rectangle {
                                id: action

                                required property var modelData

                                width: actionText.implicitWidth + 16
                                height: 24
                                radius: 6
                                color: actionArea.containsMouse ? Theme.calmDeep : Theme.surface
                                border.width: 1
                                border.color: Theme.border

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
                                    onClicked: banner.modelData.invoke(action.modelData)
                                }
                            }
                        }
                    }

                    // Reply in place, for the senders that advertise it. The
                    // field needs keyboard focus, which the shell asks for with
                    // WlrKeyboardFocus.OnDemand; whether a click into it is
                    // enough to get focus on niri is the part to check.
                    TextField {
                        id: reply
                        visible: banner.modelData?.hasInlineReply ?? false
                        width: parent.width
                        height: visible ? 28 : 0
                        placeholderText: banner.modelData?.inlineReplyPlaceholder ?? "Reply"
                        color: Theme.text
                        placeholderTextColor: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        selectByMouse: true
                        background: Rectangle {
                            radius: 6
                            color: Theme.surface
                            border.width: 1
                            border.color: reply.activeFocus ? Theme.calm : Theme.border
                        }
                        onAccepted: {
                            banner.modelData.replyText = reply.text
                            banner.modelData.sendInlineReply()
                            reply.text = ""
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    // Under the actions and the reply field: a click meant for
                    // either of those must not dismiss the whole banner.
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: banner.modelData.dismiss()
                }
            }
        }
    }
}
