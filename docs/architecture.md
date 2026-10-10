# Architecture

Agent Constellation targets the Omarchy Quattro built-in bar and Quickshell. The
plugin ID is `io.github.simoz.agent-constellation`; `Service.qml` and
`BarWidget.qml` are the manifest entry points. A Python standard-library
collector reads local agent session files; nothing else runs outside the shell.

## Interface and lifecycle

- `BarWidget.qml` registers the host view, draws the bar icon (one dot per
  agent, red while an agent waits for input) and opens `Panel.qml`.
- `Panel.qml` keeps one `Dashboard` scene when switching between the compact
  panel and the expanded window, preserving selection and focus.
- `Service.qml` owns settings, the latest snapshot, agent color roles,
  selection and animation state across views.
- `Collector.qml` owns the single collector process, snapshot requests, bounded
  framing and retry state.
- `ui/Constellation.qml` draws static geometry and labels on one canvas,
  repainted only when data, size, selection or theme change. Moving parts
  (`ui/AgentMotion.qml`, `ui/Particle.qml`: particles, subagent orbits, core
  pulses, ripples, waiting edges) are scene-graph items whose positions derive
  from one scene clock ticking at 30 fps, only while the view is visible and
  animation is on. A full-window canvas repainted every frame cost about a third
  of a core inside the shell; vsync-driven animations still rendered at 60 fps.
  With the timer, an open window costs about 12% of a core on the test VM.
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
   `~/.codex/sessions/YYYY/MM/DD/` folders that changed within the idle window;
4. replies with per-agent status, current activity, file heat, subagents,
   token rate, a five-minute activity histogram and the last 40 tool calls.

A new transcript is read from its last 1 MiB; later reads take at most 4 MiB per
file per request. `Protocol.js` validates framing, limits, session and sequence
before the snapshot replaces the previous one.

## Status

| Status | Claude Code | Codex |
| --- | --- | --- |
| working | session record `busy`, a tool call in the last 20 s | `task_started` without a later completion |
| thinking | session record `busy`, no recent tool call | `task_started`, no tool call in the last 20 s |
| waiting | session record `waiting` (permission, input) | not recorded by Codex |
| idle | session record `idle`; hidden after the idle window | after `task_complete` / `turn_aborted`, or 10 min without changes |

## Privacy

Transcripts contain prompts, model output, command lines and tool results. The
collector emits only tool names, file paths relative to the session directory
(or `~/…`), program names without arguments, search patterns and hosts (both
truncated), subagent names, model names, token counts and status. It writes
nothing and makes no network requests. Snapshots stay in memory.

## Design record

- ID: `io.github.simoz.agent-constellation`, kinds `service` + `bar-widget`.
- User problem: see at a glance what each coding agent is doing, which files it
  touches and whether it is waiting for you.
- Per-instance state: bar icon per monitor. Process-wide state: snapshot,
  selection, color roles, animation and pause in `Service.qml`.
- Durable state: inline plugin configuration in `shell.json` (sources, session
  directories, interval, idle window), written by Settings → Done.
- External commands: `python3` running `tools/collect.py`. No credentials, no
  network endpoints, no privileged operations, no changes to agent settings.
- Failure states: collector unavailable (no Python), invalid output, timeouts
  with bounded retries, source directory missing, source disabled.
- Removal: `omarchy plugin remove` deletes the plugin and its configuration;
  nothing else is installed.
- Tests: collector unit tests on synthetic sessions, protocol and model tests,
  QtTest for keyboard behavior, offscreen captures from `demo/run`.
- Prior art (October 2026): `omarchy.agents` shows usage and limits; "Agent
  Sessions" lists live session status; "Agent Activity Visualization" charts
  history. None draws live tool activity per file.
- Deferred: Hyprland background-layer mode, focusing an agent's terminal,
  desktop notifications for waiting agents, Codex approval detection, other
  agents (opencode, pi).
