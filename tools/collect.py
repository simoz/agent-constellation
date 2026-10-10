#!/usr/bin/env python3
"""Agent Constellation collector.

Reads local Claude Code and Codex session files, read-only, and answers each
snapshot request on stdin with one JSON line on stdout. See docs/protocol.md.

Only derived activity leaves this process: tool names, file paths relative to
the session directory, program names (never full command lines), token counts
and session status. Prompts, model output and tool results are never emitted.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import secrets
import stat
import sys
import time
from collections import deque
from datetime import datetime
from pathlib import Path

PROTOCOL_VERSION = 1
MAX_REQUEST_BYTES = 4096
MAX_AGENTS = 24
MAX_FILES = 16
MAX_SUBAGENTS = 6
MAX_EVENTS = 40
MAX_TEXT = 160
# A newly discovered transcript is read from its last 1 MiB; later reads take at
# most 4 MiB per file per snapshot so one huge append cannot stall a reply.
BOOTSTRAP_BYTES = 1 << 20
READ_LIMIT = 4 << 20
# An unterminated line kept for the next read; longer lines are dropped.
MAX_PARTIAL = 1 << 20
# Session records and subagent metadata are small JSON files.
MAX_RECORD = 64 << 10
# The first line of a Codex rollout (session_meta, with the base instructions).
MAX_META = 256 << 10
# Activity windows, in seconds.
WORKING_WINDOW = 20
SUBAGENT_WINDOW = 15
CODEX_STALE_WORKING = 600
TOKEN_WINDOW = 60
BUCKET_SECONDS = 10
BUCKETS = 30
HEAT_HALF_LIFE = 300

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
FILE_TOOLS = EDIT_TOOLS | {"Read"}
SPAWN_TOOLS = {"Agent", "Task"}
# Session ids and rollout names become agent ids and glob patterns; anything else is skipped.
SAFE_ID = re.compile(r"[A-Za-z0-9._-]{1,128}")
# Search patterns that may contain credentials are not shown.
SECRET_WORD = re.compile(r"(?i)pass(word|wd)?|secret|token|api[_-]?key|bearer|authorization|credential|private[_-]?key")
TOKEN_LIKE = re.compile(r"[A-Za-z0-9+/_=-]{20,}")


def now_ms() -> int:
    return int(time.time() * 1000)


def parse_ms(value) -> int | None:
    if not isinstance(value, str):
        return None
    try:
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return None


def clip(value, limit: int = MAX_TEXT) -> str:
    text = "".join(ch if ch.isprintable() else " " for ch in str(value))
    return text if len(text) <= limit else text[: limit - 1] + "…"


def search_target(pattern) -> str:
    """A search pattern or query, redacted when it names or looks like a credential."""
    text = str(pattern or "")
    if SECRET_WORD.search(text) or any(
        re.search(r"[0-9]", run) and re.search(r"[A-Za-z]", run) for run in TOKEN_LIKE.findall(text)
    ):
        return "[redacted]"
    return clip(text, 48)


def codex_running() -> bool:
    """Whether the user runs any Codex process; rollouts outlive the sessions that wrote them."""
    uid = os.getuid()
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != uid:
                continue
            with open(f"/proc/{entry.name}/comm", "rb") as handle:
                if handle.read().strip() == b"codex":
                    return True
        except OSError:
            continue
    return False


def read_json(path: Path):
    """Parse a small regular file; FIFOs, devices and oversized files raise ValueError."""
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as handle:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError("not a regular file")
        data = handle.read(MAX_RECORD + 1)
    if len(data) > MAX_RECORD:
        raise ValueError("file too large")
    return json.loads(data)


def program_name(command) -> str:
    """First program of a shell command, without arguments or env assignments."""
    if isinstance(command, list):
        # Codex wraps commands as ["/bin/bash", "-lc", "<script>"].
        command = command[-1] if command else ""
    for segment in re.split(r"[;&|\n]+", str(command)):
        words = segment.split()
        if not words or words[0] in ("cd", "pushd", "popd", "export", "set"):
            continue
        for word in words:
            # A command substitution assignment such as out=$(git log) runs its inner program.
            if "=$(" in word or word.startswith("$("):
                word = word.split("$(", 1)[1]
            if "=" in word.split("/")[0] and not word.startswith(("/", ".")):
                continue
            if word in ("sudo", "env", "time", "nice", "exec", "timeout") or word.startswith("-") or word.isdigit():
                continue
            return clip(os.path.basename(word.strip("'\"()")), 40)
    return ""


def display_path(path, cwd: str, home: str) -> str:
    path = str(path)
    if path.startswith("file://"):
        path = path[7:]
    if cwd and (path == cwd or path.startswith(cwd.rstrip("/") + "/")):
        path = os.path.relpath(path, cwd)
    elif home and path.startswith(home.rstrip("/") + "/"):
        path = "~/" + path[len(home.rstrip("/")) + 1 :]
    return clip(path)


def line_count(text) -> int:
    return len(str(text).splitlines()) if text else 0


class Tail:
    """Incremental reader of complete JSON lines appended to a file."""

    def __init__(self, path: Path):
        self.path = path
        self.offset: int | None = None
        self.inode = None
        self.rest = b""
        # Set while the rest of an overlong line is still arriving.
        self.discard = False

    def read(self):
        try:
            info = self.path.stat()
        except OSError:
            return []
        if self.inode != info.st_ino or (self.offset is not None and info.st_size < self.offset):
            self.inode, self.offset, self.rest, self.discard = info.st_ino, None, b"", False
        skip_partial = False
        if self.offset is None:
            self.offset = max(0, info.st_size - BOOTSTRAP_BYTES)
            skip_partial = self.offset > 0
        if info.st_size <= self.offset:
            return []
        try:
            with self.path.open("rb") as handle:
                handle.seek(self.offset)
                data = handle.read(READ_LIMIT)
        except OSError:
            return []
        self.offset += len(data)
        data = self.rest + data
        lines = data.split(b"\n")
        self.rest = lines.pop()
        if (skip_partial or self.discard) and lines:
            lines.pop(0)
            self.discard = False
        if len(self.rest) > MAX_PARTIAL:
            self.rest, self.discard = b"", True
        entries = []
        for line in lines:
            try:
                entry = json.loads(line)
            except (ValueError, RecursionError):
                continue
            if isinstance(entry, dict):
                entries.append(entry)
        return entries


class Agent:
    def __init__(self, ident: str, kind: str, cwd: str):
        self.id = ident
        self.kind = kind
        self.cwd = cwd
        self.name = ""
        self.model = ""
        self.status = "idle"
        self.waiting_for = ""
        self.last_tool_ms = 0
        self.activity = None
        self.tool_calls = 0
        self.output_tokens = 0
        self.token_samples: deque = deque(maxlen=512)
        self.call_times: deque = deque(maxlen=2048)
        self.files: dict[str, dict] = {}
        self.subagents: dict[str, dict] = {}
        self.seen_messages: deque = deque(maxlen=256)
        self.tails: dict[Path, Tail] = {}

    def tail(self, path: Path) -> Tail:
        if path not in self.tails:
            self.tails[path] = Tail(path)
        return self.tails[path]

    def tokens(self, at_ms: int, count) -> None:
        if isinstance(count, int) and count > 0:
            self.output_tokens += count
            self.token_samples.append((at_ms, count))

    def call(self, at_ms: int, tool: str, target: str, events: deque, subagent: str = "") -> None:
        subagent = clip(subagent, 40)
        self.tool_calls += 1
        self.call_times.append(at_ms)
        if at_ms >= self.last_tool_ms:
            self.last_tool_ms = at_ms
            self.activity = {"tool": clip(tool, 40), "target": target, "atMs": at_ms, "subagent": subagent}
        events.append({"atMs": at_ms, "agent": self.id, "subagent": subagent, "tool": clip(tool, 40), "target": target})

    def touch(self, at_ms: int, path: str, edit: bool, added: int = 0, removed: int = 0, subagent: str = "") -> None:
        subagent = clip(subagent, 40)
        entry = self.files.get(path)
        if entry is None:
            entry = self.files[path] = {"score": 0.0, "touches": 0, "edits": 0, "added": 0, "removed": 0, "lastMs": at_ms, "subagent": subagent}
        decay = math.exp(-max(0, at_ms - entry["lastMs"]) / 1000 / HEAT_HALF_LIFE * math.log(2))
        entry["score"] = entry["score"] * decay + (2 if edit else 1)
        entry["touches"] += 1
        entry["edits"] += 1 if edit else 0
        entry["added"] += added
        entry["removed"] += removed
        entry["lastMs"] = max(entry["lastMs"], at_ms)
        entry["subagent"] = subagent
        if len(self.files) > 256:
            for stale in sorted(self.files, key=lambda p: self.files[p]["lastMs"])[:64]:
                del self.files[stale]

    def snapshot(self, at_ms: int) -> dict:
        def score(entry):
            return entry["score"] * math.exp(-max(0, at_ms - entry["lastMs"]) / 1000 / HEAT_HALF_LIFE * math.log(2))

        ranked = sorted(self.files.items(), key=lambda item: score(item[1]), reverse=True)[:MAX_FILES]
        top = max([score(entry) for _, entry in ranked] + [1.0])
        buckets = [0] * BUCKETS
        for at in self.call_times:
            index = BUCKETS - 1 - (at_ms - at) // (BUCKET_SECONDS * 1000)
            if 0 <= index < BUCKETS:
                buckets[int(index)] += 1
        status = self.status
        if status == "working" and at_ms - self.last_tool_ms > WORKING_WINDOW * 1000:
            status = "thinking"
        return {
            "id": self.id,
            "kind": self.kind,
            "name": clip(self.name or os.path.basename(self.cwd.rstrip("/")) or self.kind, 60),
            "project": clip(os.path.basename(self.cwd.rstrip("/")) or "~", 60),
            "model": clip(self.model, 60),
            "status": status,
            "waitingFor": clip(self.waiting_for, 60) if status == "waiting" else "",
            "activity": self.activity,
            "toolCalls": self.tool_calls,
            "outputTokens": self.output_tokens,
            "tokensPerMinute": sum(n for at, n in self.token_samples if at_ms - at <= TOKEN_WINDOW * 1000),
            "activityBuckets": buckets,
            "subagents": [
                {"id": clip(key, 200), "name": clip(sub["name"], 40), "type": clip(sub["type"], 40)}
                for key, sub in sorted(self.subagents.items(), key=lambda item: item[1]["startedMs"])
                if at_ms - sub["lastMs"] <= SUBAGENT_WINDOW * 1000
            ][:MAX_SUBAGENTS],
            "files": [
                {"path": path, "touches": entry["touches"], "edits": entry["edits"], "added": entry["added"],
                 "removed": entry["removed"], "heat": round(min(1.0, score(entry) / top), 3),
                 "lastMs": entry["lastMs"], "subagent": entry["subagent"]}
                for path, entry in ranked
            ],
        }


class Collector:
    def __init__(self, claude_dir: Path, codex_dir: Path, sources: set[str], idle_minutes: int):
        self.claude_dir = claude_dir
        self.codex_dir = codex_dir
        self.sources = sources
        self.idle_ms = idle_minutes * 60_000
        self.home = str(Path.home())
        self.agents: dict[str, Agent] = {}
        self.events: deque = deque(maxlen=MAX_EVENTS)
        self.session = secrets.token_hex(8)
        self.sequence = 0
        self.skipped = 0
        self.codex_metas: dict[Path, dict] = {}
        self.codex_alive = codex_running

    def safely(self, handler, *args) -> None:
        """Run one record or entry handler; input of an unexpected shape is skipped, not fatal."""
        try:
            handler(*args)
        except Exception:
            self.skipped += 1

    # Claude Code -----------------------------------------------------------

    @staticmethod
    def process_alive(pid, start) -> bool:
        try:
            with open(f"/proc/{int(pid)}/stat", "rb") as handle:
                fields = handle.read().rsplit(b")", 1)[1].split()
        except (OSError, ValueError, IndexError):
            return False
        # Field 22 (starttime) is the 20th after the command name; it guards against PID reuse.
        return start is None or (len(fields) > 19 and fields[19].decode() == str(start))

    def claude(self, at_ms: int, seen: set[str]) -> str:
        sessions = self.claude_dir / "sessions"
        if not sessions.is_dir():
            return "missing"
        for record_path in sorted(sessions.glob("*.json"))[:256]:
            self.safely(self.claude_record, record_path, at_ms, seen)
        return "ok"

    def claude_record(self, record_path: Path, at_ms: int, seen: set[str]) -> None:
        try:
            record = read_json(record_path)
            session_id = str(record["sessionId"])
            cwd = str(record.get("cwd") or "")
        except (OSError, ValueError, KeyError, TypeError):
            return
        if not SAFE_ID.fullmatch(session_id):
            self.skipped += 1
            return
        if record.get("spare") or not self.process_alive(record.get("pid"), record.get("procStart")):
            return
        status = {"busy": "working", "waiting": "waiting"}.get(record.get("status"), "idle")
        changed = record.get("statusUpdatedAt") or record.get("updatedAt") or at_ms
        if status == "idle" and isinstance(changed, (int, float)) and at_ms - changed > self.idle_ms:
            return
        ident = "claude:" + session_id
        agent = self.agents.get(ident) or Agent(ident, "claude", cwd)
        self.agents[ident] = agent
        seen.add(ident)
        agent.status = status
        agent.waiting_for = str(record.get("waitingFor") or "")
        transcripts = list(self.claude_dir.glob("projects/*/" + session_id + ".jsonl"))
        if transcripts:
            for entry in agent.tail(transcripts[0]).read():
                self.safely(self.claude_entry, agent, entry, "")
            subagents = sorted(transcripts[0].with_suffix("").glob("subagents/agent-*.jsonl"))[-32:]
            for sub in subagents:
                self.safely(self.claude_subagent, agent, sub, at_ms)
            # Forget readers of transcripts that are no longer listed.
            for path in set(agent.tails) - {transcripts[0], *subagents}:
                del agent.tails[path]

    def claude_subagent(self, agent: Agent, path: Path, at_ms: int) -> None:
        key = path.stem
        try:
            modified = int(path.stat().st_mtime * 1000)
        except OSError:
            return
        if key not in agent.subagents and at_ms - modified > SUBAGENT_WINDOW * 1000:
            return
        sub = agent.subagents.get(key)
        if sub is None:
            meta = {}
            try:
                meta = read_json(path.with_name(key + ".meta.json"))
            except (OSError, ValueError):
                pass
            kind = str(meta.get("agentType") or "agent")
            sub = agent.subagents[key] = {"name": str(meta.get("name") or kind), "type": kind, "startedMs": modified, "lastMs": modified}
        sub["lastMs"] = modified
        for entry in agent.tail(path).read():
            self.safely(self.claude_entry, agent, entry, sub["name"])

    def claude_entry(self, agent: Agent, entry: dict, subagent: str) -> None:
        if entry.get("type") != "assistant":
            return
        message = entry.get("message")
        if not isinstance(message, dict):
            return
        at_ms = parse_ms(entry.get("timestamp")) or now_ms()
        model = message.get("model")
        if isinstance(model, str) and model and not model.startswith("<") and not subagent:
            agent.model = model.removeprefix("claude-")
        # Streaming writes one entry per content block with the same usage; count it once.
        message_id = message.get("id")
        usage = message.get("usage")
        if isinstance(usage, dict) and message_id not in agent.seen_messages:
            agent.seen_messages.append(message_id)
            agent.tokens(at_ms, usage.get("output_tokens"))
        for block in message.get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                self.claude_tool(agent, at_ms, str(block.get("name") or "tool"), block.get("input"), subagent)

    def claude_tool(self, agent: Agent, at_ms: int, tool: str, data, subagent: str) -> None:
        data = data if isinstance(data, dict) else {}
        if tool.startswith("mcp__"):
            tool = tool.split("__")[-1]
        target = ""
        path = data.get("file_path") or data.get("notebook_path")
        if tool in FILE_TOOLS and path:
            target = display_path(path, agent.cwd, self.home)
            added = removed = 0
            if tool == "Edit":
                added, removed = line_count(data.get("new_string")), line_count(data.get("old_string"))
            elif tool == "MultiEdit":
                for edit in data.get("edits") or []:
                    if isinstance(edit, dict):
                        added += line_count(edit.get("new_string"))
                        removed += line_count(edit.get("old_string"))
            elif tool == "Write":
                added = line_count(data.get("content"))
            agent.touch(at_ms, target, tool in EDIT_TOOLS, added, removed, subagent)
        elif tool == "Bash":
            target = program_name(data.get("command"))
        elif tool in ("Grep", "Glob"):
            target = search_target(data.get("pattern"))
        elif tool == "WebFetch":
            url = str(data.get("url") or "")
            target = clip(url.split("://", 1)[-1].split("/", 1)[0], 60)
        elif tool in SPAWN_TOOLS:
            target = clip(data.get("subagent_type") or data.get("name") or "agent", 40)
        agent.call(at_ms, tool, target, self.events, subagent)

    # Codex -----------------------------------------------------------------

    def codex(self, at_ms: int, seen: set[str]) -> str:
        root = self.codex_dir / "sessions"
        if not root.is_dir():
            return "missing"
        if not self.codex_alive():
            return "ok"
        threads: dict[str, Agent] = {}
        children = []
        days = {time.strftime("%Y/%m/%d", time.localtime(at_ms / 1000 - offset)) for offset in (0, 86400)}
        for day in sorted(days):
            for path in sorted((root / day).glob("rollout-*.jsonl"))[-64:]:
                try:
                    modified = int(path.stat().st_mtime * 1000)
                except OSError:
                    continue
                stem = path.stem.removeprefix("rollout-")
                if not SAFE_ID.fullmatch(stem):
                    self.skipped += 1
                    continue
                ident = "codex:" + stem
                if at_ms - modified > self.idle_ms and ident not in self.agents:
                    continue
                meta = self.codex_meta(path)
                if meta.get("parent"):
                    # Subagents such as the approval guardian belong to their parent thread.
                    children.append((path, stem, modified, meta))
                    continue
                agent = self.agents.get(ident) or Agent(ident, "codex", "")
                self.agents[ident] = agent
                if meta.get("thread"):
                    threads[meta["thread"]] = agent
                for entry in agent.tail(path).read():
                    self.safely(self.codex_entry, agent, entry)
                working_stale = agent.status == "working" and at_ms - modified > CODEX_STALE_WORKING * 1000
                if working_stale:
                    agent.status = "idle"
                if agent.status == "idle" and at_ms - modified > self.idle_ms:
                    continue
                seen.add(ident)
        for path, stem, modified, meta in children:
            agent = threads.get(meta["parent"])
            if agent is not None and agent.id in seen:
                self.safely(self.codex_subagent, agent, path, stem, modified, meta["name"], at_ms)
        if len(self.codex_metas) > 512:
            self.codex_metas.clear()
        return "ok"

    def codex_meta(self, path: Path) -> dict:
        """Thread id, parent thread id and subagent name from the rollout's first line."""
        if path in self.codex_metas:
            return self.codex_metas[path]
        try:
            with path.open("rb") as handle:
                line = handle.readline(MAX_META)
        except OSError:
            return {}
        try:
            entry = json.loads(line)
        except (ValueError, RecursionError):
            entry = None
        payload = entry.get("payload") if isinstance(entry, dict) and entry.get("type") == "session_meta" else None
        meta = {}
        if isinstance(payload, dict):
            source = payload.get("source")
            role = source.get("subagent") if isinstance(source, dict) else None
            if isinstance(role, dict):
                role = next((v for v in role.values() if isinstance(v, str)), next(iter(role), None))
            parent = payload.get("parent_thread_id")
            meta = {"thread": str(payload.get("id") or ""),
                    "parent": parent if isinstance(parent, str) and role else "",
                    "name": str(role or "agent")}
        # A first line still being written is read again next time.
        if line.endswith(b"\n"):
            self.codex_metas[path] = meta
        return meta

    def codex_subagent(self, agent: Agent, path: Path, key: str, modified: int, name: str, at_ms: int) -> None:
        if key not in agent.subagents and at_ms - modified > SUBAGENT_WINDOW * 1000:
            return
        sub = agent.subagents.get(key)
        if sub is None:
            sub = agent.subagents[key] = {"name": name, "type": name, "startedMs": modified, "lastMs": modified}
        sub["lastMs"] = modified
        for entry in agent.tail(path).read():
            self.safely(self.codex_entry, agent, entry, sub["name"])

    def codex_entry(self, agent: Agent, entry: dict, subagent: str = "") -> None:
        payload = entry.get("payload")
        if not isinstance(payload, dict):
            return
        at_ms = parse_ms(entry.get("timestamp")) or now_ms()
        kind, event = entry.get("type"), payload.get("type")
        if subagent:
            # A subagent's tool calls and tokens count for its parent; its turns and settings do not.
            if kind == "event_msg" and event == "item_completed" and isinstance(payload.get("item"), dict):
                self.codex_item(agent, at_ms, payload["item"], subagent)
            elif kind == "event_msg" and event == "token_count":
                info = payload.get("info")
                last = info.get("last_token_usage") if isinstance(info, dict) else None
                if isinstance(last, dict):
                    agent.tokens(at_ms, last.get("output_tokens"))
            return
        if kind in ("session_meta", "turn_context") and payload.get("cwd"):
            agent.cwd = str(payload["cwd"])
        if kind == "turn_context" and isinstance(payload.get("model"), str):
            agent.model = payload["model"]
        if kind != "event_msg":
            return
        if event == "thread_settings_applied":
            settings = payload.get("thread_settings")
            if isinstance(settings, dict) and isinstance(settings.get("model"), str):
                agent.model = settings["model"]
        elif event == "task_started":
            agent.status = "working"
        elif event in ("task_complete", "turn_aborted"):
            agent.status = "idle"
        elif event == "token_count":
            info = payload.get("info")
            last = info.get("last_token_usage") if isinstance(info, dict) else None
            if isinstance(last, dict):
                agent.tokens(at_ms, last.get("output_tokens"))
        elif event == "item_completed" and isinstance(payload.get("item"), dict):
            self.codex_item(agent, at_ms, payload["item"])

    def codex_item(self, agent: Agent, at_ms: int, item: dict, subagent: str = "") -> None:
        kind = item.get("type")
        if kind == "CommandExecution":
            parsed = [p for p in item.get("parsed_cmd") or [] if isinstance(p, dict)]
            reads = [p for p in parsed if p.get("type") == "read" and p.get("path")]
            if reads:
                for part in reads:
                    target = display_path(part["path"], agent.cwd, self.home)
                    agent.touch(at_ms, target, False, subagent=subagent)
                    agent.call(at_ms, "read", target, self.events, subagent)
            elif parsed and parsed[0].get("type") in ("search", "list_files"):
                agent.call(at_ms, str(parsed[0]["type"]).replace("_", " "), search_target(parsed[0].get("query")), self.events, subagent)
            else:
                agent.call(at_ms, "shell", program_name(item.get("command")), self.events, subagent)
        elif kind == "FileChange" and isinstance(item.get("changes"), dict):
            for path, change in list(item["changes"].items())[:32]:
                diff = str(change.get("unified_diff") or "") if isinstance(change, dict) else ""
                lines = diff.splitlines()
                added = sum(1 for line in lines if line.startswith("+") and not line.startswith("+++"))
                removed = sum(1 for line in lines if line.startswith("-") and not line.startswith("---"))
                target = display_path(path, agent.cwd, self.home)
                agent.touch(at_ms, target, True, added, removed, subagent)
                agent.call(at_ms, "apply_patch", target, self.events, subagent)
        elif kind == "ImageView" and item.get("path"):
            agent.call(at_ms, "view_image", display_path(item["path"], agent.cwd, self.home), self.events, subagent)

    # Snapshot --------------------------------------------------------------

    def snapshot(self, request_id: str) -> dict:
        at_ms = now_ms()
        seen: set[str] = set()
        sources, partial = {}, False
        self.skipped = 0
        for name, reader in (("claude", self.claude), ("codex", self.codex)):
            if name not in self.sources:
                sources[name] = "disabled"
                continue
            try:
                sources[name] = reader(at_ms, seen)
            except OSError:
                sources[name], partial = "error", True
        for ident in list(self.agents):
            if ident not in seen:
                del self.agents[ident]
        order = {"waiting": 0, "working": 1, "thinking": 2, "idle": 3}
        agents = [agent.snapshot(at_ms) for agent in self.agents.values()]
        agents.sort(key=lambda a: (order[a["status"]], -(a["activity"] or {}).get("atMs", 0), a["id"]))
        visible = {a["id"] for a in agents[:MAX_AGENTS]}
        self.sequence += 1
        return {
            "version": PROTOCOL_VERSION,
            "requestId": request_id,
            "session": self.session,
            "sequence": self.sequence,
            "observedAtMs": at_ms,
            "status": "partial" if partial or self.skipped or len(agents) > MAX_AGENTS else "ok",
            "sources": sources,
            "agents": agents[:MAX_AGENTS],
            "events": sorted((e for e in self.events if e["agent"] in visible), key=lambda e: -e["atMs"]),
        }


