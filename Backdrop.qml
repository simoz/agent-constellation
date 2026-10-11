import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "ui" as Constellation
import "Model.js" as Model

// The constellation drawn on every screen's desktop: above the Omarchy wallpaper,
// below windows and click-through. It moves only while an agent is busy or
// waiting, so an idle desktop costs nothing per frame. Full screen, its inks
// follow the wallpaper's brightness behind each agent; as a widget it sits on a
// card in the theme's colors, in its own layer namespace so a Hyprland rule can
// blur the wallpaper behind the card alone.
Item {
    id: root
    property var service: null
    readonly property bool lively: service !== null && service.totals.busy + service.totals.waiting > 0
    readonly property bool widget: service !== null && service.backdropStyle === "widget"
    readonly property var size: Model.widgetSizes[service ? service.widgetSize : "medium"]
    readonly property string corner: service ? service.widgetCorner : "top-right"
    Constellation.Theme { id: theme }
    onServiceChanged: if (service) service.setView(root, true)
    Component.onDestruction: if (service) service.removeView(root)
    // The Omarchy wallpaper: a symlink that changes without any event we can
    // watch, so it is resolved again every few seconds while the backdrop shows.
    readonly property string link: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/current/background"
    property string wallpaper: ""
    Process {
        id: resolve
        command: ["readlink", "-f", root.link]
        stdout: StdioCollector { onStreamFinished: root.wallpaper = text.trim() }
    }
    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root.service !== null && root.service.agents.length > 0 && !root.widget
        onTriggered: if (!resolve.running) resolve.running = true
    }
    Variants {
        model: root.widget ? [] : Quickshell.screens
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
            Constellation.WallpaperProbe {
                id: probe
                source: root.wallpaper
                screenWidth: parent.width
                screenHeight: parent.height
                area: Qt.rect(scene.x, scene.y, scene.width, scene.height)
                // A theme switch can replace the image behind an unchanged path.
                Connections {
                    target: root.service ? root.service.colors : null
                    function onThemeKeyChanged() { probe.reload(); }
                }
            }
            Constellation.Constellation {
                id: scene
                anchors.fill: parent
                // Clear of the bar and the screen edges.
                anchors.margins: 56
                service: root.service
                backdrop: true
                textScale: 1.15
                surface: probe.values.length ? probe : null
                active: root.lively
                // Slow drift on the desktop: half the panel's frame rate.
                frameInterval: 66
                opacity: 0.9
            }
        }
    }
    Variants {
        model: root.widget ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property int workspace: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
            visible: root.service !== null && root.service.agents.length > 0
                && Model.showsOnWorkspace(root.service.backdropWorkspaces, workspace)
            color: "transparent"
            implicitWidth: root.size.width
            implicitHeight: root.size.height
            anchors {
                top: root.corner.indexOf("top") === 0
                bottom: root.corner.indexOf("bottom") === 0
                left: root.corner.indexOf("left") > 0
                right: root.corner.indexOf("right") > 0
            }
            // Respects the bar's exclusive zone, like a window would.
            margins { top: 16; bottom: 16; left: 16; right: 16 }
            mask: Region {}
            WlrLayershell.namespace: "agent-constellation-widget"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            Rectangle {
                anchors.fill: parent
                radius: 18
                color: theme.fade(theme.background, 0.8)
                border.color: theme.fade(theme.text, 0.1)
                border.width: 1
            }
            Constellation.Constellation {
                anchors.fill: parent
                anchors.margins: 14
                service: root.service
                backdrop: true
                card: true
                fileLabels: root.service !== null && root.service.widgetSize === "large"
                waves: root.service !== null && root.service.widgetSize !== "small"
                active: root.lively
                frameInterval: 66
            }
        }
    }
}
