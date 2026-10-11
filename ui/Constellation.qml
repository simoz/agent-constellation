pragma ComponentBehavior: Bound
import QtQuick
import "../Model.js" as Model

// Agent cores with orbiting subagents; tool calls fly out to the files they touch
// and hot files glow. Static geometry and labels live on one canvas repainted
// only when data, size, selection or theme change; motion uses scene-graph
// items (AgentMotion) that run only while visible, active and animating.
FocusScope {
    id: root
    objectName: "constellationScene"
    required property var service
    property bool active: true
    // On the desktop: no background of its own, no focus, no pointer input.
    property bool backdrop: false
    // On the desktop: the wallpaper's luminance grid (WallpaperProbe), or null.
    property var surface: null
    // On the desktop: opacity of the theme background drawn behind the scene.
    property real veil: 0
    property int paintCount: 0
    readonly property var colors: service.colors
    readonly property bool light: colors.light
    property real time: 0
    // Milliseconds between clock ticks; the desktop backdrop runs slower.
    property int frameInterval: 33
    // False while the window shows no frames, as on another workspace: the clock
    // stops instead of evaluating bindings nobody sees. The next frame, which any
    // snapshot change brings, starts it again.
    property bool presented: true
    property double lastFrame: 0
    readonly property bool running: active && visible && presented && service.moving && width > 0 && height > 0
    readonly property string fontFamily: theme.font
    readonly property real scale: Math.max(0.75, Math.min(1.25, Math.min(width, height) / 760))
    Theme { id: theme }

    // Layout in pixels, recomputed with the snapshot or the size.
    readonly property var scene: {
        // The service sorts by status for the list; the scene keeps a stable order so
        // a core does not jump when its agent starts waiting.
        // Zoom keeps only the selected agent, laid out alone at full size.
        var agents = service.zooming ? [service.selected]
            : service.agents.slice().sort(function(a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });
        var list = Model.centres(agents.length, width / Math.max(1, height));
        var radius = Model.reach(agents.length, width, height);
        // Files spread wider than tall (orbits are flattened to 0.82), labels sit below the core.
        var mx = Math.min(radius * 1.05, width * 0.25), my = Math.min(radius * 0.8, height * 0.22);
        var grid = surface ? {columns: surface.columns, rows: surface.rows, values: surface.values} : null;
        return agents.map(function(agent, index) {
            var x = mx + list[index].x * (width - mx * 2), y = my + list[index].y * (height - my * 2);
            var behind = surfaceAt(grid, x, y, radius, radius * 0.8), lit = surfaceLight(behind);
            return {agent: agent, x: x, y: y, radius: radius, surface: behind, light: lit,
                    color: colors.standOut(service.agentColor(agent), behind, lit),
                    files: Model.fileNodes(agent, x, y, radius)};
        });
    }
    // The token waves sit on the wallpaper too.
    readonly property bool wavesLight: surfaceLight(surfaceAt(surface ? {columns: surface.columns, rows: surface.rows, values: surface.values} : null,
        width / 2, height - 50 * scale, Math.min(width * 0.3, 410 * scale), 40 * scale))
    readonly property string paintKey: Model.sceneKey(scene) + veil + scene.map(function(e) { return e.light ? 1 : 0; }).join("") + service.selection + service.zooming
        + width + "x" + height + String(theme.background) + String(theme.text) + JSON.stringify(colors.values) + light
    onPaintKeyChanged: base.requestPaint()
    // Particles in flight across all agents; each agent gets an equal share, at most 12.
    readonly property int particleLimit: Math.max(2, Math.min(12, Math.floor(48 / Math.max(1, scene.length))))
    // Delegates being removed when the scene shrinks still evaluate their bindings
    // once; they see this inert entry instead of undefined.
    readonly property var vacant: ({agent: {id: "", status: "idle", activityBuckets: [], subagents: []}, surface: -1, light: false,
                                    files: [], x: 0, y: 0, radius: 1, color: "transparent"})

    function css(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + (a === undefined ? c.a : a) + ")"; }
    // Luminance around a point, wallpaper and background veil together, or -1 off the desktop.
    function surfaceAt(grid, x, y, rx, ry) {
        var l = Model.luminanceAt(grid, x / Math.max(1, width), y / Math.max(1, height), rx / Math.max(1, width), ry / Math.max(1, height));
        if (backdrop && veil > 0) l = (l < 0 ? colors.relative(theme.background) : l) * (1 - veil) + colors.relative(theme.background) * veil;
        return l;
    }
    // Whether the scene draws as on a light background: the theme's own mode, or
    // on the desktop whichever theme ink stands out more on luminance l.
    function surfaceLight(l) {
        if (l < 0) return light;
        var a = colors.relative(theme.text), b = colors.relative(theme.background);
        return Model.lightSurface(l, Math.min(a, b), Math.max(a, b));
    }
    // Text ink for an entry: the theme's text, or its background where that stands out more.
    function ink(entry) { return entry.light === light ? theme.text : theme.background; }
    function dimmed(entry) { return service.selection !== "" && entry.agent.id !== service.selection; }
    function zoomTo(id) { service.selection = id; service.zoomed = true; }
    function font(weight, size) { return weight + " " + Math.round(size * scale) + "px \"" + fontFamily + "\""; }
    function dashed(c, x1, y1, x2, y2, dash, gap) {
        var length = Math.hypot(x2 - x1, y2 - y1), step = dash + gap;
        for (var d = 0; d < length; d += step) {
            var a = d / length, b = Math.min(1, (d + dash) / length);
            c.moveTo(x1 + (x2 - x1) * a, y1 + (y2 - y1) * a);
            c.lineTo(x1 + (x2 - x1) * b, y1 + (y2 - y1) * b);
        }
    }
    function bezier(entry, node, p, bend) {
        var mx = (entry.x + node.x) / 2, my = (entry.y + node.y) / 2, dx = node.x - entry.x, dy = node.y - entry.y;
        var length = Math.max(1, Math.hypot(dx, dy)), cx = mx - dy / length * bend, cy = my + dx / length * bend, q = 1 - p;
        return [q * q * entry.x + 2 * q * p * cx + p * p * node.x, q * q * entry.y + 2 * q * p * cy + p * p * node.y];
    }
    // Agent selection by pointer or arrow keys shares the service logic.
    function agentAt(x, y) {
        var best = null, distance = 60 * scale;
        scene.forEach(function(entry) {
            var d = Math.hypot(entry.x - x, entry.y - y);
            if (d < distance) { distance = d; best = entry.agent.id; }
        });
        return best;
    }
    function step(delta) {
        var agents = service.agents;
        if (!agents.length) return;
        var index = agents.findIndex(function(a) { return a.id === service.selection; });
        index = index < 0 ? (delta > 0 ? 0 : agents.length - 1) : (index + delta + agents.length) % agents.length;
        service.selection = agents[index].id;
    }

    activeFocusOnTab: !backdrop
    Accessible.role: Accessible.Graphic
    Accessible.name: service.zooming ? "Zoomed on " + Model.agentTitle(service.selected) + ". Escape shows all agents."
        : service.agents.length ? service.agents.length + " agents in the constellation. Arrow keys select an agent, Enter zooms." : "No active agents"
    Keys.onPressed: function(event) {
        if (event.modifiers !== Qt.NoModifier) return;
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) step(1);
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) step(-1);
        else if (event.key === Qt.Key_Home && service.selection) service.selection = "";
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && service.selection) service.zoomed = !service.zoomed;
        else if (event.key === Qt.Key_Escape && service.zooming) service.zoomed = false;
        else return;
        event.accepted = true;
    }

    Canvas {
        id: base
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            root.paintCount++;
            var c = getContext("2d"), w = width, h = height, fg = theme.text, bg = theme.background;
            c.reset();
            if (!root.backdrop) {
                var vignette = c.createRadialGradient(w / 2, h / 2, 40, w / 2, h / 2, Math.max(w, h) * 0.75);
                vignette.addColorStop(0, root.css(bg, 1));
                vignette.addColorStop(1, root.css(root.colors.mix(bg, root.light ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(0, 0, 0, 1), 0.3), 1));
                c.fillStyle = vignette; c.fillRect(0, 0, w, h);
                // Grid dots and fixed stars, seeded so they never jump between repaints.
                c.fillStyle = root.css(fg, 0.04);
                for (var gx = 20; gx < w; gx += 40) for (var gy = 20; gy < h; gy += 40) c.fillRect(gx, gy, 1.5, 1.5);
                for (var i = 0; i < 160; i++) {
                    var sx = Model.unit("x" + i) * w, sy = Model.unit("y" + i) * h, size = Model.unit("s" + i) * 1.4 + 0.6;
                    c.fillStyle = root.css(fg, 0.06 + Model.unit("a" + i) * 0.14); c.fillRect(sx, sy, size, size);
                }
            }
            var entries = root.scene;
            if (root.backdrop && root.veil > 0 && entries.length) {
                // The chosen background behind everything drawn, feathered into the
                // wallpaper by nested rounded rectangles whose opacities add up to veil.
                var feather = 48 * root.scale, x0 = w, y0 = h, x1 = 0, y1 = 0;
                var grow = function(x, y) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); };
                entries.forEach(function(entry) {
                    grow(entry.x - entry.radius * 1.2, entry.y - entry.radius * 1.2);
                    grow(entry.x + entry.radius * 1.2, entry.y + 100 * root.scale);
                    entry.files.forEach(function(node) { grow(node.x - 80 * root.scale, node.y - 30 * root.scale); grow(node.x + 80 * root.scale, node.y + 45 * root.scale); });
                });
                grow(w / 2 - Math.min(w * 0.3, 410 * root.scale), h);
                grow(w / 2 + Math.min(w * 0.3, 410 * root.scale), h - 90 * root.scale);
                x0 = Math.max(0, x0); y0 = Math.max(0, y0); x1 = Math.min(w, x1); y1 = Math.min(h, y1);
                var steps = 16, step = feather / steps;
                c.fillStyle = root.css(bg, 1 - Math.pow(1 - root.veil, 1 / steps));
                for (var s = 0; s < steps; s++) {
                    var inset = s * step, corner = feather - inset;
                    c.beginPath();
                    c.roundedRect(x0 + inset, y0 + inset, x1 - x0 - inset * 2, y1 - y0 - inset * 2, corner, corner);
                    c.fill();
                }
            }
            if (entries.length > 1) {
                c.strokeStyle = root.css(fg, 0.08); c.lineWidth = 1; c.beginPath();
                for (var k = 0; k < entries.length; k++) {
                    var from = entries[k], to = entries[(k + 1) % entries.length];
                    if (entries.length === 2 && k === 1) break;
                    root.dashed(c, from.x, from.y, to.x, to.y, 2, 8);
                }
                c.stroke();
            }
            entries.forEach(function(entry) {
                var dim = root.dimmed(entry) ? 0.3 : 1, color = entry.color;
                c.globalCompositeOperation = entry.light ? "source-over" : "lighter";
                var halo = c.createRadialGradient(entry.x, entry.y, 0, entry.x, entry.y, entry.radius * 1.3);
                halo.addColorStop(0, root.css(color, 0.16 * dim * (entry.agent.status === "idle" ? 0.4 : 1)));
                halo.addColorStop(1, root.css(color, 0));
                c.fillStyle = halo; c.fillRect(entry.x - entry.radius * 1.3, entry.y - entry.radius * 1.3, entry.radius * 2.6, entry.radius * 2.6);
                entry.files.forEach(function(node) {
                    var edge = c.createLinearGradient(entry.x, entry.y, node.x, node.y);
                    edge.addColorStop(0, root.css(color, 0.25 * dim));
                    edge.addColorStop(1, root.css(color, (0.04 + node.heat * 0.16) * dim));
                    c.strokeStyle = edge; c.lineWidth = 1; c.beginPath(); c.moveTo(entry.x, entry.y); c.lineTo(node.x, node.y); c.stroke();
                    var hot = node.heat > 0.6 ? root.colors.standOut(root.colors.role("orange"), entry.surface, entry.light) : color, glow = 8 + node.heat * 26;
                    var g = c.createRadialGradient(node.x, node.y, 0, node.x, node.y, glow);
                    g.addColorStop(0, root.css(hot, (0.2 + node.heat * 0.45) * dim)); g.addColorStop(1, root.css(hot, 0));
                    c.fillStyle = g; c.beginPath(); c.arc(node.x, node.y, glow, 0, Math.PI * 2); c.fill();
                    c.fillStyle = root.css(hot, 0.9 * dim); c.beginPath(); c.arc(node.x, node.y, 2.5 + node.heat * 4, 0, Math.PI * 2); c.fill();
                });
            });
            // Subagent orbits are static; the moving dots live in AgentMotion.
            entries.forEach(function(entry) {
                var dim = root.dimmed(entry) ? 0.3 : 1;
                c.globalCompositeOperation = entry.light ? "source-over" : "lighter";
                entry.agent.subagents.forEach(function(sub, index) {
                    var ring = (52 + index * 18) * root.scale, ink = root.colors.standOut(root.colors.role(Model.subagentRole(index)), entry.surface, entry.light);
                    c.strokeStyle = root.css(ink, 0.25 * dim); c.lineWidth = 1; c.beginPath();
                    for (var d = 0; d < Math.PI * 2; d += 0.16) {
                        c.moveTo(entry.x + Math.cos(d) * ring, entry.y + Math.sin(d) * ring * 0.82);
                        c.lineTo(entry.x + Math.cos(d + 0.06) * ring, entry.y + Math.sin(d + 0.06) * ring * 0.82);
                    }
                    c.stroke();
                });
            });
            c.globalCompositeOperation = "source-over";
            c.textAlign = "center";
            entries.forEach(function(entry) {
                var dim = root.dimmed(entry) ? 0.35 : 1, agent = entry.agent, text = root.ink(entry);
                // On the desktop a soft glow of the opposite ink lifts labels off a busy
                // wallpaper. The glow is a shadow cast from text drawn off the canvas, so
                // it never tints the glyphs; labels are also less faded there.
                var halo = root.css(entry.light === root.light ? theme.background : theme.text, 0.9 * dim);
                var label = function(value, x, y) {
                    if (root.backdrop) {
                        var fill = c.fillStyle, away = w + 1000;
                        c.fillStyle = halo; c.strokeStyle = halo; c.lineWidth = 4 * root.scale; c.lineJoin = "round";
                        c.shadowColor = halo; c.shadowBlur = 6 * root.scale; c.shadowOffsetX = away;
                        c.strokeText(value, x - away, y); c.fillText(value, x - away, y);
                        c.shadowBlur = 0; c.shadowOffsetX = 0; c.shadowColor = "transparent"; c.fillStyle = fill;
                    }
                    c.fillText(value, x, y);
                };
                entry.files.forEach(function(node) {
                    c.font = root.font(400, 11); c.fillStyle = root.css(text, (root.backdrop ? 0.65 + node.heat * 0.35 : 0.35 + node.heat * 0.55) * dim);
                    label(root.service.zooming ? Model.shortPath(node.path, 40) : node.name, node.x, node.y + 20 + node.heat * 5);
                    if ((node.file.added || node.file.removed) && (node.heat > 0.25 || root.service.zooming)) {
                        c.font = root.font(400, 10); c.fillStyle = root.css(root.colors.standOut(root.colors.role("green"), entry.surface, entry.light), 0.8 * dim);
                        label("+" + node.file.added + " −" + node.file.removed, node.x, node.y + 33 + node.heat * 5);
                    }
                });
                var y = entry.y + 70 * root.scale;
                c.font = root.font(800, 16); c.fillStyle = root.css(entry.color, dim);
                label(Model.agentTitle(agent).toUpperCase(), entry.x, y);
                c.font = root.font(400, 12); c.fillStyle = root.css(text, (root.backdrop ? 0.9 : 0.72) * dim);
                label(agent.status === "waiting" ? "⚠ WAITING · " + (agent.waitingFor || "input needed")
                    : [agent.model, Model.activityText(agent.activity)].filter(function(t) { return t; }).join(" · "), entry.x, y + 19 * root.scale);
            });
        }
    }
    // Moving parts are scene-graph items driven by one 30 fps clock. A full-window
    // canvas repainted every frame cost about a third of a core in the shell
    // process; vsync-driven animations still rendered the window at 60 fps.
    // Count-based models keep delegates (and their trail state) alive
    // across snapshots, which arrive every second as new arrays.
    Item {
        id: motion
        anchors.fill: parent
        Repeater {
            model: root.scene.length
            AgentMotion {
                required property int index
                entry: root.scene[index] || root.vacant
                colors: root.colors
                scale: root.scale
                fontFamily: root.fontFamily
                time: root.time
                particleLimit: root.particleLimit
                opacity: root.dimmed(entry) ? 0.3 : 1
            }
        }
    }
    TokenWaves {
        objectName: "tokenWaves"
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
        width: Math.min(parent.width * 0.6, 820 * root.scale)
        height: 72 * root.scale
        entries: root.scene
        colors: root.colors
        light: root.wavesLight
        time: root.time
        scale: root.scale
        fontFamily: root.fontFamily
    }
    // The scene edges glow red while any agent waits for input.
    Item {
        id: waitingEdges
        anchors.fill: parent
        visible: root.service.totals.waiting > 0
        readonly property real band: Math.min(width, height) * 0.05
        readonly property color red: root.colors.role("red")
        opacity: 0.65 + 0.2 * Math.sin(root.time * 3)
        Repeater {
            model: 4
            Rectangle {
                id: edge
                required property int index
                readonly property bool vertical: index > 1
                // Top and left fade inwards from their outer edge; bottom and right are mirrored.
                readonly property bool mirrored: index === 1 || index === 3
                readonly property color glow: Qt.rgba(waitingEdges.red.r, waitingEdges.red.g, waitingEdges.red.b, 0.3)
                x: index === 3 ? waitingEdges.width - width : 0
                y: index === 1 ? waitingEdges.height - height : 0
                width: vertical ? waitingEdges.band : waitingEdges.width
                height: vertical ? waitingEdges.height : waitingEdges.band
                gradient: Gradient {
                    orientation: edge.vertical ? Gradient.Horizontal : Gradient.Vertical
                    GradientStop { position: 0; color: edge.mirrored ? "transparent" : edge.glow }
                    GradientStop { position: 1; color: edge.mirrored ? edge.glow : "transparent" }
                }
            }
        }
    }
    Connections {
        target: root.Window.window
        function onFrameSwapped() {
            root.lastFrame = Date.now();
            root.presented = true;
        }
    }
    Timer {
        interval: root.frameInterval
        repeat: true
        running: root.running
        property double origin: Date.now() - root.time * 1000
        onRunningChanged: if (running) { origin = Date.now() - root.time * 1000; root.lastFrame = Date.now(); }
        onTriggered: {
            var now = Date.now();
            if (now - root.lastFrame > 1000) { root.presented = false; return; }
            root.time = (now - origin) / 1000;
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: !root.backdrop
        onClicked: function(mouse) {
            root.forceActiveFocus();
            var id = root.agentAt(mouse.x, mouse.y);
            if (id) root.service.select(id); else root.service.selection = "";
        }
        onDoubleClicked: function(mouse) {
            var id = root.agentAt(mouse.x, mouse.y);
            if (id) root.zoomTo(id);
        }
    }
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        spacing: 8
        visible: !root.backdrop && root.service.agents.length === 0
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.service.views.length === 0 || !root.service.snapshot ? (root.service.error || "Waiting for the first snapshot…") : "No active agents"
            color: theme.accent
            font.letterSpacing: 2
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: root.service.snapshot !== null
            color: theme.subdued
            font.pixelSize: theme.size * 0.85
            text: "Start Claude Code or Codex in a terminal; sessions appear here while they run. " + root.service.sourceStatus
        }
    }
}
