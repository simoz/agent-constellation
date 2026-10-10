import QtQuick
import qs.Ui as UI
import "ui" as Constellation

UI.BarWidget {
    id: root
    moduleName: "io.github.simoz.agent-constellation"
    readonly property var host: bar
    readonly property var service: host && host.shell ? host.shell.serviceFor(moduleName) : null
    readonly property bool opened: panel.opened
    readonly property bool popoutSwitchClosing: panel.popoutSwitchClosing
    readonly property var agents: service ? service.agents : []
    readonly property int waiting: service ? service.totals.waiting : 0
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    // Fill the widget slot instead of the host's default 55% active marker.
    readonly property real openPanelIndicatorWidth: width
    readonly property real openPanelIndicatorHeight: height
    property var registeredService: null
    function syncView() {
        if (registeredService && registeredService !== service) registeredService.removeView(root);
        registeredService = service;
        if (service) { service.loadConfiguration(settings); service.setView(root, panel.opened); }
    }
    onServiceChanged: syncView()
    onOpenedChanged: syncView()
    onSettingsChanged: if (service) service.loadConfiguration(settings)
    Component.onCompleted: syncView()
    Component.onDestruction: if (registeredService) registeredService.removeView(root)
    function open() { panel.open(); }
    function close() { panel.close(); }
    function toggle() { panel.toggle(); }
    function closeForPopoutSwitch() { panel.closeForPopoutSwitch(); }
    function tooltip() {
        if (!service) return "Agent Constellation · unavailable";
        var parts = ["Agent Constellation · " + service.status];
        if (waiting) parts.push(agents.filter(function(a) { return a.status === "waiting"; })
            .map(function(a) { return a.project + " waiting"; }).join(", "));
        else parts.push(agents.length + (agents.length === 1 ? " agent" : " agents"));
        return parts.join(" · ") + " · Right-click to expand";
    }

    UI.WidgetButton {
        id: button
        objectName: "constellationBarButton"
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        dimmed: !root.service || !root.service.demanded
        readonly property color alert: root.service ? root.service.palette.role("red") : foreground
        readonly property bool compact: root.vertical || root.agents.length === 0
        fixedWidth: compact ? barSize : barContents.implicitWidth + scaledHorizontalMargin * 2
        fixedHeight: root.vertical && root.agents.length ? barContents.implicitHeight + scaledVerticalPadding * 2 : barSize
        tooltipText: root.tooltip()
        Grid {
            id: barContents
            anchors.centerIn: parent
            columns: root.vertical ? 1 : 3
            spacing: 5
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            Constellation.ConstellationIcon {
                objectName: "constellationBarIcon"
                ink: root.waiting ? button.alert : button.foreground
                SequentialAnimation on opacity {
                    running: root.waiting > 0 && root.service && root.service.moving
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) parent.opacity = 1
                    NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                }
            }
            Grid {
                visible: !button.dimmed && root.agents.length > 0
                columns: root.vertical ? 1 : 5
                spacing: 3
                Repeater {
                    model: root.agents.slice(0, 5)
                    Rectangle {
                        required property var modelData
                        width: 6; height: 6; radius: 3
                        color: root.service.agentColor(modelData)
                        opacity: modelData.status === "idle" ? 0.45 : 1
                    }
                }
            }
            Text {
                objectName: "constellationBarCount"
                visible: !button.dimmed && root.agents.length > 0 && !root.vertical
                text: root.waiting ? root.waiting + "!" : String(root.agents.length)
                color: root.waiting ? button.alert : button.foreground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: button.activeFocus ? button.foreground : "transparent"
        }
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.tooltip()
        Accessible.onPressAction: root.toggle()
        Keys.onSpacePressed: root.toggle()
        Keys.onReturnPressed: root.toggle()
        onPressed: function(button) {
            if (button === Qt.LeftButton) root.toggle();
            else if (button === Qt.RightButton) panel.openExpanded();
        }
    }
    Panel {
        id: panel
        bar: root.bar
        service: root.service
        anchorItem: button
        hostWidget: root
    }
}
