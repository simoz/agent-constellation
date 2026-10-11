# Performance plan

Working notes for the `perf/render-and-lists` branch, from a code review in
October 2026. Delete this file once the plan is done or dropped.

## Where the cost is

- **Collector (Python): already cheap.** One snapshot of the three demo agents,
  JSON encoding included, takes about 0.6 ms (measured on macOS with `/proc`
  stubbed), so under 0.1% of a core at 1 Hz. Reading the last 1 MiB of a new
  transcript takes 2–6 ms, once per transcript.
- **QML: almost all of it.** QML figures below are estimates from counting
  bindings and objects, not measurements. Verify each change on Omarchy.

## How to measure

Before and after each change:

1. Run the preview with `CONSTELLATION_BENCHMARK=1` (frames per second, timer
   intervals, `canvasPaints` over 120 ticks).
2. Check CPU with `top -p` on the preview, and with `CONSTELLATION_STILL=1`
   (animation off) for comparison.
3. Run `tests/run`.

Make one commit per item.

## Plan

### 1. Repaint the static canvas only when its content changes

`ui/Constellation.qml` puts `snapshot.sequence` in `paintKey`, and the collector
increments it on every reply (`tools/collect.py`, `self.sequence += 1`). So the
full-window canvas is rasterized and uploaded every second even when nothing
visible changed. That means about 30 MB per screen per second on a 4K backdrop,
and probably a hitch in the animation once a second. An "idle" backdrop still
pays this cost.

- Replace the sequence with a key built from what the canvas draws:
  - per agent: id, status, model, `waitingFor`, title, activity text, subagent
    count, color, and the core position rounded to whole pixels;
  - per file: path, position rounded to whole pixels, heat in 0.05 steps, added
    and removed lines.
- Keep the existing selection, zoom, size and theme parts of the key.
- Heat decays slowly once the top score is below 1, so whole-pixel positions
  repaint only every few seconds while it decays.

Rejected: moving the vignette, grid and stars to a second canvas. Halos and
glows use the `lighter` composite mode in dark themes. On a separate transparent
canvas they would be blended source-over instead of added to the background, so
hot files would look slightly darker. The content key alone makes repaints rare.

### 2. Stop rebuilding lists on every snapshot

`ui/AgentList.qml`, `ui/EventLog.qml` and the dots in `BarWidget.qml` use JS
arrays as `model`. When the content changes, `ListView.setModel` clears every
delegate, creates them again, resets the position to the top and resets
`currentIndex` to 0. With working agents this happens about once a second.

Visible effects:
- the event log cannot stay scrolled;
- agent cards lose keyboard focus;
- tooltips close.

Check first: scroll the event log while an agent works.

Fix:
- Use a row model that appends and removes rows only at the end (a `ListModel`
  kept at the array's length).
- Delegates read `service.agents[index]` or `events[index]`, with an inert
  fallback object for rows being removed.
- A plain integer `model` is not enough: changing the count also resets the
  view.
- `Sparkline` should repaint only when `values.join()` changes, not on every new
  array.

### 3. Make particles cheaper per frame

Particles are the main per-frame cost, estimated at about 85% of the bindings
evaluated per tick. Each trail dot in `ui/Particle.qml` has a `PathInterpolator`,
a `Path` and a `PathQuad`, plus about 5 bindings. With 12 particles × 6 dots,
that is about 400 binding evaluations per agent per tick, or about 40k per
second for three agents. This is consistent with the measured 11% of a core.

In order of effort:
- Compute the quadratic Bézier directly in `x`/`y` (`Particle` already has
  `controlX`/`controlY`) and drop `PathInterpolator`.
- Use 3–4 dots per trail instead of 6, spaced further apart.
- Keep a fixed pool of 12 particles per agent instead of changing the Repeater
  model in `ui/AgentMotion.qml`. Today each activity change creates or destroys
  25 objects per particle. Hidden particles must freeze `time` so they do not
  keep evaluating.
- Add a global particle budget across agents. The worst case today, 24 agents,
  is about 7000 objects.

Expected: about half the per-frame cost. Measure it.

### 4. Bar icon blink without vsync animation

While an agent waits, the `SequentialAnimation on opacity` in `BarWidget.qml`
re-renders the bar at the display refresh rate (60–144 fps), on every monitor,
for the whole wait. Replace it with a `Timer`-driven blink (about 2 frames per
second), or pulse only for the first ~10 s and then stay red.

## Later, medium priority

- **Backdrop:** run at 15 fps instead of 30. Add an option for the main screen
  only (each screen runs a full scene today). Note that the backdrop registers
  as an open view, which keeps polling at 1 s.
- **Expanded window on another workspace:** the scene clock keeps running and
  evaluating bindings. Pause it when `frameSwapped` stops arriving, and resume
  on the next frame.
- **`Panel.qml` loads a Dashboard per bar and monitor at startup** and keeps it
  reacting to snapshots. Load it on first open instead.
- **Collector cleanups (small gains):**
  - Cache each agent's transcript path. Today `projects/*/<id>.jsonl` is globbed
    every tick: 136 µs with 39 projects, against 1.6 µs to stat a known path.
  - Skip lines without `"assistant"` before `json.loads`. This cut parsing of the
    five largest local transcripts from 18 to 8 ms.
- **Possible correctness bug:** subagent transcripts are sliced `[-32:]` by name,
  not by recency. If agent ids are random, new subagents can be missed in
  sessions with more than 32 of them. Sort by mtime.

## Keep

The single 30 fps scene clock is the right design. `Animator`, `NumberAnimation`
and `QtQuick.Particles` would run at vsync and break the cap. A `ShaderEffect`
where only `time` changes per frame would be the last step, but it means
shipping precompiled `.qsb` shaders. Do not start it before items 1–4.
