pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as C
import QtQuick.Layouts

C.Popup {
    id: root
    objectName: "constellationKeyboardHelp"
    modal: true
    focus: true
    padding: 16
    closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutside
    property var previousFocus: null
    Theme { id: theme }
    Component { id: refreshIcon; RefreshIcon { ink: theme.accent } }
    Component { id: expandIcon; ExpandIcon { ink: theme.accent } }
    Component { id: settingsIcon; SettingsIcon { ink: theme.accent } }
    onAboutToShow: {
        previousFocus = root.parent.Window.window.activeFocusItem;
        scroll.contentY = 0;
    }
    onOpened: closeButton.forceActiveFocus()
    onClosed: if (previousFocus) previousFocus.forceActiveFocus()
    background: Rectangle {
        color: theme.background
        Frame { anchors.fill: parent; emphasized: true }
    }
    contentItem: ColumnLayout {
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: "KEYS"; color: theme.accent; font.letterSpacing: 3 }
            ActionButton { id: closeButton; text: "Esc ×"; hint: "Close keyboard guide"; onClicked: root.close() }
        }
        Flickable {
            id: scroll
            objectName: "keyboardHelpScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: contents.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: C.ScrollBar {}
            Column {
                id: contents
                width: parent.width
                spacing: 14
                Repeater {
                    model: [
                        [[], "GENERAL"],
                        [["F1"], "Open or close this guide (outside Settings)"],
                        [["Tab", "Shift+Tab"], "Move to the next / previous control"],
                        [["Enter", "Space"], "Activate the focused button or agent card"],
                        [["Esc"], "Close Settings or this guide; otherwise close Constellation"],
                        [[], "ACTIONS · SHORTCUTS OR FOCUS BUTTON + ENTER / SPACE"],
                        [["LIVE", "PAUSED", "Ctrl+P"], "Pause or resume collection"],
                        [[refreshIcon, "Ctrl+R"], "Collect once; stay paused if already paused"],
                        [[expandIcon, "Ctrl+E"], "Switch between compact panel and expanded window"],
                        [[settingsIcon, "Ctrl+,"], "Open Sources, Collection and About settings"],
                        [["▷", "Ⅱ", "Ctrl+G"], "Pause or resume the animation"],
                        [["↺", "Ctrl+Shift+R"], "Show all agents again"],
                        [[], "CONSTELLATION · WHEN FOCUSED"],
                        [["←", "↑", "→", "↓"], "Select the previous / next agent"],
                        [["Home"], "Show all agents again"],
                        [[], "AGENTS AND EVENTS"],
                        [["↑", "↓"], "Move between agent cards; scroll the focused event list"],
                        [["Enter", "Space"], "Highlight an agent; choose it again to show all agents"],
                        [["PgUp", "PgDn"], "Scroll the focused event list by a page"],
                        [[], "THIS GUIDE"],
                        [["↑", "↓", "PgUp", "PgDn"], "Scroll the guide"]
                    ]
                    Column {
                        id: entry
                        required property var modelData
                        width: contents.width
                        spacing: 4
                        Label {
                            width: parent.width
                            visible: entry.modelData[0].length === 0
                            text: entry.modelData[1]
                            color: theme.accent
                            wrapMode: Text.Wrap
                            font.bold: true
                        }
                        Row {
                            visible: entry.modelData[0].length > 0
                            width: parent.width
                            spacing: 12
                            Flow {
                                id: keyCaps
                                width: contents.width >= 480 ? 180 : 110
                                spacing: 4
                                Repeater {
                                    model: entry.modelData[0]
                                    Rectangle {
                                        required property var modelData
                                        width: Math.max(24, keyLabel.implicitWidth + 12)
                                        height: Math.max(24, keyLabel.implicitHeight + 8)
                                        color: "transparent"
                                        border.color: theme.subdued
                                        Loader {
                                            anchors.centerIn: parent
                                            width: 18; height: 18
                                            sourceComponent: typeof parent.modelData === "string" ? null : parent.modelData
                                        }
                                        Label {
                                            id: keyLabel
                                            anchors.centerIn: parent
                                            text: typeof parent.modelData === "string" ? parent.modelData : ""
                                            font.pixelSize: theme.size * 0.85
                                        }
                                    }
                                }
                            }
                            Label {
                                width: parent.width - keyCaps.width - parent.spacing
                                text: entry.modelData[1]
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: theme.border }
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: theme.subdued
                    text: "Action shortcuts work only in Constellation, with Settings and this guide closed. In text fields, normal editing keys take priority.\nClick an agent core or card to highlight it and filter the event list; click it again, or press ↺, to show all agents.\nA red core and red scene edges mean an agent is waiting for your input; the bar icon turns red too.\nIn Settings, Done saves sources, paths and intervals. Esc closes without saving.\nThe bar icon opens the compact panel with a left-click and the expanded window with a right-click. Switching views preserves the selection."
                }
            }
        }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_F1) { root.close(); event.accepted = true; return; }
            var delta = 0;
            if (event.key === Qt.Key_Down) delta = 32;
            else if (event.key === Qt.Key_Up) delta = -32;
            else if (event.key === Qt.Key_PageDown) delta = scroll.height * 0.8;
            else if (event.key === Qt.Key_PageUp) delta = -scroll.height * 0.8;
            else return;
            scroll.contentY = Math.max(0, Math.min(Math.max(0, scroll.contentHeight - scroll.height), scroll.contentY + delta));
            event.accepted = true;
        }
    }
}
