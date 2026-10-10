"""Play a scripted session timeline on fictional Rails applications, for videos.

Usage: python3 -B demo/scenario.py OUTPUT_DIR [--speed FACTOR] [--once]

Writes Claude Code and Codex session files under OUTPUT_DIR as the agents would,
one step at a time, and loops until interrupted. This process stands in for the
agents: Claude Code records name its PID, and it holds the Codex thread lock.
Every project, path and command here is invented.
"""

import argparse
import fcntl
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fixtures import HOME, start_time, tool  # noqa: E402

LOOP_SECONDS = 120
PID = 0


def append(path, entry):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as handle:
        handle.write(json.dumps(entry) + "\n")


class Claude:
    def __init__(self, root, session_id, project, model):
        self.root, self.session_id, self.model = root, session_id, model
        self.cwd = f"{HOME}/work/{project}"
        self.folder = root / "projects" / self.cwd.replace("/", "-")
        self.transcript = self.folder / f"{session_id}.jsonl"
        self.subagents = {}

    def status(self, status, waiting_for=""):
        record = {"pid": PID, "procStart": start_time(PID), "sessionId": self.session_id, "cwd": self.cwd,
                  "status": status, "statusUpdatedAt": int(time.time() * 1000), "kind": "interactive"}
        if waiting_for:
            record["waitingFor"] = waiting_for
        (self.root / "sessions").mkdir(parents=True, exist_ok=True)
        (self.root / "sessions" / f"{self.session_id}.json").write_text(json.dumps(record))

    def call(self, name, data, subagent=None, tokens=220):
        target = self.transcript
        model = self.model
        if subagent:
            target = self.folder / self.session_id / "subagents" / f"agent-{subagent.lower()}.jsonl"
            if subagent not in self.subagents:
                self.subagents[subagent] = True
                target.parent.mkdir(parents=True, exist_ok=True)
                target.with_name(target.stem + ".meta.json").write_text(json.dumps({"agentType": subagent, "name": subagent}))
            model = "claude-haiku-5-5"
        append(target, tool(0, name, data, model=model, tokens=tokens))

    def read(self, path, subagent=None):
        self.call("Read", {"file_path": f"{self.cwd}/{path}"}, subagent)

    def edit(self, path, added, removed):
        self.call("Edit", {"file_path": f"{self.cwd}/{path}", "old_string": "\n" * (removed - 1) + "x",
                           "new_string": "\n" * (added - 1) + "y"}, tokens=640)

    def write(self, path, lines):
        self.call("Write", {"file_path": f"{self.cwd}/{path}", "content": "\n" * (lines - 1) + "x"}, tokens=900)

    def grep(self, pattern, subagent=None):
        self.call("Grep", {"pattern": pattern}, subagent)

    def bash(self, command):
        self.call("Bash", {"command": command})

    def spawn(self, kind, description):
        self.call("Agent", {"subagent_type": kind, "description": description})


