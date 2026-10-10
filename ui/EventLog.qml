pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import "../Model.js" as Model

// Recent tool calls across agents, newest first. With an agent selected, only its events.
Item {
    id: root
    objectName: "eventLog"
    required property var service
    readonly property var events: service.selection
        ? service.events.filter(function(e) { return e.agent === service.selection; }) : service.events
    readonly property real rowHeight: Math.max(22, theme.size * 1.7)
    Theme { id: theme }
    implicitHeight: 74 + rowHeight * 6
    Frame { anchors.fill: parent }
    Label {
        x: 14; y: 12
        width: parent.width - 28
        text: "EVENTS"
        color: theme.accent
        font.pixelSize: theme.size * 1.12
        font.letterSpacing: 1.5
    }
    Label {
        x: 14; y: 37
        width: parent.width - 28
        text: (root.service.selected ? Model.agentTitle(root.service.selected).toUpperCase() : "ALL AGENTS") + "  /  " + root.events.length + " RECENT TOOL CALLS"
        font.pixelSize: theme.size * 0.76
        color: theme.subdued
    }
    Rectangle { x: 14; y: 61; width: parent.width - 28; height: 1; color: theme.border }
    ListView {
        id: list
        objectName: "eventList"
        x: 14; y: 66
        width: parent.width - 24
        height: root.height - 74
        model: root.events
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: count > 0
        Accessible.role: Accessible.List
        Accessible.name: "Recent tool calls"
        C.ScrollBar.vertical: C.ScrollBar {}
        Keys.onPressed: function(event) {
            var delta = event.key === Qt.Key_Down ? root.rowHeight : event.key === Qt.Key_Up ? -root.rowHeight
                : event.key === Qt.Key_PageDown ? height * 0.8 : event.key === Qt.Key_PageUp ? -height * 0.8 : 0;
            if (!delta || event.modifiers !== Qt.NoModifier) return;
            contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), contentY + delta));
            event.accepted = true;
        }
        delegate: Row {
            id: line
            required property var modelData
            readonly property var agent: root.service.agentById(modelData.agent)
            width: list.width - 10
            height: root.rowHeight
            spacing: 10
            Label { anchors.verticalCenter: parent.verticalCenter; text: Model.clock(line.modelData.atMs); color: theme.subdued; font.pixelSize: theme.size * 0.85 }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, line.width * 0.35)
                text: "◆ " + (line.agent ? line.agent.project : "") + (line.modelData.subagent ? " ▸ " + line.modelData.subagent : "")
                color: line.agent ? root.service.agentColor(line.agent) : theme.text
                font.pixelSize: theme.size * 0.85
            }
            Label { anchors.verticalCenter: parent.verticalCenter; text: line.modelData.tool; font.bold: true; font.pixelSize: theme.size * 0.85 }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, line.width - x)
                text: line.modelData.target
                color: theme.subdued
                font.pixelSize: theme.size * 0.85
            }
        }
        Label {
            anchors.fill: parent
            visible: list.count === 0
            text: "No tool calls yet"
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            color: theme.subdued
        }
    }
}