def serve(collector: Collector, stdin, stdout) -> None:
    for raw in stdin:
        if len(raw) > MAX_REQUEST_BYTES:
            reply = {"version": PROTOCOL_VERSION, "requestId": "", "error": "request too large"}
        else:
            try:
                request = json.loads(raw)
                valid = isinstance(request, dict) and request.get("version") == PROTOCOL_VERSION
                request_id = str(request.get("requestId", ""))[:64] if valid else ""
            except ValueError:
                valid, request_id = False, ""
            if not valid:
                reply = {"version": PROTOCOL_VERSION, "requestId": request_id, "error": "invalid request"}
            elif request.get("command") != "snapshot":
                reply = {"version": PROTOCOL_VERSION, "requestId": request_id, "error": "unknown command"}
            else:
                reply = collector.snapshot(request_id)
        # ASCII output lets the shell split pipe chunks anywhere without breaking UTF-8.
        stdout.write(json.dumps(reply, separators=(",", ":")) + "\n")
        stdout.flush()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    home = Path.home()
    parser.add_argument("--claude-dir", type=Path, default=Path(os.environ.get("CLAUDE_CONFIG_DIR") or home / ".claude"))
    parser.add_argument("--codex-dir", type=Path, default=Path(os.environ.get("CODEX_HOME") or home / ".codex"))
    parser.add_argument("--sources", default="claude,codex", help="comma-separated: claude, codex")
    parser.add_argument("--idle-minutes", type=int, default=30, help="hide sessions idle for longer (1-1440)")
    parser.add_argument("--once", action="store_true", help="print one snapshot and exit")
    args = parser.parse_args(argv)
    if not 1 <= args.idle_minutes <= 1440:
        parser.error("--idle-minutes must be 1-1440")
    sources = {s for s in args.sources.split(",") if s in ("claude", "codex")}
    collector = Collector(args.claude_dir, args.codex_dir, sources, args.idle_minutes)
    if args.once:
        print(json.dumps(collector.snapshot("once"), indent=2, ensure_ascii=False))
        return 0
    try:
        serve(collector, sys.stdin, sys.stdout)
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
