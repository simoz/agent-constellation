"""Collector tests with synthetic Claude Code and Codex session files."""

import io
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import collect  # noqa: E402

PROJECT = "/home/tester/work/demo"


def iso(offset_seconds=0):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + offset_seconds))


def start_time(pid):
    with open(f"/proc/{pid}/stat", "rb") as handle:
        return handle.read().rsplit(b")", 1)[1].split()[19].decode()


def tool(name, data, message_id="m1", tokens=100, offset=0, sidechain=False):
    return {"type": "assistant", "timestamp": iso(offset), "isSidechain": sidechain,
            "message": {"id": message_id, "model": "claude-opus-5-5", "usage": {"output_tokens": tokens},
                        "content": [{"type": "tool_use", "id": "t-" + message_id, "name": name, "input": data}]}}


class CollectorTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.claude = self.root / "claude"
        self.codex = self.root / "codex"
        (self.claude / "sessions").mkdir(parents=True)
        self.transcripts = self.claude / "projects" / "-home-tester-work-demo"
        self.transcripts.mkdir(parents=True)

    def tearDown(self):
        self.temp.cleanup()

    def collector(self, sources=("claude", "codex"), idle=30, codex_alive=True):
        collector = collect.Collector(self.claude, self.codex, set(sources), idle)
        collector.codex_alive = lambda: codex_alive
        return collector

    def session(self, session_id="s1", status="busy", pid=None, start=None, **extra):
        pid = pid or os.getpid()
        record = {"pid": pid, "sessionId": session_id, "cwd": PROJECT, "status": status,
                  "procStart": start or start_time(pid), "statusUpdatedAt": int(time.time() * 1000), **extra}
        (self.claude / "sessions" / f"{session_id}.json").write_text(json.dumps(record))

    def append(self, path, *entries):
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as handle:
            for entry in entries:
                handle.write(json.dumps(entry) + "\n")

    def test_claude_session_reports_files_tools_and_tokens(self):
        self.session()
        self.append(self.transcripts / "s1.jsonl",
                    {"type": "user", "timestamp": iso(), "message": {"content": "secret prompt"}},
                    tool("Read", {"file_path": PROJECT + "/app/order.rb"}, "m1", 40),
                    tool("Edit", {"file_path": PROJECT + "/app/order.rb", "old_string": "a", "new_string": "b\nc"}, "m2", 60),
                    tool("Edit", {"file_path": PROJECT + "/app/order.rb", "old_string": "x", "new_string": "y"}, "m2", 60),
                    tool("Bash", {"command": "cd /tmp && API_KEY=hunter2 bundle exec rspec --seed 1"}, "m3", 10))
        snapshot = self.collector().snapshot("r1")
        self.assertEqual(snapshot["sources"], {"claude": "ok", "codex": "missing"})
        agent = snapshot["agents"][0]
        self.assertEqual((agent["kind"], agent["project"], agent["model"], agent["status"]), ("claude", "demo", "opus-5-5", "working"))
        self.assertEqual(agent["toolCalls"], 4)
        # Streaming repeats usage per content block; message m2 counts once.
        self.assertEqual(agent["outputTokens"], 110)
        self.assertEqual(agent["files"][0]["path"], "app/order.rb")
        self.assertEqual((agent["files"][0]["edits"], agent["files"][0]["added"], agent["files"][0]["removed"]), (2, 3, 2))
        self.assertEqual(agent["activity"]["tool"], "Bash")
        self.assertEqual(agent["activity"]["target"], "bundle")
        payload = json.dumps(snapshot)
        for private in ("secret prompt", "hunter2", "rspec"):
            self.assertNotIn(private, payload)

    def test_reads_only_appended_lines(self):
        self.session()
        transcript = self.transcripts / "s1.jsonl"
        self.append(transcript, tool("Read", {"file_path": PROJECT + "/a.rb"}, "m1"))
        collector = self.collector()
        self.assertEqual(collector.snapshot("r1")["agents"][0]["toolCalls"], 1)
        with transcript.open("a") as handle:
            handle.write(json.dumps(tool("Read", {"file_path": PROJECT + "/b.rb"}, "m2"))[:30])
        self.assertEqual(collector.snapshot("r2")["agents"][0]["toolCalls"], 1)
        with transcript.open("a") as handle:
            handle.write(json.dumps(tool("Read", {"file_path": PROJECT + "/b.rb"}, "m2"))[30:] + "\n")
        second = collector.snapshot("r3")
        self.assertEqual(second["agents"][0]["toolCalls"], 2)
        self.assertEqual(second["sequence"], 3)

    def test_waiting_status_and_ordering(self):
        self.session("s1", "busy")
        self.session("s2", "waiting", waitingFor="permission")
        snapshot = self.collector().snapshot("r")
        self.assertEqual([a["status"] for a in snapshot["agents"]], ["waiting", "thinking"])
        self.assertEqual(snapshot["agents"][0]["waitingFor"], "permission")

    def test_dead_or_reused_pid_and_old_idle_sessions_are_hidden(self):
        self.session("s1", start="1")
        self.session("s2", pid=2 ** 22 + 7, start="1")
        self.session("s3", "idle", statusUpdatedAt=int(time.time() * 1000) - 31 * 60_000)
        self.assertEqual(self.collector().snapshot("r")["agents"], [])

    def test_subagent_activity_is_attributed(self):
        self.session()
        self.append(self.transcripts / "s1.jsonl", tool("Agent", {"subagent_type": "Explore", "prompt": "private"}, "m1"))
        sub = self.transcripts / "s1" / "subagents" / "agent-x1.jsonl"
        self.append(sub, tool("Grep", {"pattern": "has_many"}, "m9", sidechain=True))
        sub.with_name("agent-x1.meta.json").write_text(json.dumps({"agentType": "Explore", "name": "explorer"}))
        agent = self.collector().snapshot("r")["agents"][0]
        self.assertEqual(agent["subagents"], [{"id": "agent-x1", "name": "explorer", "type": "Explore"}])
        self.assertEqual(agent["activity"]["subagent"], "explorer")
        self.assertNotIn("private", json.dumps(agent))

    def test_codex_rollout(self):
        day = self.codex / "sessions" / time.strftime("%Y/%m/%d")
        rollout = day / "rollout-2026-10-10T10-00-00-abc.jsonl"
        self.append(rollout,
                    {"timestamp": iso(), "type": "session_meta", "payload": {"cwd": PROJECT}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "thread_settings_applied", "thread_settings": {"model": "gpt-5-codex"}}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "task_started"}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "item_completed", "item": {
                        "type": "CommandExecution", "command": ["/bin/bash", "-lc", "cat app/x.rb"],
                        "parsed_cmd": [{"type": "read", "path": PROJECT + "/app/x.rb"}]}}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "item_completed", "item": {
                        "type": "FileChange", "changes": {PROJECT + "/app/x.rb": {"unified_diff": "@@\n-a\n+b\n+c\n"}}}}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "token_count", "info": {"last_token_usage": {"output_tokens": 42}}}})
        agent = self.collector(("codex",)).snapshot("r")["agents"][0]
        self.assertEqual((agent["kind"], agent["project"], agent["model"], agent["status"]), ("codex", "demo", "gpt-5-codex", "working"))
        self.assertEqual(agent["files"][0], {**agent["files"][0], "path": "app/x.rb", "touches": 2, "edits": 1, "added": 2, "removed": 1})
        self.assertEqual(agent["outputTokens"], 42)
        self.append(rollout, {"timestamp": iso(), "type": "event_msg", "payload": {"type": "task_complete"}})

    def test_unexpected_shapes_are_skipped(self):
        # Inputs from docs/security-review.md (M1): valid JSON with unexpected types or depth.
        self.session()
        self.session("s2", status=["busy"])
        transcript = self.transcripts / "s1.jsonl"
        self.append(transcript,
                    tool("MultiEdit", {"file_path": PROJECT + "/a.rb", "edits": 5}, "m1"),
                    {"type": "assistant", "timestamp": iso(), "message": {"id": "m2", "content": 7}})
        with transcript.open("a") as handle:
            handle.write("[" * 100_000 + "]" * 100_000 + "\n")
        self.append(transcript, tool("Read", {"file_path": PROJECT + "/b.rb"}, "m3"))
        rollout = self.codex / "sessions" / time.strftime("%Y/%m/%d") / "rollout-x.jsonl"
        self.append(rollout,
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "item_completed", "item": {"type": "CommandExecution", "parsed_cmd": 3}}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "task_started"}})
        snapshot = self.collector().snapshot("r")
        self.assertEqual(snapshot["status"], "partial")
        agents = {a["id"]: a for a in snapshot["agents"]}
        self.assertEqual(agents["claude:s1"]["activity"]["target"], "b.rb")
        self.assertEqual(agents["codex:x"]["status"], "thinking")

    def test_unsafe_ids_are_skipped(self):
        # docs/security-review.md M2 and L1: ids end up in the protocol and in a glob pattern.
        self.session("bad", sessionId="s\n1")
        self.session("escape", sessionId="../../outside")
        self.append(self.claude / "outside.jsonl", tool("Read", {"file_path": PROJECT + "/x.rb"}))
        self.session("ok", sessionId="s-1")
        self.append(self.codex / "sessions" / time.strftime("%Y/%m/%d") / "rollout-a\x1bb.jsonl",
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "task_started"}})
        snapshot = self.collector().snapshot("r")
        self.assertEqual([a["id"] for a in snapshot["agents"]], ["claude:s-1"])
        self.assertEqual(snapshot["status"], "partial")

    def test_session_records_must_be_small_regular_files(self):
        # docs/security-review.md L2: a FIFO would block and a huge record would be read whole.
        self.session("s1")
        self.session("s2", padding="x" * (collect.MAX_RECORD + 1))
        os.mkfifo(self.claude / "sessions" / "fifo.json")
        snapshot = self.collector().snapshot("r")
        self.assertEqual([a["id"] for a in snapshot["agents"]], ["claude:s1"])

    def test_search_patterns_with_credentials_are_redacted(self):
        # docs/security-review.md L3.
        cases = {"has_many": "has_many", "**/*.rb": "**/*.rb", "password = ": "[redacted]",
                 "API_KEY": "[redacted]", "sk-ant-api03-a1B2c3D4e5F6g7H8": "[redacted]",
                 "validates_presence_of_name": "validates_presence_of_name"}
        for pattern, expected in cases.items():
            self.assertEqual(collect.search_target(pattern), expected, pattern)

    def test_overlong_partial_line_is_dropped(self):
        # docs/security-review.md L4: the unterminated rest is capped, and its tail is not parsed later.
        transcript = self.transcripts / "s1.jsonl"
        transcript.write_text("")
        tail = collect.Tail(transcript)
        self.assertEqual(tail.read(), [])
        with transcript.open("a") as handle:
            handle.write("x" * (collect.MAX_PARTIAL + 10))
        self.assertEqual(tail.read(), [])
        self.assertEqual(tail.rest, b"")
        with transcript.open("a") as handle:
            handle.write('{"type": "fragment"}\n{"type": "ok"}\n')
        self.assertEqual(tail.read(), [{"type": "ok"}])

    def test_codex_rollouts_need_a_running_codex(self):
        # A rollout interrupted mid-task keeps its last task_started after Codex exits.
        self.append(self.codex / "sessions" / time.strftime("%Y/%m/%d") / "rollout-a.jsonl",
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "task_started"}})
        self.assertEqual(len(self.collector(("codex",)).snapshot("r")["agents"]), 1)
        snapshot = self.collector(("codex",), codex_alive=False).snapshot("r")
        self.assertEqual((snapshot["agents"], snapshot["sources"]["codex"]), ([], "ok"))

    def test_codex_subagent_rollout_belongs_to_parent(self):
        day = self.codex / "sessions" / time.strftime("%Y/%m/%d")
        self.append(day / "rollout-t1-parent.jsonl",
                    {"timestamp": iso(), "type": "session_meta", "payload": {"id": "p1", "cwd": PROJECT, "source": "cli"}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "task_started"}})
        self.append(day / "rollout-t2-guardian.jsonl",
                    {"timestamp": iso(), "type": "session_meta", "payload": {
                        "id": "g1", "parent_thread_id": "p1", "source": {"subagent": {"other": "guardian"}}}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "task_started"}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "item_completed", "item": {
                        "type": "CommandExecution", "command": ["/bin/bash", "-lc", "git diff"], "parsed_cmd": []}}},
                    {"timestamp": iso(), "type": "event_msg", "payload": {"type": "task_complete"}})
        snapshot = self.collector(("codex",)).snapshot("r")
        self.assertEqual([a["id"] for a in snapshot["agents"]], ["codex:t1-parent"])
        agent = snapshot["agents"][0]
        self.assertEqual(agent["status"], "working")
        self.assertEqual(agent["subagents"], [{"id": "t2-guardian", "name": "guardian", "type": "guardian"}])
        self.assertEqual((agent["activity"]["tool"], agent["activity"]["target"], agent["activity"]["subagent"]), ("shell", "git", "guardian"))

    def test_old_files_are_hidden_and_outside_paths_shortened(self):
        self.session()
        self.append(self.transcripts / "s1.jsonl",
                    tool("Read", {"file_path": PROJECT + "/old.rb"}, "m1", offset=-16 * 60),
                    tool("Read", {"file_path": "/tmp/scratch/shots/crop.png"}, "m2"),
                    tool("Read", {"file_path": str(Path.home() / "notes.md")}, "m3"))
        files = [f["path"] for f in self.collector().snapshot("r")["agents"][0]["files"]]
        self.assertEqual(sorted(files), ["~/notes.md", "\u2026/crop.png"])

    def test_disabled_sources(self):
        self.session()
        snapshot = self.collector(()).snapshot("r")
        self.assertEqual(snapshot["sources"], {"claude": "disabled", "codex": "disabled"})
        self.assertEqual(snapshot["agents"], [])

    def test_serve_protocol(self):
        out = io.StringIO()
        requests = [json.dumps({"version": 1, "requestId": "a", "command": "snapshot"}),
                    json.dumps({"version": 2, "requestId": "b", "command": "snapshot"}),
                    json.dumps({"version": 1, "requestId": "c", "command": "nope"}), "{", "x" * 5000]
        collect.serve(self.collector(), io.StringIO("\n".join(requests) + "\n"), out)
        replies = [json.loads(line) for line in out.getvalue().splitlines()]
        self.assertEqual(replies[0]["requestId"], "a")
        self.assertIn("agents", replies[0])
        self.assertEqual([r.get("error") for r in replies[1:]], ["invalid request", "unknown command", "invalid request", "request too large"])

    def test_program_name(self):
        cases = {"git status": "git", "cd /x && FOO=1 make -j4": "make", "sudo -E /usr/bin/pacman -S x": "pacman",
                 "timeout 20 python3 x.py": "python3", "": ""}
        for command, expected in cases.items():
            self.assertEqual(collect.program_name(command), expected, command)
        self.assertEqual(collect.program_name(["/bin/bash", "-lc", "rg foo | head"]), "rg")


if __name__ == "__main__":
    unittest.main()
