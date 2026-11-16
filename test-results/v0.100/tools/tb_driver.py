"""Shared Test Bridge helpers; the old multi-row feeder is retired.

run_blocks.py PLAN --worktree bb-v100-salvage is the default entry point.
For one test requiring process-wide arguments only:
tb_driver.py LIST START --single-row --worktree bb-v100-salvage
run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import subprocess
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import ProxyHandler, Request, build_opener

V = Path(__file__).resolve().parent.parent
WORKTREES = V.parents[2]
DEFAULT_GODOT = "C:/Users/bligh/Android/godot/Godot_v4.7.2-stable_win64_console.exe"
TERMINAL = {"passed", "failed", "error", "cancelled", "timed_out", "interrupted", "killed"}


def options(parser):
    parser.add_argument("--worktree", default="bb-v100-salvage",
                        help="folder name under .work (default: bb-v100-salvage)")
    parser.add_argument("--godot", default=DEFAULT_GODOT)
    return parser


def configure(worktree, godot):
    if worktree in {".", ".."} or "/" in worktree or "\\" in worktree or ":" in worktree:
        raise ValueError("worktree must be a folder name")
    project = WORKTREES / worktree
    if not (project / "game/project.godot").is_file():
        raise ValueError(f"missing game/project.godot in {project}")
    return {"project": project, "godot": godot,
            "runs": project / "test-results/v0.100/runs"}


def api(config, name, args):
    origin = {"workspace": str(config["project"]), "conversation_id": "", "run_id": "",
              "lead_id": "", "label": "v100-salvage"}
    req = Request("http://127.0.0.1:7319/api/test-bridge/tool",
                  data=json.dumps({"name": name, "args": args, "origin": origin}).encode(),
                  method="POST", headers={"Content-Type": "application/json", "X-Test-Bridge": "1"})
    try:
        with build_opener(ProxyHandler({})).open(req, timeout=40) as response:
            return json.load(response)
    except HTTPError as error:
        return {"error": error.read().decode("utf-8", "replace")}


class MS(ctypes.Structure):
    _fields_ = [("l", ctypes.c_ulong), ("load", ctypes.c_ulong)] + [
        (n, ctypes.c_ulonglong) for n in ("tot", "avail", "tp", "ap", "tv", "av", "ae")]


def ram_free_pct():
    status = MS()
    status.l = ctypes.sizeof(MS)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
        raise RuntimeError("cannot read free RAM")
    return 100.0 * status.avail / status.tot


def cpu_pct():
    result = subprocess.run(
        ["powershell", "-NoProfile", "-Command",
         "(Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average"],
        capture_output=True, text=True, timeout=30, check=True)
    return float(result.stdout.strip() or 0)


def engines_running():
    # Supplemental hold only. Test Bridge owns the shared process detector/lease,
    # including renamed players; do not acquire a nested lane lease here.
    result = subprocess.run(["tasklist", "/fo", "csv", "/nh"],
                            capture_output=True, text=True, timeout=15, check=True)
    return [line.split(",")[0] for line in result.stdout.lower().splitlines()
            if "godot" in line or "unity" in line]


def log(config, message):
    config["runs"].mkdir(parents=True, exist_ok=True)
    line = time.strftime("%H:%M:%S ") + message
    print(line, flush=True)
    with (config["runs"] / "block_progress.txt").open("a", encoding="utf-8") as stream:
        stream.write(line + "\n")


def run(config, name, args):
    while True:
        ram, cpu, engines = ram_free_pct(), cpu_pct(), engines_running()
        if ram >= 20 and cpu < 95 and not engines:
            break
        log(config, f"HOLD {name}: ram_free={ram:.0f}% cpu={cpu:.0f}% engines={engines}")
        time.sleep(20)
    config["runs"].mkdir(parents=True, exist_ok=True)
    label = "v100_" + "".join(c if c.isalnum() or c in "_-" else "_" for c in name)
    label += "_" + str(time.time_ns())
    output = config["runs"] / (label + ".log")
    # Direct runner invocation replaces the absent, bb-v097-bound shell wrapper.
    # Import preparation, if needed, is a separate authorized Test Bridge job.
    command = [config["godot"], "--headless", "--audio-driver", "Dummy",
               "--path", str(config["project"] / "game"), "--log-file", str(output),
               "res://tests/runner.tscn", "--", *args, "--watchdog=170"]
    job = {"name": f"bb v0.100 {name}"[:200], "helper": "v100-salvage", "engine": "Godot",
           "command": command, "cwd": str(config["project"]), "timeout_seconds": 178}
    for argument in args:  # a missing block would only fail inside Godot and count as a failed test
        if argument.startswith("--block="):
            known = json.loads((config["project"] / "game/tests/blocks.json").read_text(encoding="utf-8-sig"))
            if argument.split("=", 1)[1] not in known:
                log(config, f"NOT SUBMITTED {name}: no such block in game/tests/blocks.json")
                return False
    while True:
        submitted = api(config, "test_bridge_submit", {"job": job})
        jid = (submitted.get("id") or (submitted.get("job") or {}).get("id")) if isinstance(submitted, dict) else None
        if jid:
            break
        text = json.dumps(submitted)
        if "Auto-kill" in text and "Blocked until" in text:
            # Cooldown after an earlier failure: wait it out instead of burning the rest of the plan.
            log(config, f"COOLDOWN {name}: {text[:300]}")
            time.sleep(60)
            continue
        log(config, f"SUBMIT REFUSED {name}: {text[:400]}")
        return False
    last_status = ""
    while True:
        state = api(config, "test_bridge_status", {"job_id": jid})
        current = state.get("job", state) if isinstance(state, dict) else {}
        status = current.get("status", "")
        if status != last_status:
            log(config, f"{status.upper() or 'UNKNOWN'} {name}: job {jid}")
            last_status = status
        if status in TERMINAL:
            break
        time.sleep(5)
    data = output.read_text(encoding="utf-8", errors="replace") if output.is_file() else ""
    failures, errors = data.count("FAIL"), data.count("SCRIPT ERROR")
    expected = []
    for argument in args:
        if argument.startswith("--block="):
            blocks = json.loads((config["project"] / "game/tests/blocks.json").read_text(encoding="utf-8-sig"))
            expected.extend(blocks.get(argument.split("=", 1)[1], []))
        elif argument.startswith(("--test=", "--tests=")):
            expected.extend(argument.split("=", 1)[1].split(","))
    complete = bool(expected) and all(f"== {path}: PASS ==" in data for path in expected)
    ok = status == "passed" and complete and failures == 0 and errors == 0
    outcome = "PASS" if ok else ("FAIL" if status == "passed" else status.upper())
    record = f"{label}|{config['project'].name}|{' '.join(args)}|tb={status}|fails={failures}|script_err={errors}|log={output.name}"
    with (config["runs"] / "results.txt").open("a", encoding="utf-8") as stream:
        stream.write(record + "\n")
    log(config, f"{outcome} {name}: {record}")
    return ok


def main():
    parser = options(argparse.ArgumentParser(description=__doc__))
    parser.add_argument("plan")
    parser.add_argument("start", type=int)
    parser.add_argument("count", type=int, nargs="?", default=1)
    parser.add_argument("--single-row", action="store_true")
    args = parser.parse_args()
    if not args.single_row or args.count != 1:
        parser.error("the multi-row feeder is retired; use run_blocks.py, or --single-row with count 1")
    rows = [line.strip() for line in Path(args.plan).read_text(encoding="utf-8-sig").splitlines()
            if line.strip() and not line.lstrip().startswith("#")]
    if not 1 <= args.start <= len(rows):
        parser.error("start must select an existing row")
    config = configure(args.worktree, args.godot)
    parts = rows[args.start - 1].split()
    test, extra = parts[0], [arg for arg in parts[1:] if not arg.startswith("--watchdog=")]
    return 0 if run(config, test, [f"--test=res://tests/{test}.gd", *extra]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
