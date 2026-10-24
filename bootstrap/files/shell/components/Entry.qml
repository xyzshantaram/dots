import QtQuick
import "../core"

// One row in a list of things you can join: a surface, orange while it is the
// current one, a chevron to join and a cross to leave.
//
// The cross becomes a check on the first click, because disconnecting on one
// stray click is not something to make easy. A row that is not something you
// can leave — a power profile — shows a tick instead and applies immediately.
//
// Width comes from the parent column; the row is as wide as the list.
Column {
    id: entry

    required property string title
    required property bool isActive
    required property string glyph
    /** Small text before the action, for a lock or a state. */
    property string hint: ""
    required property var action

    property bool confirming: false
    /** Whether the action on the current row is something to confirm. */
    property bool confirms: true
    /** The glyph on the current row: a cross, or a tick where a row cannot be
     *  left. */
    property string activeGlyph: "\uf00d"

    width: parent ? parent.width : 0
    spacing: 4

    Rectangle {
        id: entryRow

        width: parent.width
        height: 36
        radius: 10
        color: entryArea.containsMouse ? Theme.surfacePill : Theme.surface
        border.width: entry.isActive ? 2 : 0
        border.color: Theme.alert

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: entryGlyph

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: entry.glyph
            color: entry.isActive ? Theme.text : Theme.textMuted
            font.family: Theme.iconFont
            font.pixelSize: Theme.iconSize
        }

        Text {
            anchors.left: entryGlyph.right
            anchors.leftMargin: 10
            anchors.right: entryHint.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: entry.title
            color: entry.isActive ? Theme.text : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }

        Text {
            id: entryHint

            anchors.right: entryAction.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: entry.hint
            color: entry.isActive ? Theme.alert : Theme.textDim
            font.family: entry.hint === "\uf023" ? Theme.iconFont : Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: entryAction

            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: entry.isActive ? (entry.confirming ? "\uf00c" : entry.activeGlyph) : "\uf054"
            color: entry.isActive ? Theme.alert : Theme.textDim
            font.family: Theme.iconFont
            font.pixelSize: entry.confirming ? Theme.fontSize + 3 : Theme.fontSizeSmall
            font.bold: entry.confirming

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: entry.click()
            }
        }

        MouseArea {
            id: entryArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: entry.click()
        }
    }

    Timer {
        id: confirm
        interval: 2500
        onTriggered: entry.confirming = false
    }

    function click(): void {
        if (!entry.isActive || !entry.confirms) {
            entry.action();
            return;
        }
        if (entry.confirming) {
            entry.confirming = false;
            entry.action();
            return;
        }
        entry.confirming = true;
        confirm.restart();
    }
}
