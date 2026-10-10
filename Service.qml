import QtQuick
import "Model.js" as Model
import "ui" as Constellation

Item {
    id: root
    property var shell: null
    property bool standalone: false
    property var saveConfiguration: null
    property bool paused: false
    property var views: []
    property bool claudeEnabled: true
    property bool codexEnabled: true
    property string claudeDir: ""
    property string codexDir: ""
    property int intervalSeconds: 1
    property int idleMinutes: 30
    property var savedConfiguration: ({})
    property var snapshot: null
    property string phase: "idle"
    property string error: ""
    // Registered bar views keep a slow watch so the bar can flag an agent waiting
    // for input; open panels and windows use the configured interval.
    readonly property int watchInterval: 5000
    readonly property int openViews: views.filter(function(v) { return v.open; }).length
    readonly property bool demanded: views.length > 0 && !paused
    readonly property int pollInterval: openViews > 0 ? intervalSeconds * 1000 : watchInterval
    readonly property string status: !views.length ? "IDLE" : paused ? "PAUSED" : phase.toUpperCase()
    readonly property var collectorArguments: {
        var sources = [];
        if (claudeEnabled) sources.push("claude");
        if (codexEnabled) sources.push("codex");
        var args = ["--sources", sources.join(","), "--idle-minutes", String(idleMinutes)];
        if (claudeDir) args.push("--claude-dir", claudeDir);
        if (codexDir) args.push("--codex-dir", codexDir);
        return args;
    }
    // Shared by every view: theme palette roles read from the active Omarchy theme.
    readonly property alias palette: palette
    Constellation.Palette { id: palette }
    Loader {
        id: transport
        active: root.shell !== null || root.standalone
        source: "Collector.qml"
        onLoaded: item.service = root
    }
    readonly property var collector: transport.item
    readonly property bool refreshing: collector ? collector.refreshing : false
    function refresh() { if (collector) collector.refresh(); }
    function retry() { if (collector) collector.retry(); }
    // Runtime helpers are Python scripts shipped in tools/ beside this file.
    function helperPath(name) { return decodeURIComponent(Qt.resolvedUrl("tools/" + name).toString().slice(7)); }
    function setView(token, open) {
        var next = views.filter(function(v) { return v.token !== token; });
        next.push({token: token, open: open}); views = next;
    }
    function removeView(token) { views = views.filter(function(v) { return v.token !== token; }); }

    function configure(claude, codex, claudePath, codexPath, interval, idle) {
        var seconds = Number(interval), minutes = Number(idle);
        if (!validPath(claudePath) || !validPath(codexPath) || /[\x00-\x1f]/.test(claudePath + codexPath)) return "Use absolute directory paths.";
        if (!validInterval(seconds)) return "Refresh interval must be 1–10 seconds.";
        if (!validIdle(minutes)) return "Idle sessions must be hidden after 1–1440 minutes.";
        var config = Object.assign({}, savedConfiguration, {sources: {claude: claude, codex: codex}, claudeDir: claudePath,
            codexDir: codexPath, intervalSeconds: seconds, idleMinutes: minutes});
        // updateEntryInline returns whether shell.json changed, not whether saving
        // failed: an entry that is already up to date also returns false.
        if (shell) shell.updateEntryInline("io.github.simoz.agent-constellation", config);
        else if (saveConfiguration && JSON.stringify(config) !== JSON.stringify(savedConfiguration) && !saveConfiguration(config)) return "Unable to save settings.";
        loadConfiguration(config); return "";
    }
    function loadConfiguration(config) {
        if (!config || JSON.stringify(config) === JSON.stringify(savedConfiguration)) return;
        savedConfiguration = config;
        var sources = config.sources && typeof config.sources === "object" ? config.sources : {};
        claudeEnabled = sources.claude !== false;
        codexEnabled = sources.codex !== false;
        claudeDir = typeof config.claudeDir === "string" && validPath(config.claudeDir) ? config.claudeDir : "";
        codexDir = typeof config.codexDir === "string" && validPath(config.codexDir) ? config.codexDir : "";
        intervalSeconds = validInterval(config.intervalSeconds) ? config.intervalSeconds : 1;
        idleMinutes = validIdle(config.idleMinutes) ? config.idleMinutes : 30;
    }
    // Empty paths select the defaults (CLAUDE_CONFIG_DIR / CODEX_HOME, then ~/.claude and ~/.codex).
    function validPath(path) { return !path || (path[0] === "/" && path.length <= 4096); }
    function validInterval(seconds) { return Number.isInteger(seconds) && seconds >= 1 && seconds <= 10; }
    function validIdle(minutes) { return Number.isInteger(minutes) && minutes >= 1 && minutes <= 1440; }

    property string selection: ""
    // Not a user setting: the host exposes no reduced-motion preference. Kept for
    // tests, captures and a future accessibility option.
    property bool reducedMotion: false
    property bool animating: true
    readonly property bool moving: animating && !reducedMotion
    readonly property var agents: snapshot ? snapshot.agents : []
    readonly property var events: snapshot ? snapshot.events : []
    readonly property var totals: Model.summary(agents)
    readonly property var selected: agents.filter(function(a) { return a.id === selection; })[0] || null
    readonly property string sourceStatus: {
        if (!snapshot) return "No snapshot yet";
        return ["Claude Code: " + snapshot.sources.claude, "Codex: " + snapshot.sources.codex].join(" · ");
    }
    property var roles: ({})
    onAgentsChanged: roles = Model.assignRoles(agents, roles)
    function agentColor(agent) { return palette.role(Model.agentRole(agent, roles)); }
    function agentById(id) { return agents.filter(function(a) { return a.id === id; })[0] || null; }
    function select(id) { selection = selection === id ? "" : id; }
    onSelectedChanged: if (selection && !selected) selection = ""
}
