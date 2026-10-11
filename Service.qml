import QtQuick
import Quickshell.Io
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
    property bool notifyWaiting: true
    property bool backdropEnabled: false
    // Workspace ids that show the backdrop; empty means every workspace.
    property var backdropWorkspaces: []
    // Opacity, 0–100, of the theme background behind the desktop constellation.
    property int backdropBackground: 0
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
    // Shared by every view: named theme colors read from the active Omarchy theme.
    readonly property alias colors: themeColors
    Constellation.Palette { id: themeColors }
    Loader {
        id: transport
        active: root.shell !== null || root.standalone
        source: "Collector.qml"
        onLoaded: item.service = root
    }
    readonly property var collector: transport.item
    // The constellation on the desktop, when enabled in Settings.
    Loader {
        active: root.backdropEnabled && (root.shell !== null || root.standalone)
        source: "Backdrop.qml"
        onLoaded: item.service = root
    }
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

    function configure(claude, codex, claudePath, codexPath, interval, idle, notify, backdrop, workspaces, background) {
        var seconds = Number(interval), minutes = Number(idle), desktops = Model.parseWorkspaces(workspaces || "");
        if (!validPath(claudePath) || !validPath(codexPath) || /[\x00-\x1f]/.test(claudePath + codexPath)) return "Use absolute directory paths.";
        if (!validInterval(seconds)) return "Refresh interval must be 1–10 seconds.";
        if (!validIdle(minutes)) return "Idle sessions must be hidden after 1–1440 minutes.";
        if (desktops === null) return "Workspaces must be numbers 1–99, such as 3, 1-5 or 1, 3, 5.";
        if (!validBackground(background)) return "Desktop background must be 0–100%.";
        var config = Object.assign({}, savedConfiguration, {sources: {claude: claude, codex: codex}, claudeDir: claudePath,
            codexDir: codexPath, intervalSeconds: seconds, idleMinutes: minutes, notifyWaiting: notify !== false, backdrop: backdrop === true,
            backdropWorkspaces: desktops, backdropBackground: background});
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
        notifyWaiting = config.notifyWaiting !== false;
        backdropEnabled = config.backdrop === true;
        backdropWorkspaces = Model.validWorkspaces(config.backdropWorkspaces) ? config.backdropWorkspaces : [];
        backdropBackground = validBackground(config.backdropBackground) ? config.backdropBackground : 0;
    }
    // Empty paths select the defaults (CLAUDE_CONFIG_DIR / CODEX_HOME, then ~/.claude and ~/.codex).
    function validPath(path) { return !path || (path[0] === "/" && path.length <= 4096); }
    function validInterval(seconds) { return Number.isInteger(seconds) && seconds >= 1 && seconds <= 10; }
    function validIdle(minutes) { return Number.isInteger(minutes) && minutes >= 1 && minutes <= 1440; }
    function validBackground(percent) { return Number.isInteger(percent) && percent >= 0 && percent <= 100; }

    property string selection: ""
    // Zoom shows only the selected agent; it ends with the selection.
    property bool zoomed: false
    readonly property bool zooming: zoomed && selected !== null
    onSelectionChanged: if (!selection) zoomed = false
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
    function agentColor(agent) { return themeColors.role(Model.agentRole(agent, roles)); }
    function agentById(id) { return agents.filter(function(a) { return a.id === id; })[0] || null; }
    function select(id) { selection = selection === id ? "" : id; }
    onSelectedChanged: if (selection && !selected) selection = ""

    // Going to an agent's terminal: the nearest ancestor of the agent process that
    // owns a Hyprland window. Terminals that serve several windows from one
    // process (a server mode) match their first window.
    property string notice: ""
    property var focusPids: []
    function canFocus(agent) { return !!agent && agent.pids.length > 0; }
    function focusAgent(agent) {
        if (!agent) { showNotice("Select an agent first"); return; }
        if (!canFocus(agent)) { showNotice("No terminal known for " + Model.agentTitle(agent)); return; }
        if (windowList.running) return;
        focusPids = agent.pids;
        windowList.running = true;
    }
    function showNotice(text) { notice = text; noticeTimer.restart(); }
    function focusWindow(output) {
        var clients = [];
        try { clients = JSON.parse(output); } catch (e) {}
        var best = null, rank = focusPids.length;
        (Array.isArray(clients) ? clients : []).forEach(function(c) {
            var index = c && typeof c.address === "string" && /^0x[0-9a-f]+$/.test(c.address) ? focusPids.indexOf(c.pid) : -1;
            if (index >= 0 && index < rank) { best = c; rank = index; }
        });
        if (!best) { showNotice("Terminal window not found"); return; }
        windowFocus.command = ["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + best.address + "\" })"];
        windowFocus.running = true;
    }
    Process {
        id: windowList
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector { onStreamFinished: root.focusWindow(text) }
    }
    Process { id: windowFocus }

    // A desktop notification when an agent starts waiting for input. notify-send
    // waits for the reply, so each notification owns its process until closed.
    property var waitingSeen: null
    property int openNotifications: 0
    onSnapshotChanged: {
        if (!snapshot) return;
        if (notifyWaiting) Model.newlyWaiting(waitingSeen, agents).forEach(notifyWaitingAgent);
        waitingSeen = Model.waitingIds(agents);
    }
    function notifyWaitingAgent(agent) {
        if (openNotifications >= 4) return;
        var id = agent.id;
        notification.createObject(root, {command: ["notify-send", "--app-name=Agent Constellation",
            "--action=focus=Go to terminal", Model.agentTitle(agent) + " is waiting",
            "Waiting for " + (agent.waitingFor || "input") + "."], agentId: id});
    }
    Component {
        id: notification
        Process {
            id: alert
            property string agentId: ""
            running: true
            Component.onCompleted: root.openNotifications++
            Component.onDestruction: root.openNotifications--
            stdout: StdioCollector {
                onStreamFinished: if (text.trim() === "focus") root.focusAgent(root.agentById(alert.agentId))
            }
            onExited: destroy()
        }
    }
    Timer { id: noticeTimer; interval: 4000; onTriggered: root.notice = "" }
}
