# Changelog

All notable changes to Agent Constellation. Versions follow
[Semantic Versioning](https://semver.org/).

## 0.1.0 — 2026-10-10

First release as an Omarchy Quattro plugin, replacing the web prototype.

### Added

- Bar widget with one dot per agent, a count, and a red pulsing icon while an
  agent waits for input; left click opens the panel, right click the expanded
  window.
- Live constellation of Claude Code and Codex sessions: a core per agent,
  orbiting subagents, tool calls flying to the files they touch, files that heat
  up with use, and token waves that follow each agent's output.
- Agent cards with status, current activity, model, tokens and an activity
  sparkline; long project names wrap to two lines.
- Event log of the last 40 tool calls, filtered by the selected agent.
- Zoom into a single session, with file paths and line counts (⊕, Ctrl+Z,
  Enter, or a double click on a core).
- Go to an agent's terminal window (↗, Ctrl+T, or a double click on a card).
- Desktop notification when an agent starts waiting, with a Go to terminal
  action.
- Optional constellation on the desktop, above the wallpaper and below windows.
- Settings for sources, session directories, refresh interval, idle window,
  notifications and the desktop view; full keyboard use with a KEYS guide (F1).
- Read-only Python collector (standard library only): Claude Code session
  records and transcripts, Codex rollouts; Codex threads count as open while
  Codex holds their writer lock. Only derived data leaves the collector, and
  search patterns that look like credentials are redacted.
- Security review (`docs/security-review.md`); all findings fixed.
- Demo tooling: README screenshots, a live scripted demo on fictional Rails
  applications, and a launch video renderer.
