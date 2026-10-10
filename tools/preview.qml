import QtQuick
import QtQuick.Window
import QtCore as Core
import Quickshell
import qs.Commons
import ".." as Plugin
import "../ui" as Constellation

// Isolated preview: real theme components, simulated host, no desktop changes.
ShellRoot {
    id: root
    property var sampleIntervals: []
    property double previousTick: 0
    property int frames: 0
    property double startedAt: 0
    Core.Settings {
        id: preferences
        location: "file://" + (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/agent-constellation/preview.ini"
    }
    Plugin.Service {
        id: service
        standalone: true
        reducedMotion: Quickshell.env("CONSTELLATION_STILL") === "1"
        saveConfiguration: function(config) {
            preferences.setValue("collection", JSON.stringify(config));
            preferences.sync();
            return true;
        }
        Component.onCompleted: {
            var saved = preferences.value("collection", "");
            var config = {};
            if (saved) {
                try { config = JSON.parse(saved); }
                catch (e) { console.warn("Unable to read saved Agent Constellation preview settings"); }
            }
            if (Quickshell.env("CONSTELLATION_CLAUDE_DIR")) config.claudeDir = Quickshell.env("CONSTELLATION_CLAUDE_DIR");
            if (Quickshell.env("CONSTELLATION_CODEX_DIR")) config.codexDir = Quickshell.env("CONSTELLATION_CODEX_DIR");
            if (Quickshell.env("CONSTELLATION_BACKDROP") === "1") config.backdrop = true;
            loadConfiguration(config);
        }
    }
    Window {
        id: window
        visible: true
        onVisibleChanged: {
            if (visible) service.setView(window, true); else service.removeView(window);
        }
        Component.onCompleted: service.setView(window, true)
        width: Number(Quickshell.env("CONSTELLATION_WIDTH")) || 1440
        height: Number(Quickshell.env("CONSTELLATION_HEIGHT")) || 920
        title: "Agent Constellation — live preview"
        // Rendered frames, for the benchmark's frames per second.
        onFrameSwapped: root.frames++
        Constellation.Dashboard {
            id: dashboard
            anchors.fill: parent
            service: service
            expanded: true
            surfaceSwitchAvailable: false
            onCloseRequested: Qt.quit()
        }
    }
    Timer {
        interval: 1000
        running: true
        onTriggered: {
            // Preserve the installed theme unless a visual-test palette is requested.
            // Agent colors still come from colors.toml under XDG_STATE_HOME (see demo/run).
            var palette = Quickshell.env("CONSTELLATION_THEME");
            if (palette === "light" || palette === "dark") {
                var light = palette === "light";
                Color.shellValues = {};
                Color.background = light ? "#faf4ed" : "#1a1b26";
                Color.foreground = light ? "#575279" : "#a9b1d6";
                Color.accent = light ? "#286983" : "#7aa2f7";
            }
            if (Quickshell.env("CONSTELLATION_ZOOM") === "1" && service.agents.length)
                dashboard.scene.zoomTo(service.agents[0].id);
            if (Quickshell.env("CONSTELLATION_BENCHMARK")) {
                previousTick = Date.now();
                startedAt = previousTick;
                frames = 0;
                benchmark.start();
            } else capture.start();
        }
    }
    // Measures the animated scene: timer intervals and canvas repaints.
    Timer {
        id: benchmark
        interval: 33
        repeat: true
        onTriggered: {
            var now = Date.now();
            root.sampleIntervals.push(now - root.previousTick);
            root.previousTick = now;
            if (root.sampleIntervals.length < 120) return;
            stop();
            var sorted = root.sampleIntervals.slice().sort(function(a, b) { return a - b; });
            console.log("CONSTELLATION_PROFILE", JSON.stringify({
                ticks: sorted.length,
                meanIntervalMs: root.sampleIntervals.reduce(function(a, b) { return a + b; }, 0) / sorted.length,
                p95IntervalMs: sorted[Math.floor(sorted.length * 0.95)],
                canvasPaints: dashboard.scene.paintCount,
                framesPerSecond: Math.round(root.frames * 10000 / (now - root.startedAt)) / 10,
                zoomed: service.zooming,
                agents: service.agents.length
            }));
            Qt.quit();
        }
    }
    Timer {
        id: capture
        interval: Number(Quickshell.env("CONSTELLATION_CAPTURE_DELAY")) || 1500
        onTriggered: {
            var output = Quickshell.env("CONSTELLATION_CAPTURE");
            if (!output) return;
            dashboard.grabToImage(function(result) {
                if (!result.saveToFile(output)) console.error("Unable to save preview");
                console.log("CONSTELLATION_CAPTURE_COMPLETE", output);
                Qt.quit();
            });
        }
    }
}
