import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "ui" as Constellation
import "Model.js" as Model

// The constellation drawn on every screen's desktop: above the Omarchy wallpaper,
// below windows, transparent and click-through. It moves only while an agent is
// busy or waiting, so an idle desktop costs nothing per frame.
Item {
    id: root
    property var service: null
    readonly property bool lively: service !== null && service.totals.busy + service.totals.waiting > 0
    onServiceChanged: if (service) service.setView(root, true)
    Component.onDestruction: if (service) service.removeView(root)
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            // Each screen shows its own active workspace; the backdrop appears only on the chosen ones.
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property int workspace: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
            visible: root.service !== null && root.service.agents.length > 0
                && Model.showsOnWorkspace(root.service.backdropWorkspaces, workspace)
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.namespace: "agent-constellation"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            Constellation.Constellation {
                anchors.fill: parent
                // Clear of the bar and the screen edges.
                anchors.margins: 56
                service: root.service
                backdrop: true
                active: root.lively
                // Slow drift on the desktop: half the panel's frame rate.
                frameInterval: 66
                opacity: 0.9
            }
        }
    }
}
