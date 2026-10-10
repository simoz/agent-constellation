import QtQuick
import QtTest
import "../ui" as Constellation
import "../Model.js" as Model

Item {
    id: root
    width: 1200
    height: 820

    QtObject {
        id: themeColors
        property var values: ({})
        property bool light: false
        function role(name) { return Qt.lighter(name === "red" ? "#d27a7a" : "#83b6a6", 1); }
        function mix(a, b, k) { return Qt.lighter(a, 1); }
    }
    QtObject {
        id: service
        property var colors: themeColors
        property bool paused: false
        property bool animating: true
        property bool reducedMotion: true
        readonly property bool moving: animating && !reducedMotion
        property string selection: ""
        property bool refreshing: false
        property int refreshes: 0
        property string error: ""
        property string status: "LIVE"
        property var views: [{token: root, open: true}]
        property string sourceStatus: "Claude Code: ok · Codex: ok"
        property var snapshot: ({sequence: 1, observedAtMs: 1800000000000})
        property var agents: [agent("claude:a", "working"), agent("codex:b", "waiting")]
        property var events: [{atMs: 1800000000000, agent: "claude:a", subagent: "", tool: "Edit", target: "a.rb"}]
        readonly property var totals: Model.summary(agents)
        readonly property var selected: agents.filter(function(a) { return a.id === selection; })[0] || null
        property bool zoomed: false
        readonly property bool zooming: zoomed && selected !== null
        onSelectionChanged: if (!selection) zoomed = false
        property bool claudeEnabled: true
        property bool codexEnabled: true
        property string claudeDir: ""
        property string codexDir: ""
        property int intervalSeconds: 1
        property int idleMinutes: 30
        property bool notifyWaiting: true
        property bool backdropEnabled: false
        function agent(id, status) {
            return {id: id, kind: id.split(":")[0], name: "demo", project: "demo-" + id, model: "m", status: status, waitingFor: "",
                activity: null, toolCalls: 1, outputTokens: 10, tokensPerMinute: 5, activityBuckets: Array(30).fill(1), pids: id === "claude:a" ? [4242, 4200] : [],
                subagents: [], files: [{path: "a.rb", touches: 1, edits: 1, added: 1, removed: 0, heat: 1, lastMs: 0, subagent: ""}]};
        }
        function agentColor(a) { return themeColors.role(Model.agentRole(a, {})); }
        function agentById(id) { return agents.filter(function(a) { return a.id === id; })[0] || null; }
        function select(id) { selection = selection === id ? "" : id; }
        function refresh() { refreshes++; }
        function retry() {}
        function configure() { return ""; }
        property string notice: ""
        property var focused: []
        function canFocus(a) { return !!a && a.pids.length > 0; }
        function focusAgent(a) { focused = focused.concat([a ? a.id : null]); }
    }
    Constellation.Dashboard {
        id: dashboard
        anchors.fill: parent
        service: service
    }
    SignalSpy { id: closeSpy; target: dashboard; signalName: "closeRequested" }
    SignalSpy { id: expandSpy; target: dashboard; signalName: "expandRequested" }

    TestCase {
        name: "Dashboard"
        when: windowShown
        function init() {
            service.paused = false; service.animating = true; service.selection = ""; service.refreshes = 0; service.focused = []; service.zoomed = false;
            closeSpy.clear(); expandSpy.clear();
            dashboard.scene.forceActiveFocus();
        }
        function test_action_shortcuts() {
            keyClick(Qt.Key_P, Qt.ControlModifier);
            compare(service.paused, true);
            keyClick(Qt.Key_G, Qt.ControlModifier);
            compare(service.animating, false);
            keyClick(Qt.Key_R, Qt.ControlModifier);
            compare(service.refreshes, 1);
            keyClick(Qt.Key_E, Qt.ControlModifier);
            compare(expandSpy.count, 1);
        }
        function test_scene_keys_select_agents() {
            keyClick(Qt.Key_Right);
            compare(service.selection, "claude:a");
            keyClick(Qt.Key_Right);
            compare(service.selection, "codex:b");
            keyClick(Qt.Key_Home);
            compare(service.selection, "");
            keyClick(Qt.Key_Left);
            compare(service.selection, "codex:b");
            keyClick(Qt.Key_R, Qt.ControlModifier | Qt.ShiftModifier);
            compare(service.selection, "");
        }
        function test_agent_cards_toggle_selection() {
            var list = dashboard.agentList.list;
            list.currentIndex = 0;
            list.currentItem.forceActiveFocus();
            keyClick(Qt.Key_Down);
            verify(list.itemAtIndex(1).activeFocus);
            keyClick(Qt.Key_Space);
            compare(service.selection, "codex:b");
            keyClick(Qt.Key_Space);
            compare(service.selection, "");
        }
        function test_terminal_goes_to_focused_card_or_selection() {
            var button = findChild(dashboard, "terminalButton");
            verify(!button.enabled);
            keyClick(Qt.Key_T, Qt.ControlModifier);
            compare(service.focused, [null]);
            service.selection = "claude:a";
            verify(button.enabled);
            mouseClick(button);
            var list = dashboard.agentList.list;
            list.currentIndex = 1;
            list.currentItem.forceActiveFocus();
            keyClick(Qt.Key_T, Qt.ControlModifier);
            compare(service.focused, [null, "claude:a", "codex:b"]);
            service.selection = "codex:b";
            verify(!button.enabled);
        }
        function test_zoom_follows_selection() {
            var button = findChild(dashboard, "zoomButton");
            verify(!button.enabled);
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Return);
            compare(service.zooming, true);
            compare(dashboard.scene.scene.length, 1);
            keyClick(Qt.Key_Right);
            compare(service.selection, "codex:b");
            compare(service.zooming, true, "arrows keep the zoom on the next agent");
            keyClick(Qt.Key_Escape);
            compare(service.zooming, false);
            compare(closeSpy.count, 0, "Escape leaves the zoom before closing");
            compare(dashboard.scene.scene.length, 2);
            keyClick(Qt.Key_Z, Qt.ControlModifier);
            compare(service.zooming, true);
            keyClick(Qt.Key_Home);
            compare(service.zooming, false);
            compare(service.zoomed, false);
        }
        function test_help_and_escape() {
            var help = findChild(dashboard, "constellationKeyboardHelp");
            keyClick(Qt.Key_F1);
            tryCompare(help, "opened", true);
            keyClick(Qt.Key_P, Qt.ControlModifier);
            compare(service.paused, false, "action shortcuts are inactive while the guide is open");
            keyClick(Qt.Key_Escape);
            tryCompare(help, "visible", false);
            compare(closeSpy.count, 0);
            keyClick(Qt.Key_Escape);
            compare(closeSpy.count, 1);
        }
        function test_settings_open_with_shortcut() {
            var settings = findChild(dashboard, "constellationSettings");
            keyClick(Qt.Key_Comma, Qt.ControlModifier);
            tryCompare(settings, "opened", true);
            keyClick(Qt.Key_Escape);
            tryCompare(settings, "visible", false);
        }
    }
}
