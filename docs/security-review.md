# Security review

Reviewed on 2026-10-10 at commit `2882b5a`: `tools/collect.py`, `Protocol.js`,
`Model.js`, `Service.qml`, `Collector.qml`, `BarWidget.qml`, `Panel.qml`, `ui/`,
`tools/preview.qml`, `tools/prepare_preview.py`, `run-ui.sh` and `demo/`.

No high or critical issue was found. The plugin has no network access, no
privileged operation, no shell interpolation and no writes outside its own
configuration. The two medium findings are availability problems: one malformed
line in a session file can stop the visualizer until the shell restarts. They
were reproduced, not inferred.

| ID | Severity | Finding | Status |
| --- | --- | --- | --- |
| M1 | Medium | Unexpected JSON shapes crash the collector, and the restart loop ends in a permanent error | Open |
| M2 | Medium | Unsanitized agent ids make the UI reject every snapshot | Open |
| L1 | Low | `sessionId` is used unvalidated in a glob pattern | Open |
| L2 | Low | Session records are read whole, without a size limit | Open |
| L3 | Low | Search patterns and Codex queries may show secrets on screen | Open |
| L4 | Low | Partial lines are retained per file, up to 4 MiB each | Open |
| I1 | Info | `python3` is resolved through `PATH` | Accepted |
| I2 | Info | Snapshot data is reachable by other plugins in the shared scene | Accepted |
| I3 | Info | Preview directories under `/tmp` are never removed | Open |
| I4 | Info | Symbolic links to transcripts are followed | Accepted |

## Threat model

The plugin runs unsandboxed inside `omarchy-shell`, with the user's
privileges. It starts one child process, `python3 -B tools/collect.py`, which
reads files the user already owns:

- `~/.claude/sessions/*.json` (session records written by Claude Code);
- `~/.claude/projects/*/<session>.jsonl` and `<session>/subagents/*.jsonl`
  (transcripts);
