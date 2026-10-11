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

## Done

Items 1–4 of the original plan, one commit each. Preview CPU (the whole `qs`
process, 30 s on the `demo/scenario.py` sessions with three agents, on the
aarch64 VM), moving / with `CONSTELLATION_STILL=1`:

| Step | Moving | Still |
| --- | --- | --- |
| Before | 25.5% | 8.1% |
| 1. Static canvas repaints only when its content key changes | 20.5% | 4.3% |
| 2. List delegates kept across snapshots (`ui/Rows.qml`) | 19.6% | 4.8% |
| 3. Particles: direct Bézier, 4-dot trails, fixed pool, budget of 48 | 12.7% | 3.2% |
| 4. Bar icon blinks with a 600 ms `Timer` | not measurable in the preview | |

The demo agents change activity about every second, so the canvas still
repaints often there; an idle backdrop now stays unpainted. Item 4 needs a check
in the real bar while an agent waits.

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
shipping precompiled `.qsb` shaders. Items 1–4 are done; measure the remaining cost before starting it.
