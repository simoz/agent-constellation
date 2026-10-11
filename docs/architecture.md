# Architecture

Agent Constellation targets the Omarchy Quattro built-in bar and Quickshell. The
plugin ID is `io.github.simoz.agent-constellation`; `Service.qml` and
`BarWidget.qml` are the manifest entry points. A Python standard-library
collector reads local agent session files; nothing else runs outside the shell.

## Interface and lifecycle

- `BarWidget.qml` registers the host view, draws the bar icon (one dot per
  agent, red while an agent waits for input) and opens `Panel.qml`.
- `Panel.qml` keeps one `Dashboard` scene when switching between the compact
  panel and the expanded window, preserving selection and focus. The scene
  loads on the first open, not at startup on every bar.
- `Service.qml` owns settings, the latest snapshot, agent color roles,
  selection and animation state across views.
- `Collector.qml` owns the single collector process, snapshot requests, bounded
  framing and retry state.
- `ui/Constellation.qml` draws static geometry and labels on one canvas,
  repainted only when data, size, selection or theme change. Moving parts
  (`ui/AgentMotion.qml`, `ui/Particle.qml`: particles, subagent orbits, core
  pulses, ripples, waiting edges; `ui/TokenWaves.qml`: one periodic wave strip
  per agent, drawn once per snapshot and slid along) are scene-graph items whose positions derive
  from one scene clock ticking at 30 fps, only while the view is visible and
  animation is on. The clock also stops when the window has presented no frame
  for a second, as on another workspace, and restarts on its next frame. A full-window canvas repainted every frame cost about a third
  of a core inside the shell; vsync-driven animations still rendered at 60 fps.
  With the timer, an open window renders about 33 frames per second and costs
  about 11% of a core on the test VM with the three demo agents, 5% zoomed on
  one agent and 2% with the animation paused (offscreen preview, October 2026).
- `Backdrop.qml`, loaded by the service when Settings enable it, shows a
  backdrop `Constellation` on every screen in a layer-shell window on the
  `Bottom` layer (above Omarchy's `Background` wallpaper layer, below windows):
  transparent, click-through (`mask: Region {}`), without keyboard focus. It
  registers as an open view, so it refreshes at the configured interval, and it
  animates at 15 fps only while an agent is busy or waiting. On the test VM it added about
  2% of a core while covered by windows; an uncovered desktop costs more.
- `ui/Palette.qml` reads named colors from the active theme's `colors.toml`,
  because the host `Color` singleton exposes only foreground, background,
  accent, urgent and muted. It reloads whenever those host colors change.

Collection runs while at least one bar view is registered, unless paused. With
only the bar, the collector is asked for a snapshot every 5 seconds so the icon
can flag a waiting agent; open panels and windows use the configured 1–10
second interval. Removing every bar view stops the collector. Manual pause
survives closing and reopening views.

## Data flow

The UI requests snapshots over the collector's stdin
([protocol](protocol.md)). For each request the collector:

1. lists Claude Code session records in `~/.claude/sessions/*.json` and keeps
   those whose process is alive (PID and start time, against PID reuse);
2. reads the lines appended since the previous request to each session
   transcript (`projects/*/<session>.jsonl`) and its subagent transcripts
   (`<session>/subagents/agent-*.jsonl`);
3. reads Codex rollouts from today's and yesterday's
   `~/.codex/sessions/YYYY/MM/DD/` folders that changed within the idle window,
   only while their thread is open: Codex holds a `flock` on
   `thread-writer-locks/<thread id>.lock` for each open thread, and the file
   outlives it. The lock holder (listed in `/proc/locks`) is the process whose
   ancestors lead to the terminal. Rollouts themselves carry no process id, and
   an interrupted turn never records its completion. A rollout whose
   `session_meta` names a `parent_thread_id` (a subagent such as the approval
   guardian) is shown as a subagent of its parent, not as an agent;
4. replies with per-agent status, current activity, file heat, subagents,
   token rate, a five-minute activity histogram and the last 40 tool calls.

A new transcript is read from its last 1 MiB; later reads take at most 4 MiB per
file per request, and an unterminated line longer than 1 MiB is dropped. Session
records and subagent metadata must be regular files of at most 64 KiB. `Protocol.js` validates framing, limits, session and sequence
before the snapshot replaces the previous one.

## Status

| Status | Claude Code | Codex |
| --- | --- | --- |
| working | session record `busy`, a tool call in the last 20 s | `task_started` without a later completion |
| thinking | session record `busy`, no recent tool call | `task_started`, no tool call in the last 20 s |
| waiting | session record `waiting` (permission, input) | not recorded by Codex |
| idle | session record `idle`; hidden after the idle window | after `task_complete` / `turn_aborted`, or 10 min without changes; hidden when its thread lock is not held |

## Privacy

Transcripts contain prompts, model output, command lines and tool results. The
collector emits only tool names, file paths relative to the session directory
(or `~/…`, or `…/name` outside both), program names without arguments, search patterns and hosts (both
truncated; patterns that name or look like credentials are redacted), subagent names, model names, token counts and status. It writes
nothing and makes no network requests. Snapshots stay in memory.

## Design record

- ID: `io.github.simoz.agent-constellation`, kinds `service` + `bar-widget`.
- User problem: see at a glance what each coding agent is doing, which files it
  touches and whether it is waiting for you.
- Per-instance state: bar icon per monitor. Process-wide state: snapshot,
  selection, color roles, animation and pause in `Service.qml`.
- Durable state: inline plugin configuration in `shell.json` (sources, session
  directories, interval, idle window, waiting notifications, desktop backdrop),
  written by
  Settings → Done.
- External commands: `python3` running `tools/collect.py`; `hyprctl clients -j`
  and `hyprctl dispatch hl.dsp.focus(...)` to go to an agent's terminal;
  `notify-send` with one action when an agent starts waiting. All run with
  argument lists. No credentials, no network endpoints, no privileged
  operations, no changes to agent settings.
- Failure states: collector unavailable (no Python), invalid output, timeouts
  with bounded retries, source directory missing, source disabled.
- Removal: `omarchy plugin remove` deletes the plugin and its configuration;
  nothing else is installed.
- Tests: collector unit tests on synthetic sessions, protocol and model tests,
  QtTest for keyboard behavior, offscreen captures from `demo/run`.
- Prior art (October 2026): `omarchy.agents` shows usage and limits; "Agent
  Sessions" lists live session status; "Agent Activity Visualization" charts
  history. None draws live tool activity per file.
- Deferred: Codex approval detection, and the other agents Omarchy offers (pi,
  omp, opencode, crush, grok, gemini, openclaw, hermes, copilot, cursor-agent,
  muse). Each needs real sessions to verify its format, so it waits until one
  is in use; presence from running processes (project from the working
  directory, terminal from the process ancestry) would come first, then a
  per-agent transcript parser.
