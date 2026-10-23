// Dictation strip: translucent, full-width layer-shell overlay that shows a
// transcript before voxtype types it. Loaded by bin/dictation-strip, which
// injects stripText / stripTimeoutMs / bandPx / bottomMargin / sidePad and a
// `ctrl` object used to report the decision back and to receive live target
// window updates.
import QtQuick
import QtQuick.Shapes
import org.kde.layershell 1.0 as LayerShell

Window {
    id: win
    visible: true
    color: "#99121212" // #121212 at 60% opacity

    // Never take activation. Without this, Qt asks the compositor to activate
    // the window on click, which pulls focus off whatever the user was typing
    // in and does not hand it back when the strip closes. Mouse events still
    // reach the buttons; only focus is refused.
    flags: Qt.Window | Qt.WindowDoesNotAcceptFocus

    readonly property int gap: 10
    readonly property int gapTop: 6
    readonly property int barGap: 16
    readonly property int targetH: 18
    readonly property int pillH: 34
    readonly property int padH: Math.round(sidePad * 1.6)

    // Height actually used by the text, bounded by the band. Kept separate so
    // a short transcript yields a short strip instead of a half-empty band.
    property int textH: bandPx
    readonly property int lines: transcript.lineCount

    // Everything that is not the text: the target line, the gaps, the pill row
    // and the padding. The countdown is drawn as an outline around the Accept
    // button rather than a bar, so it contributes no height of its own. The
    // window is this plus the text height.
    readonly property int chromeH: sidePad + targetH + gapTop
                                   + barGap + pillH + sidePad

    // Panel width: the eighty-character measure plus a margin on each side. Not
    // full width -- spanning the screen left the transcript letterboxed in
    // empty space. It also keeps the text width independent of the window
    // width, which matters because the layer-shell surface briefly reports a
    // wrong width before the compositor configures it.
    readonly property int contentW: chMeasure.advanceWidth + 2 * padH

    // Exposed for measuring: whether the transcript had to be elided, and the
    // height the wrapped text would like (independent of the bound height).
    readonly property bool textTruncated: transcript.truncated
    readonly property int textContentH: Math.ceil(transcript.contentHeight)

    // Cap the text measure at ~80 characters. Without this the strip is wide
    // enough that a line holds 200+ characters, so real transcripts run as a
    // single very long line instead of wrapping into a readable block. The
    // width is measured at the MAXIMUM font size, not the fitted one: if it
    // followed the fitted font, shrinking the font would narrow the measure and
    // could add lines, so the fitting loop would oscillate.
    readonly property string ch80: new Array(81).join("0")
    readonly property int maxFontPx: Math.max(12, Math.round(bandPx / 4))

    readonly property int timeoutSecs: Math.max(1, Math.round(stripTimeoutMs / 1000))
    // Counts down with the bar (so it freezes while paused), shown in Accept.
    readonly property int remainingSecs: Math.max(0, Math.ceil(countdown.barProgress * timeoutSecs))

    // Content-sized width, anchored only to the bottom. A surface is centred by
    // the compositor on any axis it is not anchored to, so the panel floats
    // horizontally centred (sharp-cornered, unframed) rather than spanning the
    // screen.
    width: contentW
    height: chromeH + textH

    LayerShell.Window.exclusionZone: 0
    // The surface's app id. Without this the compositor classifies the strip by
    // its interpreter ("python3.14"), so window rules cannot target it.
    LayerShell.Window.scope: "dictation-strip"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom
    LayerShell.Window.margins {
        left: 0
        top: 0
        right: 0
        bottom: bottomMargin
    }
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false
    LayerShell.Window.wantsToBeOnActiveScreen: true

    // Instrumentation for the focus-stealing investigation.
    readonly property string debugInfo:
        "flags=" + win.flags
        + " kbInteract=" + LayerShell.Window.keyboardInteractivity
        + " activateOnShow=" + LayerShell.Window.activateOnShow
        + " doesNotAcceptFocus=" + ((win.flags & Qt.WindowDoesNotAcceptFocus) ? 1 : 0)
        + " active=" + win.active

    property string targetLabel: "\u2026"
    property string decision: ""
    property bool paused: false

    function finish(d) {
        if (decision !== "")
            return;
        decision = d;
        ctrl.finish(d);
    }

    function prettyApp(name) {
        if (!name)
            return "";
        var parts = name.split(".");
        var s = parts[parts.length - 1];
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    Connections {
        target: ctrl
        function onTargetChanged(appName, title) {
            var app = win.prettyApp(appName);
            win.targetLabel = title ? (app ? app + " \u2014 " + title : title) : app;
        }
    }

    // Fit the transcript to the band: the largest size at which the wrapped
    // text stays within four lines and inside bandPx, never larger than a
    // quarter of the band (so four lines can at most fill it). forceLayout()
    // makes the measurement synchronous. The Text's elide then shortens
    // anything still too long at the floor.
    property int chosenSize: 0

    function fitFont() {
        if (win.width <= 0)
            return;
        var hi = maxFontPx;
        var best = 12;
        for (var s = hi; s >= 12; s--) {
            transcript.font.pixelSize = s;
            transcript.forceLayout();
            if (transcript.lineCount <= 4 && transcript.contentHeight <= bandPx) {
                best = s;
                break;
            }
        }
        transcript.font.pixelSize = best;
        transcript.forceLayout();
        textH = Math.min(bandPx, Math.max(1, Math.ceil(transcript.contentHeight)));
        chosenSize = best;
        // Re-apply the window height imperatively. Once the layer-shell surface
        // has been configured, the compositor has assigned the window a height
        // and the `height:` binding above no longer drives it, so a wrapped
        // transcript would stay clipped at the first line's height. Assigning
        // here commits the new size on every fit.
        if (debugLog)
            console.log("fit: size=" + best + " lines=" + transcript.lineCount
                        + " truncated=" + transcript.truncated
                        + " width=" + Math.round(transcript.width)
                        + " textH=" + textH + " -> h=" + (chromeH + textH));
        win.height = chromeH + textH;
    }

    // ---- live "about to type into" line ----
    Text {
        id: targetLine
        anchors.top: parent.top
        anchors.topMargin: sidePad
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: padH
        anchors.rightMargin: padH
        height: targetH
        text: win.targetLabel
        color: "#b3ffffff"
        font.family: "Inter"
        font.pixelSize: 13
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Width of eighty characters at the largest font size, for the measure cap.
    // Deliberately independent of `transcript.font` (see maxFontPx).
    TextMetrics {
        id: chMeasure
        font.family: "CMU Serif"
        font.pixelSize: win.maxFontPx
        text: win.ch80
    }

    // ---- quoted transcript, capped to a readable measure ----
    Text {
        id: transcript
        anchors.top: targetLine.bottom
        anchors.topMargin: gapTop
        anchors.horizontalCenter: parent.horizontalCenter
        // About eighty characters wide, never wider than the strip allows. The
        // height is deliberately NOT bound to textH: textH is derived from this
        // item's contentHeight, and binding the height back would clamp the
        // layout to whatever the first measurement produced (which is why the
        // text elided at three lines instead of four).
        // Exactly the measured eighty-character width; the margins are the
        // panel's breathing room.
        width: chMeasure.advanceWidth
        text: "\u201C" + stripText + "\u201D"
        color: "white"
        font.family: "CMU Serif"
        wrapMode: Text.WordWrap
        maximumLineCount: 4
        elide: Text.ElideRight
        clip: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Component.onCompleted: win.fitFont()
        onWidthChanged: win.fitFont()
    }

    // Countdown state. There is no bar item: the remaining time is drawn as an
    // outline around the Accept button, so this item only carries the value and
    // drives the animation. Pause/resume act on this animation.
    Item {
        id: countdown
        visible: false
        property real barProgress: 1.0

        NumberAnimation on barProgress {
            id: drain
            from: 1
            to: 0
            duration: stripTimeoutMs
            running: true
            onFinished: win.finish("accept")
        }
    }

    // ---- controls ----
    component Pill: Rectangle {
        id: pill
        property string kind
        property string label
        property real ringProgress: 1
        signal activated()

        // How far the countdown outline sits outside the button's own edge.
        readonly property int ringMargin: 3

        // Blue / orange / brown. Brown and orange are close in hue, so these
        // are separated mainly by lightness (bright orange, mid blue, dark
        // brown); the icon in each pill is a second, colour-independent cue.
        readonly property color baseColor: kind === "pause" ? "#df8a2b"
                                         : kind === "accept" ? "#3f7fd2"
                                         : "#7c4a2f"
        readonly property color hoverColor: kind === "pause" ? "#eda049"
                                          : kind === "accept" ? "#5492e0"
                                          : "#92593a"

        implicitWidth: content.implicitWidth + 26
        implicitHeight: pillH
        radius: pillH / 2
        color: mouse.containsMouse ? hoverColor : baseColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.25)

        // Countdown outline. Drawn with Canvas rather than Shape: an animating
        // ShapePath re-tessellates its geometry every frame and visibly tears on
        // Wayland, whereas a Canvas repaint is the normal way to animate an arc.
        // The capsule is traced clockwise from the centre of the top edge and
        // the elapsed portion is stroked in white over a faint full outline.
        Canvas {
            id: ring
            anchors.fill: parent
            anchors.margins: -pill.ringMargin
            visible: pill.kind === "accept" && pill.width > pill.height
            renderStrategy: Canvas.Immediate
            antialiasing: true

            function strokeCapsule(ctx, progress, color, lineWidth) {
                var m = pill.ringMargin;
                var x = m, y = m;
                var w = pill.width, h = pill.height;
                var r = h / 2;                        // capsule radius
                var half = Math.max(0, w / 2 - r);    // centre to a cap arc
                var side = Math.max(0, h - 2 * r);    // vertical run (zero here)
                var quarter = Math.PI * r / 2;
                // Two top runs of `half`, a bottom run of `2 * half`, two
                // vertical runs, four quarter arcs.
                var total = 4 * half + 2 * side + 4 * quarter;
                var budget = Math.max(0, Math.min(1, progress)) * total;
                var HALF = Math.PI / 2;
                var cx = x + w / 2;
                var cy = y;

                ctx.beginPath();
                ctx.moveTo(cx, cy);

                function run(x2, y2, len) {
                    if (budget <= 0 || len <= 0)
                        return;
                    var frac = (budget >= len) ? 1 : budget / len;
                    cx = cx + (x2 - cx) * frac;
                    cy = cy + (y2 - cy) * frac;
                    ctx.lineTo(cx, cy);
                    budget -= len * frac;
                }

                function turn(acx, acy, a0, a1, len) {
                    if (budget <= 0 || len <= 0)
                        return;
                    var frac = (budget >= len) ? 1 : budget / len;
                    var a = a0 + (a1 - a0) * frac;
                    // anticlockwise=false sweeps increasing angle, which is
                    // clockwise on screen where y grows downwards.
                    ctx.arc(acx, acy, r, a0, a, false);
                    cx = acx + r * Math.cos(a);
                    cy = acy + r * Math.sin(a);
                    budget -= len * frac;
                }

                run(x + w - r, y, half);
                turn(x + w - r, y + r, -HALF, 0, quarter);
                run(x + w, y + h - r, side);
                turn(x + w - r, y + h - r, 0, HALF, quarter);
                run(x + r, y + h, 2 * half);
                turn(x + r, y + h - r, HALF, Math.PI, quarter);
                run(x, y + r, side);
                turn(x + r, y + r, Math.PI, Math.PI + HALF, quarter);
                run(x + w / 2, y, half);

                ctx.lineWidth = lineWidth;
                ctx.lineCap = "round";
                ctx.strokeStyle = color;
                ctx.stroke();
            }

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                strokeCapsule(ctx, 1, Qt.rgba(1, 1, 1, 0.3), 3);
                strokeCapsule(ctx, pill.ringProgress, "white", 3);
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: pill
                function onRingProgressChanged() {
                    ring.requestPaint();
                }
            }
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 8

            Item {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter

                // pause: two bars
                Row {
                    anchors.centerIn: parent
                    spacing: 3
                    visible: pill.kind === "pause"
                    Rectangle { width: 3; height: 15; color: "white"; radius: 1 }
                    Rectangle { width: 3; height: 15; color: "white"; radius: 1 }
                }

                // accept: check mark
                Shape {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    visible: pill.kind === "accept"
                    ShapePath {
                        strokeColor: "white"
                        strokeWidth: 2
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        startX: 2
                        startY: 9
                        PathLine { x: 7; y: 14 }
                        PathLine { x: 15; y: 3 }
                    }
                }

                // cancel: X
                Item {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    visible: pill.kind === "cancel"
                    Rectangle {
                        anchors.centerIn: parent
                        width: 3
                        height: 16
                        radius: 1
                        color: "white"
                        rotation: 45
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 3
                        height: 16
                        radius: 1
                        color: "white"
                        rotation: -45
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: "white"
                font.family: "Inter"
                font.pixelSize: 16
                textFormat: Text.RichText // lets Accept embolden the countdown
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: pill.activated()
        }
    }

    Item {
        id: controls
        anchors.top: transcript.bottom
        anchors.topMargin: barGap
        anchors.left: parent.left
        anchors.right: parent.right
        height: pillH

        Row {
            anchors.centerIn: parent
            spacing: 12

            Pill {
                kind: "pause"
                label: win.paused ? "Resume" : "Pause"
                onActivated: {
                    if (win.paused) {
                        drain.resume();
                        win.paused = false;
                    } else {
                        drain.pause();
                        win.paused = true;
                    }
                }
            }

            Pill {
                kind: "accept"
                label: "Accept (<b>" + win.remainingSecs + "s</b>)"
                ringProgress: countdown.barProgress
                onActivated: win.finish("accept")
            }

            Pill {
                kind: "cancel"
                label: "Cancel"
                onActivated: win.finish("cancel")
            }
        }
    }
}
