pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as C
import QtQuick.Layouts
import "../Model.js" as Model

C.Popup {
    id: root
    objectName: "constellationSettings"
    required property var service
    property string validationError: ""
    property int section: 0
    property bool claude: true
    property bool codex: true
    property bool notify: true
    property bool backdrop: false
    onSectionChanged: scroll.contentY = 0
    width: Math.min(560, parent.width - 24)
    height: Math.min(parent.height - 24, 620)
    x: Math.max(12, parent.width - width - 12)
    y: Math.max(12, Math.min(58, parent.height - height - 12))
    padding: 16
    focus: true
    closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutside
    Theme { id: theme }
    onAboutToShow: {
        claude = service.claudeEnabled; codex = service.codexEnabled; notify = service.notifyWaiting; backdrop = service.backdropEnabled;
        claudeDir.text = service.claudeDir; codexDir.text = service.codexDir;
        interval.text = String(service.intervalSeconds); idle.text = String(service.idleMinutes);
        workspaces.text = Model.formatWorkspaces(service.backdropWorkspaces);
        validationError = ""; scroll.contentY = 0;
    }
    background: Rectangle { color: theme.background; Frame { anchors.fill: parent; emphasized: true } }
    contentItem: ColumnLayout {
        spacing: 12
        Label { text: "CONSTELLATION / SETTINGS"; color: theme.accent; font.letterSpacing: 1 }
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                objectName: "settingsSections"
                model: ["Sources", "Collection", "About"]
                ActionButton {
                    required property int index
                    required property string modelData
                    objectName: "settingsSection" + index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: modelData
                    selected: root.section === index
                    onClicked: root.section = index
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: C.ScrollBar {}
            ColumnLayout {
                id: body
                width: scroll.width - 12
                spacing: 10
                ColumnLayout {
                    visible: root.section === 0
                    Layout.fillWidth: true
                    spacing: 10
                    Label { text: "Agent sources"; font.bold: true }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Choose which local session files to read. Nothing is written to agent settings."; color: theme.subdued; font.pixelSize: theme.size * 0.9 }
                    ActionButton {
                        objectName: "claudeSourceToggle"
                        Layout.fillWidth: true
                        text: (root.claude ? "■ " : "□ ") + "Claude Code"
                        hint: "Read Claude Code sessions"
                        selected: root.claude
                        onClicked: root.claude = !root.claude
                    }
                    Label { text: "Claude Code directory"; color: theme.subdued }
                    SearchField { id: claudeDir; objectName: "claudeDirField"; Layout.fillWidth: true; placeholderText: "Default: $CLAUDE_CONFIG_DIR or ~/.claude" }
                    ActionButton {
                        objectName: "codexSourceToggle"
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        text: (root.codex ? "■ " : "□ ") + "Codex"
                        hint: "Read Codex sessions"
                        selected: root.codex
                        onClicked: root.codex = !root.codex
                    }
                    Label { text: "Codex directory"; color: theme.subdued }
                    SearchField { id: codexDir; objectName: "codexDirField"; Layout.fillWidth: true; placeholderText: "Default: $CODEX_HOME or ~/.codex" }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.service.sourceStatus; font.pixelSize: theme.size * 0.85 }
                }
                ColumnLayout {
                    visible: root.section === 1
                    Layout.fillWidth: true
                    spacing: 10
                    Label { text: "Collection"; font.bold: true }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Control how often agent activity refreshes and which sessions stay visible."; color: theme.subdued; font.pixelSize: theme.size * 0.9 }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.service.error || ("Status: " + root.service.status); font.pixelSize: theme.size * 0.9 }
                    RowLayout {
                        Layout.fillWidth: true
                        ActionButton { Layout.fillWidth: true; text: root.service.paused ? "Resume collection" : "Pause collection"; onClicked: root.service.paused = !root.service.paused }
                        ActionButton { text: "Retry"; onClicked: root.service.retry() }
                    }
                    Label { text: "Refresh interval · seconds (1–10)" }
                    SearchField { id: interval; objectName: "intervalField"; Layout.fillWidth: true; Accessible.name: "Refresh interval in seconds" }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Applies while a panel or window is open. With only the bar icon, sessions are checked every 5 seconds so a waiting agent can turn the icon red."; font.pixelSize: theme.size * 0.85; color: theme.subdued }
                    Label { text: "Hide idle sessions after · minutes (1–1440)" }
                    SearchField { id: idle; objectName: "idleField"; Layout.fillWidth: true; Accessible.name: "Minutes before idle sessions are hidden" }
                    ActionButton {
                        objectName: "notifyToggle"
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        text: (root.notify ? "■ " : "□ ") + "Notify when an agent waits"
                        hint: "Show a desktop notification when an agent starts waiting for input"
                        selected: root.notify
                        onClicked: root.notify = !root.notify
                    }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "The notification offers Go to terminal. It needs the bar icon, which keeps checking sessions every 5 seconds."; font.pixelSize: theme.size * 0.85; color: theme.subdued }
                    ActionButton {
                        objectName: "backdropToggle"
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        text: (root.backdrop ? "■ " : "□ ") + "Show on the desktop"
                        hint: "Draw the constellation over the wallpaper, below windows"
                        selected: root.backdrop
                        onClicked: root.backdrop = !root.backdrop
                    }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Ignores the pointer and refreshes at the interval above. It moves only while an agent is busy or waiting."; font.pixelSize: theme.size * 0.85; color: theme.subdued }
                    Label { text: "Desktop workspaces" }
                    SearchField {
                        id: workspaces
                        objectName: "workspacesField"
                        Layout.fillWidth: true
                        enabled: root.backdrop
                        placeholderText: "All workspaces, or 3, 1-5, 1, 3, 5"
                        Accessible.name: "Workspaces that show the constellation on the desktop"
                    }
                }
                ColumnLayout {
                    visible: root.section === 2
                    Layout.fillWidth: true
                    spacing: 10
                    Label { text: "About"; font.bold: true }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "What Constellation reads and shows."; color: theme.subdued; font.pixelSize: theme.size * 0.9 }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: theme.size * 0.85
                        text: "The collector reads Claude Code session records and transcripts and Codex rollout files, read-only, on this machine. It shows tool names, file paths relative to each project, program names and token counts. Prompts, replies, command arguments and tool output are never displayed or stored. Nothing is sent over the network."
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: theme.size * 0.85
                        text: "Waiting status comes from Claude Code's session records. Codex does not record approval prompts in its session files, so Codex agents show working or idle only."
                    }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: theme.size * 0.85; text: "Agent Constellation code: MIT." }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
        Label { visible: root.validationError !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.validationError }
        ActionButton {
            objectName: "applySettings"; Layout.fillWidth: true; text: "Done"
            onClicked: {
                root.validationError = root.service.configure(root.claude, root.codex, claudeDir.text.trim(), codexDir.text.trim(), interval.text.trim(), idle.text.trim(), root.notify, root.backdrop, workspaces.text.trim());
                if (root.validationError === "") root.close();
            }
        }
    }
    Connections {
        target: root.visible ? root.parent.Window.window : null
        function onActiveFocusItemChanged() {
            if (!root.visible) return;
            var item = root.parent.Window.window.activeFocusItem, ancestor = item;
            while (ancestor && ancestor !== body) ancestor = ancestor.parent;
            if (!item || ancestor !== body) return;
            var pos = item.mapToItem(body, 0, 0);
            if (pos.y < scroll.contentY) scroll.contentY = pos.y;
            else if (pos.y + item.height > scroll.contentY + scroll.height) scroll.contentY = Math.min(scroll.contentHeight - scroll.height, pos.y + item.height - scroll.height);
        }
    }
}
