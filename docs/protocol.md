# Collector protocol

`tools/collect.py` reads one JSON request per line on stdin and writes one JSON
reply per line on stdout. Output is ASCII JSON, so the shell can split pipe
chunks anywhere. Diagnostics never go to stdout.

## Request

```json
{"version":1,"requestId":"g1-r1","command":"snapshot"}
```

Requests longer than 4096 bytes, with another version, invalid JSON or an
unknown command get `{"version":1,"requestId":"…","error":"…"}`. The UI treats
any error reply as fatal for that process.

## Snapshot

```json
{
  "version": 1, "requestId": "g1-r1", "session": "16 hex chars", "sequence": 1,
  "observedAtMs": 1791630000000, "status": "ok",
  "sources": {"claude": "ok", "codex": "missing"},
  "agents": [{
    "id": "claude:<session id>", "kind": "claude", "name": "demo", "project": "demo",
    "model": "opus-5-5", "status": "working", "waitingFor": "",
    "activity": {"tool": "Edit", "target": "app/order.rb", "atMs": 1791630000000, "subagent": ""},
    "toolCalls": 20, "outputTokens": 3600, "tokensPerMinute": 900,
    "activityBuckets": [0, 1, "… 30 counts of tool calls per 10 s, oldest first"],
    "pids": [4242, 4200, 3900],
    "subagents": [{"id": "agent-…", "name": "Explore", "type": "Explore"}],
    "files": [{"path": "app/order.rb", "touches": 4, "edits": 3, "added": 19, "removed": 6,
               "heat": 1, "lastMs": 1791630000000, "subagent": ""}]
  }],
  "events": [{"atMs": 1791630000000, "agent": "claude:<session id>", "subagent": "", "tool": "Edit", "target": "app/order.rb"}]
}
```

- `session` changes when the collector restarts; `sequence` then starts at 1
  and must increase within a session.
- `status` is `partial` when a source failed to read, agents were omitted, or
  input was skipped: a session or rollout id outside `[A-Za-z0-9._-]{1,128}`,
  or a record or entry of an unexpected shape.
- `sources.*`: `ok`, `missing` (directory absent), `disabled`, `error`.
- `agents[].status`: `working`, `thinking`, `waiting`, `idle`. Agents are
  sorted waiting first, then by latest activity.
- `pids` lists the agent process and its ancestors owned by the user, nearest
  first, so the UI can find the terminal window. For Codex it starts from the
  process holding the thread's writer lock.
- `heat` is 0–1, relative to the hottest file of the same agent; touches decay
  with a five-minute half-life and edits weigh double.

## Limits

| Item | Limit |
| --- | --- |
| Reply line | 2 MiB |
| Agents | 24 |
| Files per agent | 16 |
| Subagents per agent | 6 |
| Events | 40 |
| Process ids per agent | 16 |
| Agent name, project, model, waitingFor | 60 characters |
| Tool, subagent name | 40 characters |
| Target, file path | 160 characters |

Strings contain no control characters. `Protocol.js` rejects replies that break
any limit, answer another request, repeat a sequence or reference unknown
agents.
