"""Run a targeted block plan, one headless Godot process per block through Test Bridge.
Usage: python run_blocks.py PLAN [--worktree bb-v100-salvage] [--godot PATH]
Each plan line is NAME<TAB>--block=NAME (or --tests=res://tests/a.gd,res://tests/b.gd).
run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
"""
import argparse
from pathlib import Path

import tb_driver as tb


def main():
    parser = tb.options(argparse.ArgumentParser(description=__doc__))
    parser.add_argument("plan")
    args = parser.parse_args()
    config = tb.configure(args.worktree, args.godot)
    plan = []
    for line in Path(args.plan).read_text(encoding="utf-8-sig").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t", 1)
        if len(parts) != 2 or not parts[0] or not parts[1].startswith(("--block=", "--tests=")) or any(c.isspace() for c in parts[1]):
            parser.error(f"invalid block-plan line: {line!r}")
        plan.append(parts)
    if not plan:
        parser.error("block plan is empty")
    failed = 0
    for name, argument in plan:
        if not tb.run(config, name, [argument]):
            failed += 1
            break  # Test Bridge refuses new jobs for 10 minutes after a failure: fix, then rerun from this block
    tb.log(config, f"DONE blocks={len(plan)} failures={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
