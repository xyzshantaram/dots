import "../core"
import "../services"
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// The dock: bottom edge, centred, autohiding, one icon per app that has a
// window.
//
// Its own PanelWindow rather than a region inside the shell's window. The shell
// is one full-screen surface whose mask is a union of rectangles, and hiding a
// 56px plate at the bottom of it means adding a trigger strip to that union and
// keeping its arithmetic right while the plate slides. A surface anchored to the
// bottom edge is the same thing niri already knows how to place: it reserves a
// two-pixel exclusive zone, so the sliver that summons the dock is both visible
// and hittable, and the mask below only ever describes the plate.
//
// The window is taller than the plate on purpose: the hover list opens above
// the plate, and a layer surface cannot draw outside its own geometry.
PanelWindow {
    id: dock

    /** A float is open over the strip; the dock has no business being up. */
    required property bool suppressed

    /** The output this dock is drawn on. Its windows are the ones in the plate. */
    required property string outputName

    // ---- geometry --------------------------------------------------------

    readonly property int cellSize: 44
    readonly property int cellGap: 6
    readonly property int pad: 8
    readonly property int iconArea: 56

    /**
     * The dot rail is tight against the icons — four pixels under the artwork,
     * three under the dots. Anything looser reads as a separate band.
     */
    readonly property int dotsTop: iconArea - 5
    readonly property int plateHeight: dotsTop + 7
    /** Room above the plate for the hover list: five rows and their padding. */
    readonly property int headroom: 148

    /** Two pixels of plate stay on screen while it is away: the trigger. */
    readonly property int peek: 2

    /**
     * The base flares out into the screen edge instead of rounding off: the
     * plate's bottom corners turn away from it, so the dock reads as sitting on
     * the edge rather than floating above it. Drawn outside the plate, which is
     * why the window is this much wider than it.
     */
    readonly property int flare: 8

    readonly property int plateWidth: Math.max(pad * 2, Math.min(
        dock.screen ? dock.screen.width - 48 - flare * 2 : 1200,
        groups.length * cellSize + Math.max(0, groups.length - 1) * cellGap + pad * 2))

    readonly property real plateX: (width - plateWidth) / 2
    readonly property real plateTop: height - plateHeight + drop

    // The plate slides; `drop` is how far down it currently is. Two pixels stay
    // on screen while it is away, and those two pixels are the trigger.
    property real drop: shown ? 0 : plateHeight - peek
    Behavior on drop {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    readonly property real maskTop: Math.min(plateTop, height - peek)

    /**
     * The whole outline as one path: a Rectangle can only round all four
     * corners, and the base is not rounded. It turns outward into the screen
     * edge, so fill and hairline have to describe the same shape.
     */
    readonly property string silhouette: {
        const l = plateX
        const r = plateX + plateWidth
        const t = plateTop
        const b = plateTop + plateHeight
        const rad = Theme.radiusSmall
        const f = flare

        const p = ["M " + (l + rad) + " " + t, "L " + (r - rad) + " " + t]
        p.push("A " + rad + " " + rad + " 0 0 1 " + r + " " + (t + rad))
        p.push("L " + r + " " + (b - f))
        // Concave: the corner sweeps away from the plate, not around it.
        p.push("A " + f + " " + f + " 0 0 0 " + (r + f) + " " + b)
        p.push("L " + (l - f) + " " + b)
        p.push("A " + f + " " + f + " 0 0 0 " + l + " " + (b - f))
        p.push("L " + l + " " + (t + rad))
        p.push("A " + rad + " " + rad + " 0 0 1 " + (l + rad) + " " + t)
        p.push("Z")
        return p.join(" ")
    }

    property bool shown: false

    color: "transparent"
    implicitWidth: Math.max(plateWidth, 288) + flare * 2 + 2
    implicitHeight: plateHeight + headroom

    // Bottom edge only, so niri centres the surface horizontally.
    anchors.bottom: true
    margins.bottom: 0
    exclusiveZone: peek

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The plate, plus the hover list while it is up. Everything else in the
    // window — the headroom, and the plate while it is away — clicks through.
    mask: Region {
        x: dock.plateX - dock.flare
        y: dock.maskTop
        width: dock.plateWidth + dock.flare * 2
        height: dock.height - dock.maskTop

        Region {
            x: hoverList.x
            y: hoverList.y
            width: hoverList.visible ? hoverList.width : 0
            height: hoverList.visible ? hoverList.height : 0
        }
    }

    // ---- when it shows ---------------------------------------------------

    /**
     * A window on this output fills it, so there is nothing for the dock to
     * add. Any window on the output, not just the focused one: a fullscreen
     * window keeps the other monitor's dock hidden when the pointer moves away.
     */
    readonly property bool covered: {
        const out = Niri.outputByName(dock.outputName)
        if (!out) return false
        return Niri.windowsOn(dock.outputName).some(
            (w) => w.layout.window_size[1] >= out.logical.height)
    }

    // No windows, a fullscreen window, or a float over the strip: nothing to
    // draw, and no sliver either.
    visible: groups.length > 0 && !covered && !suppressed

    onVisibleChanged: if (!visible) {
        shown = false
        listIndex = -1
        hoveredIndex = -1
    }

    HoverHandler {
        id: pointer
        // Only the mask delivers hover, so this is true exactly while the
        // pointer is on the plate or the list — including the two-pixel sliver.
        onHoveredChanged: {
            if (hovered) {
                hideTimer.stop()
                dock.shown = true
            } else {
                hideTimer.restart()
            }
        }
    }

    // Crossing from an icon to the list passes a gap where neither is under the
    // pointer; without the timer the dock would drop out from under it.
    Timer {
        id: hideTimer
        // While a list is open the dock has to wait at least as long as the
        // list's own grace period, or it would drop away mid-crossing.
        interval: dock.listIndex >= 0 ? 520 : 300
        onTriggered: {
            dock.shown = false
            dock.listIndex = -1
        }
    }

    // ---- the windows, grouped by app -------------------------------------

    /**
     * The desktop entry for a window's app id.
     *
     * byId is the right lookup and usually enough, but a launcher that wraps an
     * app reports its own id while the window reports the app's: Spotify's
     * window says "spotify" and the only entry is spotify-launcher.desktop,
     * which carries StartupWMClass=spotify. Without the second pass its icon is
     * a letter in a square.
     */
    function entryFor(appId): var {
        if (!appId) return null

        const exact = DesktopEntries.byId(appId)
        if (exact) return exact

        const apps = DesktopEntries.applications.values || []
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i]
            if (e && e.startupClass && e.startupClass === appId) return e
        }
        // Nothing declares the class: a launcher named after the app it starts.
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i]
            if (e && e.id && e.id.indexOf(appId) === 0) return e
        }
        return null
    }

    readonly property var groups: {
        const map = {}
        const owned = Niri.windowsOn(dock.outputName)
        for (let i = 0; i < owned.length; i++) {
            const w = owned[i]
            // A stray XWayland window has no app id; group it under its title so
            // it still gets a slot rather than vanishing.
            const key = w.app_id || w.title || "window"
            let g = map[key]
            if (!g) {
                g = {
                    key: key,
                    appId: w.app_id || "",
                    title: w.title || "",
                    windows: [],
                    focused: false
                }
                map[key] = g
            }
            g.windows.push(w)
            if (w.is_focused) g.focused = true
        }

        const out = []
        for (const k in map) {
            const g = map[k]
            // niri returns creation order and ids are monotonic, so newest first.
            g.windows.sort((a, b) => b.id - a.id)
            out.push(g)
        }
        out.sort((a, b) => b.windows[0].id - a.windows[0].id)

        for (let i = 0; i < out.length; i++) {
            const g = out[i]
            const entry = entryFor(g.appId)
            // The entry's icon first; otherwise the app id itself may be a
            // themed icon name.
            let source = entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
            if (source === "" && g.appId) source = Quickshell.iconPath(g.appId, true)
            g.icon = source
            g.letter = (entry && entry.name ? entry.name : (g.appId || g.title))
                .charAt(0).toUpperCase()
        }
        return out
    }

    // ---- pointer state ---------------------------------------------------

    /** Index of the icon under the pointer, or -1. */
    property int hoveredIndex: -1

    /**
     * The icon whose window list is open, or -1.
     *
     * Separate from hoveredIndex because the pointer leaves the icon on its way
     * up to the list: clearing the list the moment the icon is left made
     * reaching it impossible. This one only closes after a grace period, or
     * when the dock itself goes away.
     */
    property int listIndex: -1

    readonly property var listGroup:
        listIndex >= 0 && listIndex < groups.length ? groups[listIndex] : null

    /** Neighbours grow too, less with distance: the strip magnifies, not one cell. */
    function scaleFor(index): real {
        if (hoveredIndex < 0) return 1
        const d = Math.abs(index - hoveredIndex)
        return 1 + 0.42 * Math.exp(-(d * d) / 1.4)
    }

    function focusGroup(group): void {
        if (!group || group.windows.length === 0) return
        Niri.action(["focus-window", "--id", String(group.windows[0].id)])
        listIndex = -1
    }

    function closeList(): void {
        listIndex = -1
        hoveredIndex = -1
    }

    Timer {
        id: openTimer
        interval: 400
        onTriggered: if (dock.hoveredIndex >= 0) dock.listIndex = dock.hoveredIndex
    }

    // Long enough to cross the gap to the list, short enough that leaving the
    // dock does not leave the list hanging.
    Timer {
        id: listCloseTimer
        interval: 500
        onTriggered: dock.closeList()
    }

    // ---- the plate -------------------------------------------------------

    Shape {
        id: silhouetteShape

        x: 0
        y: 0
        width: dock.width
        height: dock.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            // The panels' surface, not the pill's: the dock is a card like the
            // control centre and the mixer, and reads as one.
            fillColor: Theme.surfaceRaised
            strokeColor: Theme.border
            strokeWidth: 1
            PathSvg { path: dock.silhouette }
        }
    }

    // Geometry only: the icons and their dots are positioned against it, and the
    // shape above is what draws it.
    Rectangle {
        id: plate

        x: dock.plateX
        y: dock.plateTop
        width: dock.plateWidth
        height: dock.plateHeight
        color: "transparent"

        // Icons sit in the top of the plate, their dots in the rail below.
        Repeater {
            model: dock.groups

            delegate: Item {
                id: cell

                required property var modelData
                required property int index

                x: dock.pad + index * (dock.cellSize + dock.cellGap)
                y: 0
                width: dock.cellSize
                height: dock.plateHeight

                readonly property bool hovered: dock.hoveredIndex === index

                Image {
                    id: icon

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (dock.iconArea - height) / 2
                    width: 38
                    height: 38

                    source: cell.modelData.icon
                    visible: source !== ""
                    // Loaded at the magnified size so growing stays crisp.
                    sourceSize.width: 64
                    sourceSize.height: 64
                    fillMode: Image.PreserveAspectFit
                    smooth: true

                    scale: dock.scaleFor(cell.index)
                    transformOrigin: Item.Center
                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }

                Rectangle {
                    visible: cell.modelData.icon === ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (dock.iconArea - height) / 2
                    width: 36
                    height: 36
                    radius: 10
                    color: Theme.surface

                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData.letter
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: dock.dotsTop
                    spacing: 4

                    Repeater {
                        model: Math.min(cell.modelData.windows.length, 3)

                        delegate: Rectangle {
                            width: 4
                            height: 4
                            radius: 2
                            color: cell.modelData.focused ? Theme.alert : Theme.textDim
                        }
                    }

                    // More windows than dots: a fourth, fainter one.
                    Rectangle {
                        visible: cell.modelData.windows.length > 3
                        width: 4
                        height: 4
                        radius: 2
                        color: Theme.textDim
                        opacity: 0.5
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onEntered: {
                        dock.hoveredIndex = cell.index
                        listCloseTimer.stop()
                        // A list that is already open follows the pointer.
                        if (dock.listIndex >= 0) dock.listIndex = cell.index
                        else openTimer.restart()
                    }
                    onExited: {
                        if (dock.hoveredIndex === cell.index) dock.hoveredIndex = -1
                        openTimer.stop()
                        // Not closed here: the pointer is probably on its way to
                        // the list, so it gets the grace period instead.
                        if (dock.listIndex === cell.index) listCloseTimer.restart()
                    }
                    onClicked: dock.focusGroup(cell.modelData)
                }
            }
        }
    }

    // ---- the hover list --------------------------------------------------

    Rectangle {
        id: hoverList

        readonly property var group: dock.listGroup

        visible: group !== null && group.windows.length > 1
        width: 288
        height: rows.height + 12
        radius: Theme.radiusSmall
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Theme.border

        // Centred on the icon it belongs to, kept inside the screen.
        x: Math.max(8, Math.min(dock.width - width - 8,
            dock.plateX + dock.pad
                + dock.hoveredIndex * (dock.cellSize + dock.cellGap)
                + dock.cellSize / 2 - width / 2))
        y: dock.plateTop - height - 6

        // The list is masked in, so hovering it is what keeps the dock from
        // timing out while the pointer is up here.
        HoverHandler {
            onHoveredChanged: {
                if (hovered) {
                    hideTimer.stop()
                    listCloseTimer.stop()
                } else if (dock.listIndex >= 0) {
                    listCloseTimer.restart()
                }
            }
        }

        Column {
            id: rows
            y: 6
            width: parent.width - 12
            x: 6
            spacing: 2

            Repeater {
                model: hoverList.group ? hoverList.group.windows : []

                delegate: Rectangle {
                    required property var modelData

                    width: rows.width
                    height: 26
                    radius: 8
                    // The panels' entry treatment: surface at rest, the pill
                    // tone under the pointer.
                    color: rowMouse.containsMouse ? Theme.surfacePill : Theme.surface

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        text: modelData.title || modelData.app_id
                        color: modelData.is_focused ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Niri.action(["focus-window", "--id", String(modelData.id)])
                            dock.listIndex = -1
                            dock.shown = false
                            hideTimer.stop()
                            listCloseTimer.stop()
                        }
                    }
                }
            }
        }
    }
}
