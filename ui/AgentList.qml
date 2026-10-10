pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import "../Model.js" as Model

// One card per agent. Choosing a card highlights the agent in the scene; choosing
// it again clears the selection, as with Outbound's facet filters.
Item {
    id: root
    objectName: "agentList"
    required property var service
    readonly property real rowHeight: Math.max(104, theme.size * 8)
    property alias list: list
    Theme { id: theme }
    Frame { anchors.fill: parent; emphasized: root.service.selection !== "" }
    Label {
        x: 14; y: 12
        width: parent.width - 28
        text: "AGENTS"
        color: theme.accent
        font.pixelSize: theme.size * 1.12
        font.letterSpacing: 1.5
    }
    Label {
        x: 14; y: 37
        width: parent.width - 28
        readonly property var totals: root.service.totals
        text: totals.agents + " AGENTS  /  " + totals.subagents + " SUBAGENTS  /  " + Model.tokens(totals.tokensPerMinute) + " TOK/MIN"
        font.pixelSize: theme.size * 0.76
        color: theme.subdued
    }
    Rectangle { x: 14; y: 61; width: parent.width - 28; height: 1; color: theme.border }
    ListView {
        id: list
        x: 12; y: 66
        width: parent.width - 20
        height: Math.max(root.rowHeight, root.height - 74)
        model: root.service.agents
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        C.ScrollBar.vertical: C.ScrollBar {}
        delegate: C.ItemDelegate {
            id: card
            required property var modelData
            required property int index
            readonly property bool selected: root.service.selection === modelData.id
            readonly property color ink: root.service.agentColor(modelData)
            width: list.width - 8
            // A project name on two lines makes the card taller instead of hiding it.
            height: root.rowHeight + name.implicitHeight - name.implicitHeight / Math.max(1, name.lineCount)
            C.ToolTip.visible: hovered && name.truncated
            C.ToolTip.text: modelData.project
            focusPolicy: Qt.StrongFocus
            Accessible.name: Model.agentTitle(modelData) + ", " + Model.statusLabel(modelData.status) + ", " + Model.activityText(modelData.activity)
            onClicked: root.service.select(modelData.id)
            onDoubleClicked: root.service.focusAgent(modelData)
            onActiveFocusChanged: if (activeFocus) {
                list.currentIndex = index;
                list.positionViewAtIndex(index, ListView.Contain);
            }
            Keys.onPressed: function(event) {
                if (event.modifiers !== Qt.NoModifier || (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down)) return;
                var next = Math.max(0, Math.min(list.count - 1, index + (event.key === Qt.Key_Down ? 1 : -1)));
                list.currentIndex = next;
                list.positionViewAtIndex(next, ListView.Contain);
                list.forceLayout();
                list.currentItem.forceActiveFocus();
                event.accepted = true;
            }
            background: Rectangle {
                color: card.selected || card.hovered ? theme.fade(card.ink, 0.09) : theme.wash
                border.color: card.activeFocus ? theme.text : card.selected ? card.ink : theme.border
                border.width: card.activeFocus || card.selected ? 2 : 1
                Rectangle { width: 3; height: parent.height; color: card.ink }
            }
            contentItem: Column {
                leftPadding: 6
                spacing: 3
                Item {
                    width: parent.width - 6
                    height: name.implicitHeight
                    Label {
                        id: name
                        width: parent.width - pill.width - 8
                        text: card.modelData.project
                        font.bold: true
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 2
                    }
                    Rectangle {
                        id: pill
                        anchors.right: parent.right
                        width: pillLabel.implicitWidth + 14
                        height: pillLabel.implicitHeight + 2
                        radius: height / 2
                        color: card.ink
                        Label {
                            id: pillLabel
                            anchors.centerIn: parent
                            text: Model.statusLabel(card.modelData.status)
                            color: theme.background
                            font.bold: true
                            font.pixelSize: theme.size * 0.72
                            font.letterSpacing: 1
                        }
                    }
                }
                Label {
                    width: parent.width - 6
                    text: card.modelData.status === "waiting" ? "⚠ " + (card.modelData.waitingFor || "input needed") : Model.activityText(card.modelData.activity)
                    color: card.modelData.status === "waiting" ? card.ink : theme.text
                    font.pixelSize: theme.size * 0.9
                }
                Label {
                    width: parent.width - 6
                    text: [card.modelData.kind, card.modelData.model, Model.tokens(card.modelData.outputTokens) + " tok", card.modelData.toolCalls + " calls"]
                        .concat(card.modelData.subagents.length ? [card.modelData.subagents.length + " sub"] : []).filter(function(t) { return t; }).join(" · ")
                    color: theme.subdued
                    font.pixelSize: theme.size * 0.8
                }
                Sparkline {
                    width: parent.width - 6
                    height: Math.max(18, card.availableHeight - y)
                    values: card.modelData.activityBuckets
                    ink: card.ink
                }
            }
        }
        Label {
            anchors.fill: parent
            visible: list.count === 0
            text: "No active agents"
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            color: theme.subdued
        }
    }
}
