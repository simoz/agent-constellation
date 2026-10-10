import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugin" as Plugin
import "plugin/ui" as Constellation

// Beat-cut launch video (28.8 s = 12 bars at 100 BPM), the same format as
// Outbound's: 1440×1440, cuts and kinetic type on the beat, the drop at 2.4 s.
//   DEMO_AUDIO=demo/constellation.mp3 DEMO_AUDIO_START=<drop - 2.4> demo/video demo/constellation-launch.mp4
// Data: snapshots of demo/scenario.py precomputed by demo/video_data.py on a
// simulated clock (fictional Rails sessions), replayed at two simulated seconds
// per video second.
ShellRoot {
    id: root
    readonly property int fps: Number(Quickshell.env("DEMO_FPS")) || 30
    readonly property string outDir: Quickshell.env("DEMO_FRAMES") || ""
    // DEMO_STEP renders every Nth frame, for quick checks.
    readonly property int step: Number(Quickshell.env("DEMO_STEP")) || 1
    readonly property real beat: 0.6
    readonly property real drop: 2.4
    readonly property real duration: 28.8
    // Simulated scenario second shown at video time t; bookings starts waiting at 30.
    function simulated(time) { return 6.4 + 2 * time; }
    property int frame: 0
    property real t: 0
    property var fired: ({})
    property var snapshots: []

    readonly property var camera: [
        {t: 0.0, at: "full", s: 0.86},
        {t: 2.4, at: "full", s: 0.86, cut: true},
        {t: 4.7, at: "full", s: 0.95},
        {t: 4.8, at: "core:shop", s: 2.2, cut: true},
        {t: 7.1, at: "core:shop", s: 2.0},
        {t: 7.2, at: "hot:shop", s: 2.5, cut: true},
        {t: 9.5, at: "hot:shop", s: 2.3},
        {t: 9.6, at: "core:shop", s: 1.7, cut: true},
        {t: 11.9, at: "core:shop", s: 1.85},
        {t: 12.0, at: "scene", s: 1.0, cut: true},
        {t: 13.1, at: "core:bookings", s: 1.6},
        {t: 14.3, at: "core:bookings", s: 1.7},
        {t: 14.4, at: "buttons", s: 1.9, cut: true},
        {t: 15.5, at: "buttons", s: 2.0},
        {t: 15.6, at: "scene", s: 1.12, cut: true},
        {t: 16.4, at: "scene", s: 1.12},
        {t: 19.1, at: "scene", s: 1.6},
        {t: 19.2, at: "waves", s: 2.3, cut: true},
        {t: 21.5, at: "waves", s: 2.1},
        {t: 21.6, at: "list", s: 1.65, cut: true},
        {t: 24.0, at: "list", s: 1.75},
        {t: 28.8, at: "list", s: 1.75}
    ]
    readonly property var cursor: [
        {t: 0.0, p: [1400, 1300]},
        {t: 14.4, p: [1400, 1300]},
        {t: 14.4, p: "core:bookings+", cut: true},
        {t: 14.7, p: "core:bookings"},
        {t: 15.0, p: "terminalButton"},
        {t: 15.6, p: "core:shop+", cut: true},
        {t: 15.85, p: "core:shop"},
        {t: 16.2, p: "zoomButton"},
        {t: 16.8, p: [1400, 1300], cut: true},
        {t: 28.8, p: [1400, 1300]}
    ]
    readonly property var clicks: [
        {t: 14.75, run: function() { service.selection = root.agentId("bookings"); }},
        {t: 15.1, run: function() {}},
        {t: 15.9, run: function() { service.selection = root.agentId("shop"); }},
        {t: 16.3, run: function() { service.zoomed = true; }},
        {t: 19.2, click: false, run: function() { service.selection = ""; }}
    ]
    readonly property var words: [
        {from: 2.4, to: 4.8, lines: [[2.4, "YOUR AGENTS."], [3.0, "LIVE."]]},
        {from: 4.8, to: 7.2, lines: [[4.8, "TOOL CALLS"], [5.4, "IN FLIGHT."]]},
        {from: 7.2, to: 9.6, lines: [[7.2, "HOT FILES"], [7.8, "GLOW."]]},
        {from: 9.6, to: 12.0, lines: [[9.6, "SUBAGENTS"], [10.2, "IN ORBIT."]]},
        {from: 12.0, to: 14.4, lines: [[12.0, "WAITING"], [12.6, "FOR YOU."]]},
        {from: 14.4, to: 15.6, small: true, lines: [[14.4, "JUMP TO ITS TERMINAL"]]},
        {from: 15.6, to: 16.8, small: true, lines: [[15.6, "ZOOM IN"]]},
        {from: 16.8, to: 19.2, small: true, lines: [[16.8, "PATHS."], [18.0, "LINE COUNTS."]]},
        {from: 19.2, to: 21.6, small: true, lines: [[19.2, "TOKENS"], [19.8, "IN WAVES."]]},
        {from: 21.6, to: 24.0, small: true, lines: [[21.6, "CLAUDE CODE."], [22.2, "CODEX."], [22.8, "LOCAL."], [23.4, "READ-ONLY."]]}
    ]
    readonly property var cuts: [2.4, 4.8, 7.2, 9.6, 12.0, 14.4, 15.6, 16.8, 19.2, 21.6, 24.0]
    readonly property var block: words.find(function(w) { return t >= w.from && t < w.to; }) || null

    function clamp(x) { return Math.max(0, Math.min(1, x)); }
    function pulse(amount) {
        if (t < drop) return 0;
        var n = Math.floor((t - drop) / beat), phase = t - drop - n * beat;
        return amount * (n % 4 === 0 ? 1 : 0.45) * Math.exp(-phase * 9);
    }
    function flash() {
        var best = 0;
        cuts.forEach(function(c) { if (t >= c) best = Math.max(best, (c === drop || c === 24.0 ? 0.85 : 0.35) * Math.exp(-(t - c) * 10)); });
        return best;
    }
    function ease(x) { x = clamp(x); return x < 0.5 ? 4*x*x*x : 1 - Math.pow(-2*x + 2, 3) / 2; }
    function find(item, test) {
        if (!item) return null;
        if (test(item)) return item;
        for (var i = 0; i < item.children.length; i++) {
            var hit = find(item.children[i], test);
            if (hit) return hit;
        }
        if (item.contentItem && item.contentItem !== item) return find(item.contentItem, test);
        return null;
    }
    function named(name) { return find(board, function(i) { return i.objectName === name; }); }
    function agentId(project) {
        var agent = service.agents.find(function(a) { return a.project === project; });
        return agent ? agent.id : "";
    }
    function centre(item, fx, fy) {
        var m = item.mapToItem(dashboard, item.width * fx, item.height * fy);
        return {x: m.x, y: m.y};
    }
    // A core or the hottest file of an agent, in dashboard coordinates.
    function scenePoint(project, hot) {
        var entry = board.scene.scene.find(function(e) { return e.agent.project === project; });
        if (!entry) return null;
        var point = hot && entry.files.length ? entry.files[0] : entry;
        var m = board.scene.mapToItem(dashboard, point.x, point.y);
        return {x: m.x, y: m.y};
    }
    function region(name) {
        var parts = name.split(":");
        if (parts[0] === "core" || parts[0] === "hot") return scenePoint(parts[1], parts[0] === "hot") || region("scene");
        if (name === "scene") return centre(board.scene, 0.5, 0.5);
        if (name === "list") return centre(board.agentList, 0.5, 0.3);
        if (name === "waves") return centre(named("tokenWaves"), 0.5, 0.4);
        if (name === "buttons") { var b = centre(named("terminalButton"), 0.5, 0.5); return {x: b.x - 150, y: b.y - 40}; }
        return {x: 640, y: 600};
    }
    function locate(p) {
        if (Array.isArray(p)) return {x: p[0], y: p[1]};
        var offset = p.slice(-1) === "+";
        if (offset) p = p.slice(0, -1);
        var m = p.indexOf("core:") === 0 ? scenePoint(p.slice(5), false) : named(p) ? centre(named(p), 0.5, 0.5) : null;
        if (!m) return null;
        return offset ? {x: m.x + 70, y: m.y + 90} : m;
    }
    function track(keys, time, value) {
        var i = 0;
        while (i < keys.length - 2 && keys[i + 1].t <= time) i++;
        var a = keys[i], b = keys[i + 1];
        if (b.cut) return value(a, a, 0);
        return value(a, b, ease((time - a.t) / Math.max(0.001, b.t - a.t)));
    }
    property var lastCursor: ({x: 1400, y: 1300})
    function apply() {
        var index = Math.min(snapshots.length - 1, Math.floor(simulated(t)));
        if (index >= 0 && service.snapshot !== snapshots[index]) service.snapshot = snapshots[index];
        board.scene.time = t;
        clicks.forEach(function(c, i) {
            if (!root.fired[i] && t >= c.t) { root.fired[i] = true; c.run(); if (c.click !== false) ripple.at = t; }
        });
        var cam = track(camera, t, function(a, b, k) {
            var pa = root.region(a.at), pb = root.region(b.at);
            return {x: pa.x + (pb.x - pa.x)*k, y: pa.y + (pb.y - pa.y)*k, s: a.s + (b.s - a.s)*k};
        });
        var s = cam.s * (1 + pulse(0.05));
        camScale.xScale = camScale.yScale = s;
        camMove.x = stage.width/2 - cam.x*s;
        camMove.y = stage.height/2 - cam.y*s;
        var pos = track(cursor, t, function(a, b, k) {
            var pa = root.locate(a.p) || root.lastCursor, pb = root.locate(b.p) || pa;
            return {x: pa.x + (pb.x - pa.x)*k, y: pa.y + (pb.y - pa.y)*k};
        });
        lastCursor = pos;
        pointer.x = camMove.x + pos.x*s;
        pointer.y = camMove.y + pos.y*s;
    }

    FileView {
        id: data
        path: Quickshell.env("DEMO_SNAPSHOTS")
        blockLoading: true
    }
    Plugin.Service {
        id: service
        // No collector: frames replay precomputed snapshots.
        Component.onCompleted: {
            reducedMotion = false; animating = false; notifyWaiting = false;
            root.snapshots = JSON.parse(data.text());
        }
    }
    Constellation.Theme { id: theme }
    Window {
        id: window
        visible: true
        width: 1080; height: 1080
        color: Color.background
        Item {
            id: stage
            // Fixed size: the offscreen platform may not honour the window size.
            width: 1080; height: 1080
            clip: true
            Rectangle { anchors.fill: parent; color: Color.background }
            Item {
                id: dashboard
                width: 1280; height: 1200
                transform: [Scale { id: camScale }, Translate { id: camMove }]
                Constellation.Dashboard {
                    id: board
                    anchors.fill: parent
                    service: service
                    expanded: true
                    surfaceSwitchAvailable: false
                }
            }
            // Vignette keeps the eye centred and the type readable over busy frames.
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var c = getContext("2d");
                    var g = c.createRadialGradient(width/2, height/2, width*0.3, width/2, height/2, width*0.75);
                    g.addColorStop(0, Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0));
                    g.addColorStop(1, Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.85));
                    c.fillStyle = g; c.fillRect(0, 0, width, height);
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 460
                visible: root.block !== null
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0) }
                    GradientStop { position: 0.55; color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.82) }
                    GradientStop { position: 1; color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.95) }
                }
            }
            Item {
                id: pointer
                width: 1; height: 1
                opacity: root.t >= 14.4 && root.t < 16.8 ? 1 : 0
                Rectangle {
                    id: ripple
                    property real at: -10
                    readonly property real k: root.clamp((root.t - at) / 0.4)
                    visible: k > 0 && k < 1
                    width: 16 + 56*k; height: width; radius: width/2
                    x: -width/2; y: -height/2
                    color: "transparent"; border.width: 4
                    border.color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 1 - k)
                }
                Canvas {
                    width: 30; height: 36
                    onPaint: {
                        var c = getContext("2d");
                        c.beginPath(); c.moveTo(2, 2); c.lineTo(2, 27); c.lineTo(8.5, 21); c.lineTo(13, 31);
                        c.lineTo(17.5, 29); c.lineTo(13, 19.5); c.lineTo(21.5, 19.5); c.closePath();
                        c.fillStyle = "#f4f4f4"; c.fill();
                        c.lineWidth = 1.6; c.strokeStyle = "#111111"; c.stroke();
                    }
                }
            }
            // Kinetic type, bottom-left; each line snaps up on its beat.
            Column {
                id: type
                readonly property var current: root.block
                x: 64
                anchors { bottom: parent.bottom; bottomMargin: 72 }
                spacing: current && current.small ? 0 : -8
                opacity: current ? root.clamp((current.to - root.t) / 0.08) : 0
                Rectangle {
                    width: 72; height: 6; color: theme.accent
                    visible: type.current !== null
                }
                Item { width: 1; height: 14 }
                Repeater {
                    model: type.current ? type.current.lines : []
                    Text {
                        required property var modelData
                        required property int index
                        readonly property real k: root.clamp((root.t - modelData[0]) / 0.12)
                        visible: root.t >= modelData[0]
                        opacity: k
                        transform: Translate { y: 36 * (1 - root.ease(k)) }
                        width: 960
                        text: modelData[1]
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 40
                        font.family: theme.font
                        font.pixelSize: type.current.small ? 88 : 118
                        font.bold: true
                        font.letterSpacing: 2
                        // Lines alternate text/accent so the second hit reads as the punchline.
                        color: index % 2 ? theme.accent : theme.text
                    }
                }
            }
            // Title card: logo, name and tagline, with a short build into the drop.
            Rectangle {
                anchors.fill: parent
                color: Color.background
                visible: root.t < root.drop
                Column {
                    anchors.centerIn: parent
                    spacing: 22
                    opacity: root.clamp((root.t - 0.2) / 0.5)
                    scale: 1 + 0.08 * root.ease(root.clamp((root.t - 1.2) / 1.2))
                    Item {
                        width: 120; height: 120
                        anchors.horizontalCenter: parent.horizontalCenter
                        Constellation.ConstellationIcon { anchors.centerIn: parent; ink: theme.accent; scale: 6 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "CONSTELLATION"; color: theme.text
                        font.family: theme.font; font.pixelSize: 76
                        font.letterSpacing: 10 + 8 * root.ease(root.clamp((root.t - 1.2) / 1.2))
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "See what your coding agents are doing."; color: theme.subdued
                        font.family: theme.font; font.pixelSize: 32
                    }
                }
            }
            // End card with the install command; the logo pulses on the beat.
            Rectangle {
                anchors.fill: parent
                color: Color.background
                visible: root.t >= 24.0
                Column {
                    anchors.centerIn: parent
                    spacing: 20
                    Item {
                        width: 120; height: 120
                        anchors.horizontalCenter: parent.horizontalCenter
                        scale: 1 + root.pulse(0.14)
                        Constellation.ConstellationIcon { anchors.centerIn: parent; ink: theme.accent; scale: 6 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "CONSTELLATION"; color: theme.text
                        font.family: theme.font; font.pixelSize: 88; font.bold: true
                        font.letterSpacing: 10
                        scale: 1.25 - 0.25 * root.ease(root.clamp((root.t - 24.0) / 0.5))
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Live coding agent activity for your Omarchy bar"; color: theme.subdued
                        font.family: theme.font; font.pixelSize: 30
                        opacity: root.clamp((root.t - 24.6) / 0.3)
                    }
                    Item { width: 1; height: 26 }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: command.implicitWidth + 48; height: 64
                        color: theme.wash; border.color: theme.fade(theme.accent, 0.55); border.width: 1.5
                        opacity: root.clamp((root.t - 25.2) / 0.3)
                        Text {
                            id: command
                            anchors.centerIn: parent
                            text: "<font color='" + theme.accent + "'>$</font> omarchy plugin add https://github.com/simoz/agent-constellation.git --enable"
                            textFormat: Text.RichText
                            color: theme.text; font.family: theme.font; font.pixelSize: 18
                        }
                    }
                }
            }
            // Cut flash, strongest on the drop and on the end card.
            Rectangle {
                anchors.fill: parent
                color: theme.text
                opacity: root.flash()
                visible: opacity > 0.01
            }
        }
    }

    // Wait for the scene to lay out, then step through frames: apply(t) → let canvases paint → grab.
    Timer { interval: 1500; running: true; onTriggered: root.nextFrame() }
    function nextFrame() {
        t = frame / fps;
        apply();
        paintWait.start();
    }
    Timer {
        id: paintWait
        interval: 45
        onTriggered: stage.grabToImage(function(result) {
            if (root.outDir) result.saveToFile(root.outDir + "/f" + String(root.frame).padStart(4, "0") + ".png");
            root.frame += root.step;
            if (root.frame >= root.duration * root.fps) { console.log("DEMO_COMPLETE", root.frame); Qt.quit(); }
            else root.nextFrame();
        })
    }
}
