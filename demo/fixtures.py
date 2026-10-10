"""Write fictional Claude Code and Codex session files for demos and screenshots.

Usage: python3 -B demo/fixtures.py OUTPUT_DIR PID [--scene live|wait]

PID must be a running process that outlives the capture (demo/run starts one):
Claude Code session records are shown only while their process is alive.
Codex threads are shown only while their lock file, printed on stdout, is held
(demo/run holds it with flock).
Every project, path and command here is invented.
"""

import json
import sys
import time
from pathlib import Path

HOME = "/home/demo"


def iso(seconds_ago):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - seconds_ago))


def start_time(pid):
    with open(f"/proc/{pid}/stat", "rb") as handle:
        return handle.read().rsplit(b")", 1)[1].split()[19].decode()


def write(path, entries):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(entry) + "\n" for entry in entries))


def tool(seconds_ago, name, data, model="claude-opus-5-5", tokens=180, serial=[0]):
    serial[0] += 1
    return {"type": "assistant", "timestamp": iso(seconds_ago),
            "message": {"id": f"msg_{serial[0]}", "model": model, "usage": {"output_tokens": tokens},
                        "content": [{"type": "tool_use", "id": f"tool_{serial[0]}", "name": name, "input": data}]}}


def claude_session(root, pid, session_id, project, status, entries, subagents=(), **extra):
    cwd = f"{HOME}/work/{project}"
    record = {"pid": pid, "procStart": start_time(pid), "sessionId": session_id, "cwd": cwd, "status": status,
              "statusUpdatedAt": int(time.time() * 1000), "kind": "interactive", **extra}
    (root / "sessions").mkdir(parents=True, exist_ok=True)
    (root / "sessions" / f"{session_id}.json").write_text(json.dumps(record))
    folder = root / "projects" / cwd.replace("/", "-")
    write(folder / f"{session_id}.jsonl", [entry(cwd) for entry in entries])
    for key, meta, sub_entries in subagents:
        write(folder / session_id / "subagents" / f"{key}.jsonl", [entry(cwd) for entry in sub_entries])
        (folder / session_id / "subagents" / f"{key}.meta.json").write_text(json.dumps(meta))


def edit(seconds_ago, path, added, removed, **kw):
    return lambda cwd: tool(seconds_ago, "Edit", {"file_path": f"{cwd}/{path}", "old_string": "\n" * (removed - 1) + "x",
                                                  "new_string": "\n" * (added - 1) + "y"}, **kw)


def read(seconds_ago, path, **kw):
    return lambda cwd: tool(seconds_ago, "Read", {"file_path": f"{cwd}/{path}"}, **kw)


def other(seconds_ago, name, data, **kw):
    return lambda cwd: tool(seconds_ago, name, data, **kw)


def main():
    output, pid = Path(sys.argv[1]), int(sys.argv[2])
    scene = sys.argv[4] if len(sys.argv) > 4 and sys.argv[3] == "--scene" else "live"
    claude = output / "claude"
    shop = [read(280 - i * 9, path) for i, path in enumerate(
        ["app/models/order.rb", "config/routes.rb", "db/schema.rb", "app/views/orders/_form.html.erb"])]
    shop += [edit(200 - i * 14, path, a, r) for i, (path, a, r) in enumerate([
        ("app/models/order.rb", 12, 3), ("app/controllers/orders_controller.rb", 8, 2), ("app/models/order.rb", 4, 1),
        ("db/migrate/20261010_add_shipped_at.rb", 14, 1), ("app/mailers/order_mailer.rb", 9, 0), ("app/models/order.rb", 3, 2),
        ("spec/models/order_spec.rb", 22, 0)])]
    shop += [other(40, "Bash", {"command": "bundle exec rspec spec/models"}),
             other(12, "Agent", {"subagent_type": "Explore", "description": "Find status changes"}),
             edit(3, "spec/mailers/order_mailer_spec.rb", 18, 0)]
    explore = ("agent-explore-1", {"agentType": "Explore", "name": "Explore"},
               [other(8 - i, "Grep", {"pattern": "status"}, model="claude-haiku-5-5") for i in range(4)]
               + [read(2, "app/services/checkout.rb", model="claude-haiku-5-5")])
    plan = ("agent-plan-2", {"agentType": "Plan", "name": "Plan"}, [read(4, "config/routes.rb")])
    claude_session(claude, pid, "a1b2c3d4-0000-4000-8000-000000000001", "shop", "busy", shop, (explore, plan))
    poems = [read(250 - i * 20, path, model="claude-sonnet-5-5") for i, path in enumerate(
        ["app/models/poem.rb", "app/models/author.rb", "app/controllers/poems_controller.rb", "db/seeds.rb", "lib/search.rb"])]
    poems += [other(60, "Grep", {"pattern": "has_many :poems"}, model="claude-sonnet-5-5"),
              edit(30, "app/models/poem.rb", 6, 2, model="claude-sonnet-5-5"),
              other(5, "Bash", {"command": "bin/rails db:migrate RAILS_ENV=staging"}, model="claude-sonnet-5-5")]
    if scene == "wait":
        claude_session(claude, pid, "a1b2c3d4-0000-4000-8000-000000000002", "poems", "waiting", poems, waitingFor="permission")
    else:
        claude_session(claude, pid, "a1b2c3d4-0000-4000-8000-000000000002", "poems", "busy", poems[:-1])
    day = output / "codex" / "sessions" / time.strftime("%Y/%m/%d")
    cwd = f"{HOME}/work/recipes"
    events = [{"timestamp": iso(300), "type": "session_meta", "payload": {"id": "0000demo", "cwd": cwd}},
              {"timestamp": iso(300), "type": "event_msg", "payload": {"type": "thread_settings_applied", "thread_settings": {"model": "gpt-5-codex"}}},
              {"timestamp": iso(290), "type": "event_msg", "payload": {"type": "task_started"}}]
    for i, path in enumerate(["app/services/recipe_scaler.rb", "app/models/ingredient.rb", "test/services/recipe_scaler_test.rb", "app/models/recipe.rb"]):
        events.append({"timestamp": iso(240 - i * 30), "type": "event_msg", "payload": {"type": "item_completed", "item": {
            "type": "CommandExecution", "command": ["/bin/bash", "-lc", f"sed -n 1,200p {path}"], "parsed_cmd": [{"type": "read", "path": f"{cwd}/{path}"}]}}})
    for i, (path, diff) in enumerate([("app/services/recipe_scaler.rb", "+a\n+b\n+c\n-d\n"), ("app/models/ingredient.rb", "+a\n-b\n"),
                                      ("app/services/recipe_scaler.rb", "+a\n+b\n")]):
        events.append({"timestamp": iso(100 - i * 25), "type": "event_msg", "payload": {"type": "item_completed", "item": {
            "type": "FileChange", "changes": {f"{cwd}/{path}": {"type": "update", "unified_diff": diff}}}}})
        events.append({"timestamp": iso(100 - i * 25), "type": "event_msg", "payload": {"type": "token_count", "info": {"last_token_usage": {"output_tokens": 900}}}})
    events.append({"timestamp": iso(6), "type": "event_msg", "payload": {"type": "item_completed", "item": {
        "type": "CommandExecution", "command": ["/bin/bash", "-lc", "bin/rails test test/services"], "parsed_cmd": [{"type": "unknown"}]}}})
    write(day / "rollout-2026-10-10T10-00-00-0000demo.jsonl", events)
    lock = output / "codex" / "thread-writer-locks" / "0000demo.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    lock.touch()
    print(lock)


if __name__ == "__main__":
    main()
