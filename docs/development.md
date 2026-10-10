# Development

The runtime is the QML plugin plus `tools/collect.py`, which needs only Python
3.11+ (already part of Omarchy). Node and the QtTest runner are development
tools.

## Run the live interface

```bash
./run-ui.sh
```

The launcher assembles an isolated preview with the installed Omarchy
`Commons`/`Ui` modules and a simulated host. It reads your real Claude Code and
Codex sessions, read-only, and does not change the bar. Preview settings live
in `${XDG_CONFIG_HOME:-$HOME/.config}/agent-constellation/preview.ini`.
`CONSTELLATION_CLAUDE_DIR` and `CONSTELLATION_CODEX_DIR` select other session
directories.

To print one snapshot from the terminal:

```bash
python3 -B tools/collect.py --once
```

## Install the plugin

```bash
omarchy plugin add https://github.com/simoz/agent-constellation.git --enable
```

To install from a working copy, copy into an **unused**
`~/.config/omarchy/plugins/io.github.simoz.agent-constellation/` directory
`manifest.json`, `LICENSE`, the root `*.qml` and `*.js` files, `ui/` and
`tools/collect.py`, then:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.simoz.agent-constellation
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.simoz.agent-constellation
```

The shell's automatic reload can keep previous QML in memory; restart the
Omarchy shell after replacing files.

## Automated checks

```bash
tests/run
omarchy plugin validate .
```

`tests/run` runs the Node tests (`Protocol.js`, `Model.js`), the collector unit
tests on synthetic sessions, QtTest with a minimal `qs.Commons` facade and
`git diff --check`. QtTest checks keyboard behavior with a stub service;
offscreen rendering is not a desktop integration test.

## Visual checks and screenshots

`demo/run` renders stills offscreen from the fictional sessions written by
`demo/fixtures.py`, with temporary XDG directories and a fixture theme. It never
reads real sessions or changes the bar. Regenerate the README screenshots after
visible changes:

```bash
demo/run /tmp/constellation-shots
cp /tmp/constellation-shots/*.png docs/screenshots/
```

For a single capture of your real sessions, inspect it before sharing:

```bash
preview=$(python3 -B tools/prepare_preview.py)
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic \
  CONSTELLATION_THEME=light CONSTELLATION_CAPTURE=/tmp/constellation.png qs -p "$preview"
rm -rf -- "$preview"
```

Controls: `CONSTELLATION_THEME` (`light`/`dark`, otherwise the installed
theme), `CONSTELLATION_WIDTH`, `CONSTELLATION_HEIGHT`,
`CONSTELLATION_CAPTURE_DELAY` and `CONSTELLATION_BENCHMARK=1`, which reports
timer intervals and static-canvas repaints over 120 ticks. After changes to the
moving parts, compare the preview's CPU use with `CONSTELLATION_STILL=1`
(animation off), for example with `top -p`.
