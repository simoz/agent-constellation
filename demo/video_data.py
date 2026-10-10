"""Precompute collector snapshots of demo/scenario.py on a simulated clock.

Usage: python3 -B demo/video_data.py OUTPUT.json [--seconds N]

The launch video renders frames slower than real time, so it replays these
snapshots instead of running the collector: one snapshot per simulated second,
produced by the real collector reading the scenario's fictional session files.
"""

import argparse
import json
import sys
import tempfile
import time
from pathlib import Path

demo = Path(__file__).resolve().parent
sys.path.insert(0, str(demo))
sys.path.insert(0, str(demo.parent / "tools"))
import collect  # noqa: E402
import scenario  # noqa: E402

clock = [time.time()]
# Every module reads time through time.time(); file mtimes follow scenario.append.
time.time = lambda: clock[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("output", type=Path)
    parser.add_argument("--seconds", type=int, default=90)
    args = parser.parse_args()
    scenario.PID = __import__("os").getpid()
    with tempfile.TemporaryDirectory(prefix="constellation-video.") as folder:
        root = Path(folder)
        steps, codex = scenario.timeline(root / "claude", root / "codex", 0)
        collector = collect.Collector(root / "claude", root / "codex", {"claude", "codex"}, 30)
        start, snapshots, index = clock[0], [], 0
        for second in range(args.seconds + 1):
            while index < len(steps) and steps[index][0] <= second:
                # Spread actions of the same second so their timestamps stay ordered.
                clock[0] = start + steps[index][0] + 0.01 * index
                steps[index][1]()
                index += 1
            clock[0] = start + second + 0.5
            snapshots.append(collector.snapshot("video"))
        codex.lock.close()
    args.output.write_text(json.dumps(snapshots, separators=(",", ":")))
    print(f"{len(snapshots)} snapshots -> {args.output}")


if __name__ == "__main__":
    main()
