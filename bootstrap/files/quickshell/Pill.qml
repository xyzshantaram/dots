import QtQuick
import QtQuick.Layouts

// Every element in the bar sits on one of these: a dark purple pill.
//
// One file for the surface, because the alternative is the radius, the padding
// and the fill drifting apart between the clock and the metrics, which is the
// state the shell this borrows its layout from ended up in.
Rectangle {
    id: root

    /// Children land in the row inside the pill.
    default property alias content: row.data
    property int padding: 4
    property int spacing: Theme.gap / 2

    // Take the bar's height rather than arguing with it. A pill sized purely by
    // its contents is taller than the strip it sits in as soon as the text
    // grows, and the bar window clips rather than complains.
    Layout.fillHeight: true

    color: Theme.surfacePill
    // Fully rounded, so it stays a pill at any height.
    radius: Theme.pillRadius
    implicitWidth: row.implicitWidth + padding * 2
    implicitHeight: row.implicitHeight + padding * 2

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: root.spacing
    }
}