- `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (Codex rollouts);
- `~/.local/state/omarchy/current/theme/colors.toml` (read by QML).

Transcripts and rollouts are the main untrusted input. Their structure is
written by the agent CLIs, but much of their content comes from places the user
does not control: tool inputs chosen by the model, file names from cloned
repositories, web pages, command output. A prompt injection can therefore shape
tool inputs that end up in these files. An attacker who can write to these
directories directly already runs code as the user, so that case is out of
scope; the relevant attacker shapes **content** that the agents record.

Assets:

- **Confidentiality**: prompts, replies, command lines and tool output in the
  transcripts must not leave the collector.
- **Availability**: the visualizer, and the shell it runs in, must keep working
  on any input.
- **Integrity of the shell**: nothing read from the files may be executed or
  interpreted as markup.

## Findings

### M1 — Unexpected JSON shapes crash the collector

**Where**: `tools/collect.py`, `Collector.claude`, `claude_entry`,
`claude_tool`, `codex_item`, `Tail.read`; the snapshot only catches `OSError`.

The parser assumes field types that valid JSON need not have. Each of these
lines raised an uncaught exception during the review:

| Input | Exception |
| --- | --- |
| `MultiEdit` with `"edits": 5` | `TypeError: 'int' object is not iterable` |
| Session record with `"status": ["busy"]` | `TypeError: unhashable type: 'list'` |
| Assistant entry with `"content": 7` | `TypeError: 'int' object is not iterable` |
| A line with 100,000 nested arrays | `RecursionError` (not a `ValueError`, so not skipped) |

`Codex` items have the same pattern (`parsed_cmd` as a number).

**Scenario**: a prompt-injected model emits a tool call with an odd input
shape, or a future CLI version changes a field type. The collector exits;
`Collector.qml` restarts it five times with backoff. Each restart re-reads the
same last 1 MiB of the transcript and crashes again, so the view ends in
"Collector stopped repeatedly" and stays there until the session file ages out
or the shell restarts. The rest of the shell is not affected.

**Fix**:

- Catch `(ValueError, RecursionError)` around `json.loads` in `Tail.read`.
- Wrap the processing of each entry and each session record in
  `try/except Exception`, skip the entry, and count it in a new
  `sources.<name>` state or a `skipped` counter so the UI can report `partial`.
- Check types before iterating (`isinstance(x, list)`) where the code iterates
  over input fields.
- Add the four inputs above as regression tests in `tests/test_collect.py`.

### M2 — Unsanitized agent ids make the UI reject every snapshot

**Where**: `tools/collect.py`, `ident = "claude:" + session_id` and
`"codex:" + path.stem`; `Protocol.js`, `text(a.id, 200)`.

Every other string is passed through `clip()`, which replaces control
characters and truncates. Agent ids are not. A `sessionId` containing a newline
produced a snapshot that `Protocol.parse` rejected ("Invalid snapshot"). The
same happens with a rollout file name containing a control character, or an id
over 200 characters.

**Scenario**: one malformed session record or file name. `Collector.qml` treats
invalid output as fatal ("Invalid or incompatible collector output") and does
not retry, so the view stays empty for every agent, not only the bad one.

**Fix**: accept only ids matching `^[A-Za-z0-9._-]{1,128}$` for Claude session
ids and rollout stems, and skip anything else. Keep the strict check in
`Protocol.js`: it is the right defence, the collector just has to honour it.

### L1 — `sessionId` is used unvalidated in a glob pattern

**Where**: `Collector.claude`,
`self.claude_dir.glob("projects/*/" + session_id + ".jsonl")`.

`session_id` comes from the session record. Python's `Path.glob` accepts `..`
segments: during the review, `projects/*/../../secret.jsonl` matched a file
outside `projects/`. Glob metacharacters (`*`, `?`, `[`) are also expanded.

**Impact**: the collector could read another JSONL file the user can read and
derive tool names and paths from it. Only someone who can already write
`~/.claude/sessions/` can trigger it, so this is a hardening issue.

**Fix**: the same id validation as M2, before the glob.

### L2 — Session records are read whole, without a size limit

**Where**: `Collector.claude`, `record_path.read_text()`.

Transcripts are read in bounded chunks, but each session record is read
entirely on every snapshot, once a second while a view is open. A very large
or endless file (for example a symlink to a device) costs memory and time; a
read longer than 5 s also trips the UI watchdog (see M1 for the retry outcome).

**Fix**: skip records that are not regular files or exceed 64 KiB (`stat`
before reading, then read at most that many bytes).

### L3 — Search patterns and Codex queries may show secrets on screen

**Where**: `claude_tool` (`Grep`/`Glob` pattern, `WebFetch` host) and
`codex_item` (`search` query).

Program names are reduced to the first word without arguments, but search
patterns and queries are shown as typed, truncated to 48 characters. An agent
grepping for an API key or a password puts that string in the panel, the event
log and on any screen share.

**Fix**: show only the tool name for searches, or mask patterns that look like
credentials (long high-entropy tokens, `key=`, `token`, `password`). Document
the choice in the README section on what the data means.

### L4 — Partial lines are retained per file, up to 4 MiB each

**Where**: `Tail.read`, `self.rest`.

An unterminated last line is kept until the next read, up to `READ_LIMIT`
(4 MiB) per tracked file. With many live sessions and subagents the retained
memory can reach hundreds of MiB in the worst case.

**Fix**: drop `rest` above 1 MiB (one transcript entry is rarely larger), and
cap the number of tracked tails.

### I1 — `python3` is resolved through `PATH`

`Collector.qml` starts `python3` by name. Anyone who can change the shell's
`PATH` already controls the user session, so this adds no exposure. Outbound
and `omarchy.agents` do the same. Accepted.

### I2 — Snapshot data is reachable by other plugins

The Omarchy host documents that visual plugins share one QML scene and can
traverse it. Another installed plugin could read the snapshot: project names,
file paths, tool names. It cannot reach transcript content, which never leaves
the collector. Accepted, and noted in the threat model.

### I3 — Preview directories under `/tmp` are never removed

`tools/prepare_preview.py` creates a new `constellation-preview-*` directory on
each run (mode 0700, via `mkdtemp`) and nothing deletes it. Harmless, but it
accumulates. `demo/run` cleans up its own work directory.

**Fix**: let `run-ui.sh` remove the directory on exit with a `trap`.

### I4 — Symbolic links to transcripts are followed

A transcript or rollout that is a symlink is read like a regular file. The
user owns these directories, and the bounded reader handles special files
(their size is 0, so nothing is read). Accepted; L2 adds the regular-file check
for session records.

## Controls that hold

- **No markup from data**: every `Text`/`Label` showing snapshot data uses
  `Text.PlainText`, and so do the host's bar tooltip and `WidgetButton` label. Canvas
  `fillText` draws plain text. A project name such as `<img src=…>` is shown
  literally and loads nothing.
- **No shell**: the collector is started with an argument list. Directory paths
  from Settings must be absolute, contain no control characters and start with
  `/`, so they cannot be read as options.
- **Bounded, validated protocol**: ASCII-only framing, one reply per request,
  2 MiB per line, a session and sequence check against stale replies, and
  per-field type and length checks in `Protocol.js`.
- **Bounded reads**: 1 MiB at first sight of a transcript, then at most 4 MiB
  per file per snapshot; at most 256 session records, 32 subagent files per
  session and 64 rollouts per day.
- **Derived data only**: prompts, replies, command arguments and tool output
  never leave the collector. Tests assert this for a prompt, an environment
  variable assignment and command arguments.
- **PID reuse**: a session counts only while its PID has the recorded start
  time.
- **Process lifecycle**: one collector at a time, killed with SIGTERM then
  SIGKILL when views go away; it also exits on EOF if the shell dies.
- **No network, no writes**: the collector opens no sockets and writes only to
  stdout. The plugin writes only its inline configuration through the host.
- **Theme input**: `colors.toml` values are accepted only as `#rrggbb` or
  `light`/`dark`.

## Recommendations

1. Fix M1 and M2 together, with regression tests for each input in this
   review: they share the outcome of a permanently empty view.
2. Fix L1 with the same id validation, and L2 with a size and file-type check.
3. Decide how much of search patterns to show (L3) and document it.
4. Tighten L4 and I3 when convenient.

## Reproduction

The findings above were reproduced with synthetic files in a temporary
directory, calling `collect.Collector(...).snapshot()` directly, and with
`Protocol.parse` under Node for M2. Static review covered every QML file for
text formats, process invocation, `Qt.openUrlExternally` (unused) and network
access (none).
