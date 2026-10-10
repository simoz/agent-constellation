pragma ComponentBehavior: Bound
import QtQuick
import "../Model.js" as Model

// Agent cores with orbiting subagents; tool calls fly out to the files they touch
// and hot files glow. Static geometry and labels live on one canvas repainted
// only when data, size, selection or theme change; motion is a second canvas
// redrawn at about 30 fps while visible, active and animating.
FocusScope {
    id: root
    objectName: "constellationScene"
    required property var service
    property bool active: true
    property int paintCount: 0
    property int basePaintCount: 0
    readonly property var palette: service.palette
    readonly property bool light: palette.light
    property real time: 0
    readonly property bool running: active && visible && service.moving && width > 0 && height > 0
    readonly property string fontFamily: theme.font
    readonly property real scale: Math.max(0.75, Math.min(1.25, Math.min(width, height) / 760))
    Theme { id: theme }

    // Layout in pixels, recomputed with the snapshot or the size.
    readonly property var scene: {
        // The service sorts by status for the list; the scene keeps a stable order so
        // a core does not jump when its agent starts waiting.
        var agents = service.agents.slice().sort(function(a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });
        var list = Model.centres(agents.length, width / Math.max(1, height));
        var radius = Model.reach(agents.length, width, height);
        // Files spread wider than tall (orbits are flattened to 0.82), labels sit below the core.
        var mx = Math.min(radius * 1.05, width * 0.25), my = Math.min(radius * 0.8, height * 0.22);
        return agents.map(function(agent, index) {
            var x = mx + list[index].x * (width - mx * 2), y = my + list[index].y * (height - my * 2);
            return {agent: agent, x: x, y: y, radius: radius, color: service.agentColor(agent),
                    files: Model.fileNodes(agent, x, y, radius)};
        });
    }
    readonly property string paintKey: JSON.stringify(service.snapshot ? service.snapshot.sequence : 0) + service.selection
        + width + "x" + height + String(theme.background) + String(theme.text) + JSON.stringify(palette.values) + light
    onPaintKeyChanged: { base.requestPaint(); motion.requestPaint(); }
    onRunningChanged: if (!running) motion.requestPaint()

    function css(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + (a === undefined ? c.a : a) + ")"; }
    function dimmed(entry) { return service.selection !== "" && entry.agent.id !== service.selection; }
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

    activeFocusOnTab: true
    Accessible.role: Accessible.Graphic
    Accessible.name: service.agents.length ? service.agents.length + " agents in the constellation. Arrow keys select an agent." : "No active agents"
    Keys.onPressed: function(event) {
        if (event.modifiers !== Qt.NoModifier) return;
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) step(1);
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) step(-1);
        else if (event.key === Qt.Key_Home && service.selection) service.selection = "";
        else return;
        event.accepted = true;
    }

    Canvas {
        id: base
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            root.paintCount++; root.basePaintCount++;
            var c = getContext("2d"), w = width, h = height, fg = theme.text, bg = theme.background;
            c.reset();
            var vignette = c.createRadialGradient(w / 2, h / 2, 40, w / 2, h / 2, Math.max(w, h) * 0.75);
            vignette.addColorStop(0, root.css(bg, 1));
            vignette.addColorStop(1, root.css(root.palette.mix(bg, root.light ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(0, 0, 0, 1), 0.3), 1));
            c.fillStyle = vignette; c.fillRect(0, 0, w, h);
            // Grid dots and fixed stars, seeded so they never jump between repaints.
            c.fillStyle = root.css(fg, 0.04);
            for (var gx = 20; gx < w; gx += 40) for (var gy = 20; gy < h; gy += 40) c.fillRect(gx, gy, 1.5, 1.5);
            for (var i = 0; i < 160; i++) {
                var sx = Model.unit("x" + i) * w, sy = Model.unit("y" + i) * h, size = Model.unit("s" + i) * 1.4 + 0.6;
                c.fillStyle = root.css(fg, 0.06 + Model.unit("a" + i) * 0.14); c.fillRect(sx, sy, size, size);
            }
            var entries = root.scene;
            if (entries.length > 1) {
                c.strokeStyle = root.css(fg, 0.08); c.lineWidth = 1; c.beginPath();
                for (var k = 0; k < entries.length; k++) {
                    var from = entries[k], to = entries[(k + 1) % entries.length];
                    if (entries.length === 2 && k === 1) break;
                    root.dashed(c, from.x, from.y, to.x, to.y, 2, 8);
                }
                c.stroke();
            }
            c.globalCompositeOperation = root.light ? "source-over" : "lighter";
            entries.forEach(function(entry) {
                var dim = root.dimmed(entry) ? 0.3 : 1, color = entry.color;
                var halo = c.createRadialGradient(entry.x, entry.y, 0, entry.x, entry.y, entry.radius * 1.3);
                halo.addColorStop(0, root.css(color, 0.16 * dim * (entry.agent.status === "idle" ? 0.4 : 1)));
                halo.addColorStop(1, root.css(color, 0));
                c.fillStyle = halo; c.fillRect(entry.x - entry.radius * 1.3, entry.y - entry.radius * 1.3, entry.radius * 2.6, entry.radius * 2.6);
                entry.files.forEach(function(node) {
                    var edge = c.createLinearGradient(entry.x, entry.y, node.x, node.y);
                    edge.addColorStop(0, root.css(color, 0.25 * dim));
                    edge.addColorStop(1, root.css(color, (0.04 + node.heat * 0.16) * dim));
                    c.strokeStyle = edge; c.lineWidth = 1; c.beginPath(); c.moveTo(entry.x, entry.y); c.lineTo(node.x, node.y); c.stroke();
                    var hot = node.heat > 0.6 ? root.palette.role("orange") : color, glow = 8 + node.heat * 26;
                    var g = c.createRadialGradient(node.x, node.y, 0, node.x, node.y, glow);
                    g.addColorStop(0, root.css(hot, (0.2 + node.heat * 0.45) * dim)); g.addColorStop(1, root.css(hot, 0));
                    c.fillStyle = g; c.beginPath(); c.arc(node.x, node.y, glow, 0, Math.PI * 2); c.fill();
                    c.fillStyle = root.css(hot, 0.9 * dim); c.beginPath(); c.arc(node.x, node.y, 2.5 + node.heat * 4, 0, Math.PI * 2); c.fill();
                });
            });
            c.globalCompositeOperation = "source-over";
            c.textAlign = "center";
            entries.forEach(function(entry) {
                var dim = root.dimmed(entry) ? 0.35 : 1, agent = entry.agent;
                entry.files.forEach(function(node) {
                    c.font = root.font(400, 11); c.fillStyle = root.css(fg, (0.35 + node.heat * 0.55) * dim);
                    c.fillText(node.name, node.x, node.y + 20 + node.heat * 5);
                    if ((node.file.added || node.file.removed) && node.heat > 0.25) {
                        c.font = root.font(400, 10); c.fillStyle = root.css(root.palette.role("green"), 0.8 * dim);
                        c.fillText("+" + node.file.added + " −" + node.file.removed, node.x, node.y + 33 + node.heat * 5);
                    }
                });
                var y = entry.y + 70 * root.scale;
                c.font = root.font(800, 16); c.fillStyle = root.css(entry.color, dim);
                c.fillText(Model.agentTitle(agent).toUpperCase(), entry.x, y);
                c.font = root.font(400, 12); c.fillStyle = root.css(fg, 0.72 * dim);
                c.fillText(agent.status === "waiting" ? "⚠ WAITING · " + (agent.waitingFor || "input needed")
                    : [agent.model, Model.activityText(agent.activity)].filter(function(t) { return t; }).join(" · "), entry.x, y + 19 * root.scale);
            });
        }
    }
    Canvas {
        id: motion
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            root.paintCount++;
            var c = getContext("2d"), t = root.time;
            c.reset();
            var waiting = false;
            c.globalCompositeOperation = root.light ? "source-over" : "lighter";
            root.scene.forEach(function(entry) {
                var agent = entry.agent, color = entry.color, dim = root.dimmed(entry) ? 0.3 : 1;
                var status = agent.status, busy = status === "working" || status === "thinking";
                if (status === "waiting") waiting = true;
                // Particles: outbound in the agent color, returning results in cyan.
                var recent = agent.activityBuckets.slice(-3).reduce(function(a, b) { return a + b; }, 0);
                var count = busy && entry.files.length ? Math.min(18, 3 + recent * 2) : 0, back = root.palette.role("cyan");
                for (var p = 0; p < count; p++) {
                    var key = agent.id + "#" + p, node = entry.files[Math.floor(Model.unit(key + "n") * Math.min(entry.files.length, 6))];
                    var speed = 0.25 + Model.unit(key + "s") * 0.35, returning = Model.unit(key + "b") < 0.3;
                    var bend = (Model.unit(key + "c") - 0.5) * entry.radius * 0.6;
                    var progress = (t * speed * (status === "thinking" ? 0.5 : 1) + Model.unit(key + "p")) % 1;
                    if (returning) progress = 1 - progress;
                    var ink = returning ? back : color;
                    for (var k = 0; k < 10; k++) {
                        var q = returning ? progress + k * 0.018 : progress - k * 0.018;
                        if (q < 0 || q > 1) break;
                        var point = root.bezier(entry, node, q, bend);
                        c.fillStyle = root.css(ink, (1 - k / 10) * 0.8 * dim);
                        c.beginPath(); c.arc(point[0], point[1], 2.6 * (1 - k / 13), 0, Math.PI * 2); c.fill();
                    }
                }
                // Subagents orbit the core with a short trail.
                agent.subagents.forEach(function(sub, index) {
                    var ring = (52 + index * 18) * root.scale, angle = t * (0.6 - index * 0.12) + index * 2.4;
                    var ink = root.palette.role(Model.subagentRole(index));
                    c.strokeStyle = root.css(ink, 0.25 * dim); c.lineWidth = 1; c.beginPath();
                    for (var d = 0; d < Math.PI * 2; d += 0.16) {
                        c.moveTo(entry.x + Math.cos(d) * ring, entry.y + Math.sin(d) * ring * 0.82);
                        c.lineTo(entry.x + Math.cos(d + 0.06) * ring, entry.y + Math.sin(d + 0.06) * ring * 0.82);
                    }
                    c.stroke();
                    for (var trail = 0; trail < 16; trail++) {
                        var a = angle - trail * 0.05;
                        c.fillStyle = root.css(ink, (trail ? 0.35 * (1 - trail / 16) : 0.95) * dim);
                        c.beginPath(); c.arc(entry.x + Math.cos(a) * ring, entry.y + Math.sin(a) * ring * 0.82, trail ? 2.2 : 4.5, 0, Math.PI * 2); c.fill();
                    }
                    c.font = root.font(600, 10); c.textAlign = "center"; c.fillStyle = root.css(ink, dim);
                    c.fillText(sub.name, entry.x + Math.cos(angle) * ring, entry.y + Math.sin(angle) * ring * 0.82 - 9);
                });
                // Core, rotating arcs and ripples. Waiting cores pulse harder.
                var pulse = status === "waiting" ? 1 + 0.25 * Math.sin(t * 4) : 1 + 0.06 * Math.sin(t * 5);
                var core = 16 * root.scale * pulse * (status === "idle" ? 0.7 : status === "thinking" ? 0.85 : 1);
                var glow = c.createRadialGradient(entry.x, entry.y, 0, entry.x, entry.y, core * 2.6);
                glow.addColorStop(0, root.css(root.light ? color : Qt.rgba(1, 1, 1, 1), 0.95 * dim));
                glow.addColorStop(0.25, root.css(color, 0.95 * dim)); glow.addColorStop(0.6, root.css(color, 0.3 * dim));
                glow.addColorStop(1, root.css(color, 0));
                c.fillStyle = glow; c.beginPath(); c.arc(entry.x, entry.y, core * 2.6, 0, Math.PI * 2); c.fill();
                c.lineWidth = 2;
                [[30, 1.1, 1.6], [37, -0.7, 2.4], [44, 0.45, 0.9]].forEach(function(arc, index) {
                    var start = t * arc[1] * (busy ? 1 : 0.3) + index, r = arc[0] * root.scale;
                    c.strokeStyle = root.css(color, (0.7 - index * 0.18) * dim);
                    c.beginPath(); c.arc(entry.x, entry.y, r, start, start + arc[2]); c.stroke();
                    c.beginPath(); c.arc(entry.x, entry.y, r, start + Math.PI, start + Math.PI + arc[2] * 0.4); c.stroke();
                });
                if (status !== "idle") {
                    var period = status === "waiting" ? 1.2 : 1.8;
                    for (var ripple = 0; ripple < 2; ripple++) {
                        var phase = (t / period + ripple * 0.5) % 1;
                        c.strokeStyle = root.css(color, (1 - phase) * (status === "waiting" ? 0.7 : 0.3) * dim);
                        c.lineWidth = status === "waiting" ? 3 : 1.5;
                        c.beginPath(); c.arc(entry.x, entry.y, (28 + phase * (status === "waiting" ? 130 : 80)) * root.scale, 0, Math.PI * 2); c.stroke();
                    }
                }
            });
            c.globalCompositeOperation = "source-over";
            // The scene edges glow red while any agent waits for input.
            if (waiting) {
                var red = root.palette.role("red"), band = Math.min(width, height) * 0.05, strength = 0.22 + 0.1 * Math.sin(t * 3);
                [[0, 0, 0, band, 0, 0, width, band], [0, height, 0, height - band, 0, height - band, width, band],
                 [0, 0, band, 0, 0, 0, band, height], [width, 0, width - band, 0, width - band, 0, band, height]].forEach(function(e) {
                    var g = c.createLinearGradient(e[0], e[1], e[2], e[3]);
                    g.addColorStop(0, root.css(red, strength)); g.addColorStop(1, root.css(red, 0));
                    c.fillStyle = g; c.fillRect(e[4], e[5], e[6], e[7]);
                });
            }
        }
    }
    Timer {
        interval: 33
        repeat: true
        running: root.running
        property double origin: Date.now()
        onTriggered: { root.time = (Date.now() - origin) / 1000; motion.requestPaint(); }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) {
            root.forceActiveFocus();
            var id = root.agentAt(mouse.x, mouse.y);
            if (id) root.service.select(id); else root.service.selection = "";
        }
    }
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        spacing: 8
        visible: root.service.agents.length === 0
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
