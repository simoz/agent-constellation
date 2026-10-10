pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import qs.Ui as UI
import "ui" as Constellation

UI.Panel {
    id: root
    moduleName: "io.github.simoz.agent-constellation"
    manageIpc: false
    property var service: null
    property Item anchorItem: null
    property var hostWidget: null
    property bool expanded: false
    readonly property Item scene: dashboard.item as Item

    function close() {
        controller.hide();
        expanded = false;
    }
    function openExpanded() {
        expanded = true;
        open();
        Qt.callLater(function() {
            expandedWindow.requestActivate();
            if (root.scene) root.scene.forceActiveFocus();
        });
    }
    function changeSurface() {
        expanded = !expanded;
        Qt.callLater(function() { if (root.scene) root.scene.forceActiveFocus(); });
    }

    UI.KeyboardPanel {
        id: popup
        bar: root.bar
        owner: root.hostWidget || root
        anchorItem: root.anchorItem
        open: root.opened && !root.expanded
        focusTarget: root.scene
        contentWidth: fittedContentWidth(1060)
        // Ask for more than any common screen: the host clamps the card below the bar.
        contentHeight: fittedContentHeight(1400)
        Item {
            id: compactHost
            anchors.fill: parent
            Constellation.Label {
                anchors.fill: parent
                visible: root.service === null
                wrapMode: Text.Wrap
                text: "Agent Constellation service unavailable. It requires the built-in Omarchy bar."
            }
        }
    }
    Window {
        id: expandedWindow
        title: "Agent Constellation"
        width: 1440
        height: 920
        minimumWidth: 380
        minimumHeight: 360
        visible: root.opened && root.expanded
        onClosing: function(event) { event.accepted = false; root.close(); }
    }
    // A single loaded scene is reparented; selection and focus are not recreated
    // when switching surfaces or closing the panel.
    Loader {
        id: dashboard
        parent: root.expanded ? expandedWindow.contentItem : compactHost
        anchors.fill: parent
        active: root.service !== null
        sourceComponent: Constellation.Dashboard {
            service: root.service
            active: root.opened
            expanded: root.expanded
            onCloseRequested: root.close()
            onExpandRequested: root.changeSurface()
        }
    }
}
