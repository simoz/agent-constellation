// Shared view logic: layout, colors and labels. Pure functions, tested with Node.

// Red stays reserved for agents waiting on the user.
var agentRoles = ["blue", "green", "orange", "magenta", "cyan", "yellow"];
var subagentRoles = ["magenta", "cyan", "yellow", "green", "blue", "orange"];

// FNV-1a keeps positions and colors stable across snapshots and restarts.
function hash(value) {
    var h = 0x811c9dc5;
    for (var i = 0; i < value.length; i++) {
        h ^= value.charCodeAt(i);
        h = Math.imul(h, 0x01000193) >>> 0;
    }
    return h;
}
function unit(value) { return hash(value) / 4294967296; }

// Each agent keeps its color while visible: its hashed role when free, otherwise
// the first unused one. Waiting agents are drawn red without losing their role.
function assignRoles(agents, previous) {
    var roles = {}, used = {};
    agents.forEach(function(agent) {
        if (previous[agent.id]) { roles[agent.id] = previous[agent.id]; used[previous[agent.id]] = true; }
    });
    agents.forEach(function(agent) {
        if (roles[agent.id]) return;
        var start = hash(agent.id) % agentRoles.length, role = agentRoles[start];
        for (var i = 0; i < agentRoles.length && used[role]; i++) role = agentRoles[(start + i) % agentRoles.length];
        roles[agent.id] = role; used[role] = true;
    });
    return roles;
}
function agentRole(agent, roles) {
    if (agent.status === "waiting") return "red";
    return (roles && roles[agent.id]) || agentRoles[hash(agent.id) % agentRoles.length];
}
function subagentRole(index) { return subagentRoles[index % subagentRoles.length]; }

// Normalized agent centres (0…1) for a scene of the given aspect ratio.
function centres(count, aspect) {
    if (count === 0) return [];
    if (count === 1) return [{x: 0.5, y: 0.5}];
    if (count === 2) return aspect >= 1 ? [{x: 0.25, y: 0.42}, {x: 0.75, y: 0.6}] : [{x: 0.42, y: 0.25}, {x: 0.6, y: 0.75}];
    if (count === 3) return aspect >= 1 ? [{x: 0.2, y: 0.62}, {x: 0.55, y: 0.2}, {x: 0.82, y: 0.72}]
                                        : [{x: 0.62, y: 0.2}, {x: 0.2, y: 0.55}, {x: 0.72, y: 0.82}];
    // More agents share a grid whose shape follows the scene.
    var columns = Math.max(1, Math.round(Math.sqrt(count * Math.max(aspect, 0.3))));
    var rows = Math.ceil(count / columns), result = [];
    for (var i = 0; i < count; i++) {
        var row = Math.floor(i / columns), inRow = Math.min(columns, count - row * columns), col = i % columns;
        result.push({x: (col + 0.5) / inRow, y: (row + 0.5) / rows});
    }
    return result;
}

// Orbit radius for files around an agent core, in pixels.
function reach(count, width, height) {
    var cell = Math.min(width, height) / (count <= 1 ? 1 : count <= 3 ? 2 : Math.sqrt(count) * 1.25);
    return Math.max(70, Math.min(300, cell * 0.42));
}

// Angles derived from the path keep a file in place across snapshots; a few
// relaxation passes then enforce a minimum gap so labels do not collide.
function spreadAngles(keys) {
    var n = keys.length, gap = Math.PI * 2 / Math.max(n, 1) * 0.8;
    var items = keys.map(function(key, index) { return {index: index, angle: unit(key) * Math.PI * 2}; })
        .sort(function(a, b) { return a.angle - b.angle; });
    for (var pass = 0; pass < 12 && n > 1; pass++) {
        for (var i = 0; i < n; i++) {
            var a = items[i], b = items[(i + 1) % n];
            var delta = b.angle - a.angle + (i === n - 1 ? Math.PI * 2 : 0);
            if (delta < gap) { a.angle -= (gap - delta) / 2; b.angle += (gap - delta) / 2; }
        }
    }
    var result = [];
    items.forEach(function(item, order) { result[item.index] = {angle: item.angle, order: order}; });
    return result;
}

// File positions around a core: hotter files sit closer; neighbours alternate
// between two rings to give their labels more room.
function fileNodes(agent, x, y, radius) {
    var angles = spreadAngles(agent.files.map(function(file) { return agent.id + "/" + file.path; }));
    return agent.files.map(function(file, index) {
        var angle = angles[index].angle, ring = angles[index].order % 2 ? 1.08 : 0.9;
        var distance = radius * ring * (0.78 + 0.22 * (1 - file.heat));
        return {path: file.path, name: baseName(file.path), heat: file.heat, file: file,
                x: x + Math.cos(angle) * distance, y: y + Math.sin(angle) * distance * 0.82};
    });
}

// The end of a path, which names the file, survives truncation.
function shortPath(path, max) {
    var chars = Array.from(String(path));
    return chars.length <= max ? chars.join("") : "…" + chars.slice(chars.length - max + 1).join("");
}
function baseName(path) {
    var parts = String(path).split("/");
    return parts[parts.length - 1] || path;
}
function tokens(value) {
    if (value >= 1e6) return (value / 1e6).toFixed(1) + "M";
    if (value >= 1e3) return (value / 1e3).toFixed(value >= 1e4 ? 0 : 1) + "k";
    return String(value);
}
function statusLabel(status) {
    return {working: "WORKING", thinking: "THINKING", waiting: "WAITING", idle: "IDLE"}[status] || "IDLE";
}
function ago(ms, now) {
    var seconds = Math.max(0, Math.round((now - ms) / 1000));
    if (seconds < 60) return seconds + "s";
    if (seconds < 3600) return Math.floor(seconds / 60) + "m";
    return Math.floor(seconds / 3600) + "h";
}
function clock(ms) {
    var d = new Date(ms);
    function two(n) { return (n < 10 ? "0" : "") + n; }
    return two(d.getHours()) + ":" + two(d.getMinutes()) + ":" + two(d.getSeconds());
}
function activityText(activity) {
    if (!activity) return "No tool calls yet";
    return (activity.subagent ? activity.subagent + " ▸ " : "") + activity.tool + (activity.target ? " " + activity.target : "");
}
function agentTitle(agent) { return agent.kind + " · " + agent.project; }
function summary(agents) {
    var waiting = agents.filter(function(a) { return a.status === "waiting"; }).length;
    var busy = agents.filter(function(a) { return a.status === "working" || a.status === "thinking"; }).length;
    var subagents = agents.reduce(function(n, a) { return n + a.subagents.length; }, 0);
    var rate = agents.reduce(function(n, a) { return n + a.tokensPerMinute; }, 0);
    return {agents: agents.length, waiting: waiting, busy: busy, subagents: subagents, tokensPerMinute: rate,
            toolCalls: agents.reduce(function(n, a) { return n + a.toolCalls; }, 0)};
}
