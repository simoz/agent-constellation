// Validation of collector replies (docs/protocol.md). Shared by QML and the Node tests.
// ASCII JSON permits arbitrary pipe chunk boundaries without splitting UTF-8.
var maxLine = 2 * 1024 * 1024;
var statuses = ["working", "thinking", "waiting", "idle"];
var sourceStates = ["ok", "missing", "disabled", "error"];
function frame(buffer, chunk) {
    if (typeof chunk !== "string" || /[^\x00-\x7f]/.test(chunk) || chunk.length > maxLine) throw new Error("Invalid transport encoding or size");
    var lines = [], start = 0, end;
    while ((end = chunk.indexOf("\n", start)) >= 0) {
        if (buffer.length + end - start + 1 > maxLine) throw new Error("Snapshot too large");
        lines.push(buffer + chunk.slice(start, end));
        if (lines.length > 1) throw new Error("Unsolicited snapshots");
        buffer = ""; start = end + 1;
    }
    buffer += chunk.slice(start);
    if (buffer.length >= maxLine) throw new Error("Unterminated snapshot too large");
    return {buffer: buffer, lines: lines};
}
function integer(value) { return Number.isSafeInteger(value) && value >= 0; }
function text(value, max) { return typeof value === "string" && Array.from(value).length <= max && !/[\x00-\x1f\x7f]/.test(value); }
function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function list(value, max) { return Array.isArray(value) && value.length <= max; }
function check(condition) { if (!condition) throw new Error("Invalid snapshot"); }
function activity(a) {
    return a === null || (object(a) && text(a.tool, 40) && text(a.target, 160) && integer(a.atMs) && text(a.subagent, 40));
}
function agent(a) {
    check(object(a) && text(a.id, 200) && (a.kind === "claude" || a.kind === "codex"));
    check(text(a.name, 60) && text(a.project, 60) && text(a.model, 60) && statuses.indexOf(a.status) >= 0 && text(a.waitingFor, 60));
    check(activity(a.activity) && integer(a.toolCalls) && integer(a.outputTokens) && integer(a.tokensPerMinute));
    check(list(a.activityBuckets, 30) && a.activityBuckets.length === 30 && a.activityBuckets.every(integer));
    check(list(a.subagents, 6) && a.subagents.every(function(s) { return object(s) && text(s.id, 200) && text(s.name, 40) && text(s.type, 40); }));
    check(list(a.files, 16) && a.files.every(function(f) {
        return object(f) && text(f.path, 160) && integer(f.touches) && integer(f.edits) && integer(f.added) && integer(f.removed)
            && typeof f.heat === "number" && f.heat >= 0 && f.heat <= 1 && integer(f.lastMs) && text(f.subagent, 40);
    }));
}
// Throws unless the reply answers the pending request with a newer sequence of the same session.
function parse(line, requestId, session, sequence) {
    var s = JSON.parse(line);
    check(object(s) && s.version === 1 && s.requestId === requestId && s.error === undefined);
    check(typeof s.session === "string" && /^[0-9a-f]{16}$/.test(s.session) && integer(s.sequence) && integer(s.observedAtMs));
    check(s.session !== session ? s.sequence === 1 || session === "" : s.sequence > sequence);
    check(s.status === "ok" || s.status === "partial");
    check(object(s.sources) && ["claude", "codex"].every(function(k) { return sourceStates.indexOf(s.sources[k]) >= 0; }));
    check(list(s.agents, 24)); s.agents.forEach(agent);
    var ids = s.agents.map(function(a) { return a.id; });
    check(ids.every(function(id, i) { return ids.indexOf(id) === i; }));
    check(list(s.events, 40) && s.events.every(function(e) {
        return object(e) && integer(e.atMs) && ids.indexOf(e.agent) >= 0 && text(e.subagent, 40) && text(e.tool, 40) && text(e.target, 160);
    }));
    return s;
}
