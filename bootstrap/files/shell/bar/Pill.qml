import "../core"
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

    // Horizontal padding is the wider of the two. Text needs room at its ends
    // in a way it does not need above and below, where the strip's own margin
    // already surrounds it.
    property int paddingX: 8
    property int paddingY: 4
    property int spacing: Theme.gap / 2

    color: Theme.surfacePill
    // Fully rounded, so it stays a pill at any height.
    radius: Theme.pillRadius

    // Every pill takes the strip's height, minus the layout's margins, so they
    // are all exactly as tall as each other. Sized by contents instead, the
    // clock ran taller than the window title and the two stopped lining up.
    //
    // This is why Theme.barHeight has to be at least the tallest pill's own
    // height plus twice the margin: the pill is stretched to whatever is left,
    // and there is no second chance to be clipped out of it.
    Layout.fillHeight: true

    implicitWidth: row.implicitWidth + paddingX * 2
    implicitHeight: row.implicitHeight + paddingY * 2

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: root.spacing
    }
}
