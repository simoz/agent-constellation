pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as C
import QtQuick.Layouts
import "../Model.js" as Model

FocusScope {
    id: root
    objectName: "constellationDashboard"
    required property var service
    property bool active: true
    property bool expanded: false
    property bool surfaceSwitchAvailable: true
    property alias scene: scene
    property alias agentList: agents
    readonly property bool wide: width >= 800
    signal expandRequested()
    signal closeRequested()
    // The focused agent card, otherwise the selected agent.
    function terminalTarget() {
        var card = agents.list.currentItem;
        return card && card.activeFocus ? card.modelData : root.service.selected;
    }
    Theme { id: theme }
    Shortcut {
        sequence: "F1"
        enabled: root.active && !settings.opened
        onActivated: keyboardHelp.visible ? keyboardHelp.close() : keyboardHelp.open()
    }
    KeyboardHelp { id: keyboardHelp; width: Math.min(680, root.width - 24); height: Math.min(580, root.height - 24); x: (root.width - width) / 2; y: (root.height - height) / 2 }
    // Handle only keys that the focused control did not consume. These bindings
    // stay inside this dashboard and never register desktop-wide shortcuts.
    Keys.onPressed: function(event) {
        if (!root.active || settings.visible || keyboardHelp.visible) return;
        var focused = root.Window.window ? root.Window.window.activeFocusItem : null;
        if (focused instanceof TextInput || focused instanceof TextEdit) return;
        if (event.modifiers === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_R) {
            clearSelectionButton.clicked();
        } else if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_R && refreshButton.enabled) refreshButton.clicked();
            else if (event.key === Qt.Key_P) collectionToggle.clicked();
            else if (event.key === Qt.Key_G) motionButton.clicked();
            else if (event.key === Qt.Key_T) root.service.focusAgent(root.terminalTarget());
            else if (event.key === Qt.Key_Z && zoomButton.enabled) zoomButton.clicked();
            else if (event.key === Qt.Key_E && root.surfaceSwitchAvailable) surfaceSwitch.clicked();
            else if (event.key === Qt.Key_Comma) settingsButton.clicked();
            else return;
        } else return;
        event.accepted = true;
    }
    Keys.onEscapePressed: function(event) {
        if (root.service.zooming) root.service.zoomed = false; else closeRequested();
        event.accepted = true;
    }
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            var item = root.Window.window.activeFocusItem;
            var ancestor = item;
            while (ancestor && ancestor !== root) ancestor = ancestor.parent;
            if (!item || ancestor !== root) return;
            Qt.callLater(function() {
                var position = item.mapToItem(scroll.contentItem, 0, 0);
                if (position.y < scroll.contentY) scroll.contentY = Math.max(0, position.y - 12);
                else if (position.y + item.height > scroll.contentY + scroll.height)
                    scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, position.y + item.height - scroll.height + 12));
            });
        }
    }
    Rectangle { anchors.fill: parent; color: theme.background }
    Frame { anchors.fill: parent; anchors.margins: 1; emphasized: true }
    Flickable {
        id: scroll
        objectName: "constellationPage"
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 24
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        C.ScrollBar.vertical: C.ScrollBar {}
        ColumnLayout {
            id: content
            x: 12; y: 12
            width: Math.max(200, scroll.width - 24)
            spacing: 10
            RowLayout {
                id: header
                Layout.fillWidth: true
                Layout.minimumHeight: 36
                spacing: root.wide ? 12 : 4
                Label { text: "CONSTELLATION"; color: theme.accent; font.pixelSize: theme.size * (root.wide ? 1.75 : 1.2); font.letterSpacing: root.wide ? 3 : 1 }
                Label { visible: root.width > 920; text: "AGENT OBSERVATORY"; color: theme.subdued; font.pixelSize: theme.size * 0.75; font.letterSpacing: 1 }
                Item { Layout.fillWidth: true }
                ActionButton {
                    flat: true
                    id: collectionToggle
                    objectName: "collectionToggleButton"
                    text: root.service.paused ? "Ⅱ PAUSED" : root.service.error ? "! ERROR" : "● LIVE"
                    hint: root.service.paused ? "Resume collection" : "Pause collection"
                    onClicked: root.service.paused = !root.service.paused
                }
                ActionButton {
                    flat: true
                    id: refreshButton
                    objectName: "refreshButton"
                    implicitWidth: 30
                    contentItem: Item {
                        opacity: parent.enabled ? 1 : 0.45
                        RefreshIcon { anchors.centerIn: parent; ink: theme.accent }
                    }
                    hint: root.service.paused ? "Refresh once and stay paused" : "Refresh agents"
                    enabled: !root.service.refreshing
                    onClicked: root.service.refresh()
                }
                ActionButton {
                    flat: true
                    objectName: "keyboardHelpButton"
                    implicitWidth: 30
                    hint: "Keyboard guide (F1)"
                    contentItem: Item { KeyboardIcon { anchors.centerIn: parent; ink: theme.accent } }
                    onClicked: keyboardHelp.open()
                }
                ActionButton {
                    flat: true
                    id: settingsButton
                    objectName: "settingsButton"
                    implicitWidth: 30
                    hint: "Sources and collection settings"
                    contentItem: Item { SettingsIcon { anchors.centerIn: parent; ink: theme.accent } }
                    onClicked: settings.open()
                }
                ActionButton {
                    flat: true
                    visible: root.surfaceSwitchAvailable
                    id: surfaceSwitch
                    objectName: "surfaceSwitchButton"
                    implicitWidth: 30
                    hint: root.expanded ? "Collapse into panel" : "Expand into window"
                    contentItem: Item { ExpandIcon { anchors.centerIn: parent; ink: theme.accent } }
                    onClicked: root.expandRequested()
                }
            }
            GridLayout {
                id: hero
                Layout.fillWidth: true
                Layout.preferredHeight: root.wide
                    ? Math.max(380, root.height - Math.max(36, header.implicitHeight) - events.implicitHeight - footer.implicitHeight - 54)
                    : 900
                columns: root.wide ? 2 : 1
                columnSpacing: 10
                rowSpacing: 10
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.wide ? content.width * 0.66 : content.width
                    Layout.preferredHeight: root.wide ? 1 : 440
                    Constellation {
                        id: scene
                        anchors.fill: parent
                        anchors.margins: 1
                        service: root.service
                        active: root.active
                    }
                    Frame { anchors.fill: parent; emphasized: root.service.totals.waiting > 0; accent: root.service.totals.waiting > 0 ? root.service.colors.role("red") : theme.accent }
                    Row {
                        anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
                        spacing: 4
                        ActionButton {
                            id: zoomButton
                            objectName: "zoomButton"
                            text: root.service.zooming ? "⊖" : "⊕"
                            implicitWidth: 28; implicitHeight: 26
                            enabled: root.service.selected !== null
                            hint: root.service.zooming ? "Show all agents (Ctrl+Z, Esc)" : "Zoom into the selected agent (Ctrl+Z)"
                            C.ToolTip.visible: hovered
                            C.ToolTip.text: hint
                            onClicked: root.service.zoomed = !root.service.zooming
                        }
                        ActionButton {
                            id: terminalButton
                            objectName: "terminalButton"
                            text: "↗"; implicitWidth: 28; implicitHeight: 26
                            enabled: root.service.canFocus(root.service.selected)
                            hint: "Go to the selected agent's terminal (Ctrl+T)"
                            C.ToolTip.visible: hovered
                            C.ToolTip.text: hint
                            onClicked: root.service.focusAgent(root.service.selected)
                        }
                        ActionButton {
                            id: clearSelectionButton
                            objectName: "clearSelectionButton"
                            text: "↺"; implicitWidth: 28; implicitHeight: 26
                            enabled: root.service.selection !== ""
                            hint: "Show all agents (Ctrl+Shift+R)"
                            C.ToolTip.visible: hovered
                            C.ToolTip.text: hint
                            onClicked: root.service.selection = ""
                        }
                        ActionButton {
                            id: motionButton
                            objectName: "motionButton"
                            text: root.service.animating ? "Ⅱ" : "▷"
                            implicitWidth: 28; implicitHeight: 26
                            hint: root.service.animating ? "Pause animation (Ctrl+G)" : "Resume animation (Ctrl+G)"
                            C.ToolTip.visible: hovered
                            C.ToolTip.text: hint
                            onClicked: root.service.animating = !root.service.animating
                        }
                    }
                }
                AgentList {
                    id: agents
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.wide ? content.width * 0.34 : content.width
                    Layout.preferredHeight: root.wide ? 1 : 440
                    service: root.service
                }
            }
            EventLog {
                id: events
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                service: root.service
            }
            GridLayout {
                id: footer
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                Label {
                    Layout.fillWidth: true
                    text: root.service.notice ? root.service.notice : (root.service.error || root.service.sourceStatus) + (root.service.snapshot ? " · " + Model.clock(root.service.snapshot.observedAtMs) : "")
                    color: theme.subdued
                    font.pixelSize: theme.size * 0.7
                }
                Label {
                    readonly property var totals: root.service.totals
                    text: "OBSERVED / " + totals.agents + " AGENTS / " + totals.busy + " BUSY / " + totals.waiting + " WAITING"
                    color: totals.waiting ? root.service.colors.role("red") : theme.accent
                    font.pixelSize: theme.size * 0.7
                }
            }
        }
    }
    Settings { id: settings; service: root.service }
}