class Codex:
    def __init__(self, root, thread, project):
        self.cwd = f"{HOME}/work/{project}"
        day = root / "sessions" / time.strftime("%Y/%m/%d")
        self.rollout = day / f"rollout-{time.strftime('%Y-%m-%dT%H-%M-%S')}-{thread}.jsonl"
        lock = root / "thread-writer-locks" / f"{thread}.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        # Codex holds this lock while the thread is open; so does the demo.
        self.lock = lock.open("w")
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        self.event("session_meta", {"id": thread, "cwd": self.cwd, "source": "cli"})
        self.event("event_msg", {"type": "thread_settings_applied", "thread_settings": {"model": "gpt-5-codex"}})

    def event(self, kind, payload):
        append(self.rollout, {"timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()), "type": kind, "payload": payload})

    def item(self, item, tokens=500):
        self.event("event_msg", {"type": "item_completed", "item": item})
        self.event("event_msg", {"type": "token_count", "info": {"last_token_usage": {"output_tokens": tokens}}})

    def task(self, started):
        self.event("event_msg", {"type": "task_started" if started else "task_complete"})

    def read(self, path):
        self.item({"type": "CommandExecution", "command": ["/bin/bash", "-lc", f"sed -n 1,200p {path}"],
                   "parsed_cmd": [{"type": "read", "path": f"{self.cwd}/{path}"}]})

    def patch(self, path, added, removed):
        diff = "@@\n" + "+x\n" * added + "-y\n" * removed
        self.item({"type": "FileChange", "changes": {f"{self.cwd}/{path}": {"type": "update", "unified_diff": diff}}}, 1200)

    def shell(self, command):
        self.item({"type": "CommandExecution", "command": ["/bin/bash", "-lc", command], "parsed_cmd": [{"type": "unknown"}]})


def timeline(claude_dir, codex_dir, loop):
    """(second, action) pairs for one loop; sessions persist across loops."""
    shop = Claude(claude_dir, "d3m0a1b2-0000-4000-8000-000000000001", "shop", "claude-opus-5-5")
    bookings = Claude(claude_dir, "d3m0a1b2-0000-4000-8000-000000000002", "bookings", "claude-sonnet-5-5")
    invoices = Claude(claude_dir, "d3m0a1b2-0000-4000-8000-000000000003", "invoices", "claude-opus-5-5")
    recipes = Codex(codex_dir, f"d3m0c0de-{loop:04d}", "recipes")
    steps = [
        (0, lambda: shop.status("busy")), (0, lambda: bookings.status("busy")), (0, lambda: recipes.task(True)),
        (1, lambda: shop.read("app/models/order.rb")), (2, lambda: bookings.grep("has_many :reservations")),
        (3, lambda: recipes.read("app/models/recipe.rb")), (4, lambda: shop.read("app/models/line_item.rb")),
        (5, lambda: bookings.read("app/models/reservation.rb")), (6, lambda: shop.read("config/routes.rb")),
        (7, lambda: recipes.read("app/services/recipe_scaler.rb")), (8, lambda: bookings.read("app/models/room.rb")),
        (9, lambda: shop.spawn("Explore", "Find where orders change status")),
    ]
    # The Explore subagent searches while the main agent keeps reading.
    for i, (pattern, path) in enumerate([("status:", "app/models/order.rb"), ("aasm", "app/services/checkout.rb"),
                                         ("shipped_at", "db/schema.rb"), ("OrderMailer", "app/mailers/order_mailer.rb")]):
        steps += [(10 + i * 2, lambda p=pattern: shop.grep(p, "Explore")), (11 + i * 2, lambda p=path: shop.read(p, "Explore"))]
    steps += [
        (11, lambda: recipes.read("app/models/ingredient.rb")), (12, lambda: bookings.read("app/controllers/reservations_controller.rb")),
        (14, lambda: recipes.read("test/services/recipe_scaler_test.rb")), (15, lambda: bookings.edit("app/models/reservation.rb", 9, 2)),
        (18, lambda: recipes.patch("app/services/recipe_scaler.rb", 14, 4)), (19, lambda: bookings.write("app/validators/overlap_validator.rb", 24)),
        (20, lambda: shop.edit("app/models/order.rb", 12, 3)), (22, lambda: shop.edit("app/services/checkout.rb", 8, 2)),
        (23, lambda: recipes.patch("app/models/ingredient.rb", 5, 1)), (24, lambda: bookings.edit("app/models/reservation.rb", 3, 1)),
        (25, lambda: shop.write("db/migrate/20261010120000_add_shipped_at_to_orders.rb", 14)),
        (27, lambda: recipes.shell("bin/rails test test/services")), (28, lambda: shop.edit("app/models/order.rb", 4, 1)),
        # Bookings stops for permission: its core and the bar turn red.
        (30, lambda: bookings.status("waiting", "permission")),
        (31, lambda: shop.edit("app/mailers/order_mailer.rb", 9, 0)), (33, lambda: recipes.patch("app/services/recipe_scaler.rb", 6, 2)),
        (34, lambda: shop.write("app/views/order_mailer/shipped.html.erb", 18)), (36, lambda: recipes.read("app/models/recipe.rb")),
        (37, lambda: shop.edit("app/models/order.rb", 3, 2)), (39, lambda: recipes.shell("bin/rails test test/services")),
        (42, lambda: bookings.status("busy")), (42, lambda: bookings.bash("bin/rails db:migrate")),
        (44, lambda: bookings.edit("db/schema.rb", 6, 0)), (46, lambda: bookings.write("test/models/reservation_test.rb", 31)),
        (45, lambda: shop.spawn("Plan", "Plan the shipping notification")),
        (46, lambda: shop.read("app/models/order.rb", "Plan")), (48, lambda: shop.read("config/routes.rb", "Plan")),
        (50, lambda: shop.read("app/controllers/orders_controller.rb", "Plan")),
        (48, lambda: recipes.patch("app/controllers/recipes_controller.rb", 7, 3)), (51, lambda: recipes.task(False)),
        # A new session joins halfway.
        (55, lambda: invoices.status("busy")), (56, lambda: invoices.read("app/models/invoice.rb")),
        (57, lambda: shop.edit("app/controllers/orders_controller.rb", 8, 2)), (58, lambda: invoices.read("app/models/payment.rb")),
        (59, lambda: bookings.bash("bin/rails test test/models")), (60, lambda: invoices.grep("def total")),
        (61, lambda: shop.write("spec/models/order_spec.rb", 22)), (62, lambda: invoices.read("app/services/invoice_pdf.rb")),
        (64, lambda: invoices.edit("app/models/invoice.rb", 11, 4)), (65, lambda: shop.bash("bundle exec rspec spec/models")),
        (66, lambda: recipes.task(True)), (67, lambda: recipes.read("app/views/recipes/show.html.erb")),
        (68, lambda: invoices.write("app/jobs/send_invoice_job.rb", 19)), (70, lambda: shop.write("spec/mailers/order_mailer_spec.rb", 18)),
        (71, lambda: recipes.patch("app/views/recipes/show.html.erb", 9, 5)), (72, lambda: invoices.edit("app/services/invoice_pdf.rb", 7, 3)),
        (73, lambda: bookings.edit("app/controllers/reservations_controller.rb", 5, 2)), (75, lambda: shop.bash("bundle exec rspec")),
        (76, lambda: invoices.write("test/jobs/send_invoice_job_test.rb", 26)), (78, lambda: recipes.shell("bin/rails test")),
        (79, lambda: bookings.status("idle")), (80, lambda: invoices.bash("bin/rails test test/jobs")),
        (82, lambda: shop.edit("app/models/order.rb", 2, 1)), (84, lambda: invoices.edit("app/models/invoice.rb", 3, 1)),
        (86, lambda: recipes.task(False)), (88, lambda: shop.bash("bundle exec rspec spec/mailers")),
        (90, lambda: invoices.bash("bin/rails test")), (95, lambda: shop.status("idle")), (100, lambda: invoices.status("idle")),
    ]
    return sorted(steps, key=lambda step: step[0]), recipes


def main():
    global PID
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("output", type=Path)
    parser.add_argument("--speed", type=float, default=1.0, help="play faster (2) or slower (0.5)")
    parser.add_argument("--once", action="store_true", help="play one loop and exit")
    args = parser.parse_args()
    PID = os.getpid()
    claude_dir, codex_dir = args.output / "claude", args.output / "codex"
    loop = 0
    try:
        while True:
            steps, codex = timeline(claude_dir, codex_dir, loop)
            started = time.monotonic()
            for second, action in steps:
                delay = started + second / args.speed - time.monotonic()
                if delay > 0:
                    time.sleep(delay)
                action()
            time.sleep(max(0, started + LOOP_SECONDS / args.speed - time.monotonic()))
            codex.lock.close()
            loop += 1
            if args.once:
                break
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
