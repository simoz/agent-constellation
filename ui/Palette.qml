import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Named theme colors for agents. The host Color singleton exposes only
// foreground, background, accent, urgent and muted, so the full palette is read
// from the active theme's colors.toml. Theme switches reach Color through shell
// IPC without a file event; any change of its colors triggers a reload here.
Item {
    id: root
    readonly property string path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/current/theme/colors.toml"
    property var values: ({})
    readonly property bool light: values.mode ? values.mode === "light" : luminance(Color.background) > 0.5
    readonly property string themeKey: String(Color.background) + String(Color.foreground) + String(Color.accent)
    onThemeKeyChanged: file.reload()

    function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b; }
    function mix(a, b, k) { return Qt.rgba(a.r * (1 - k) + b.r * k, a.g * (1 - k) + b.g * k, a.b * (1 - k) + b.b * k, 1); }
    function fade(c, opacity) { return Qt.rgba(c.r, c.g, c.b, c.a * opacity); }
    function contrast(a, b) { return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05); }
    // A theme color on a surface of luminance l, as the desktop backdrop over a
    // wallpaper: the color itself when it stands out, otherwise its darker or
    // lighter shade. A negative l means the theme's own background.
    function standOut(c, l) {
        if (l < 0 || contrast(luminance(c), l) >= 3) return c;
        var dark = mix(c, Qt.rgba(0, 0, 0, 1), 0.5), bright = mix(c, Qt.rgba(1, 1, 1, 1), 0.5);
        return contrast(luminance(dark), l) > contrast(luminance(bright), l) ? dark : bright;
    }
    // Older themes ship only color0–color15: map them to the same role names.
    readonly property var ansi: ({red: "color1", green: "color2", yellow: "color3", blue: "color4", magenta: "color5", cyan: "color6"})
    function role(name) {
        var value = values[name] || values[ansi[name]];
        // Qt.lighter with factor 1 turns the theme's hex string into a color value.
        if (value) return Qt.lighter(value, 1);
        if (name === "orange") return mix(role("red"), role("yellow"), 0.55);
        return name === "red" ? Color.urgent : Color.accent;
    }
    function parse(raw) {
        var result = {};
        String(raw || "").split("\n").forEach(function(line) {
            var match = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6}|light|dark)\b/);
            if (match) result[match[1]] = match[2];
        });
        return result;
    }
    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onLoaded: root.values = root.parse(text())
        onFileChanged: reload()
        onLoadFailed: root.values = {}
    }
}
