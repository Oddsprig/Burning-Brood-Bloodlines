"""Feed older-test rows to Test Bridge one at a time; stop at the first failure.

Usage: python tb_driver.py LIST START [COUNT]
LIST rows: "<test> [args...]" (lines starting with # are skipped). START is 1-based over non-comment rows.
Each row runs via run_one_ref.sh (one Godot process, headless, <3 min) through the shared Test Bridge lane.
Holds tests while free RAM < 20% or CPU >= 95%. Progress: runs/driver_progress.txt.
"""
from __future__ import annotations
import ctypes, json, subprocess, sys, time
from pathlib import Path
from urllib.request import Request, build_opener, ProxyHandler
from urllib.error import HTTPError

V = Path(__file__).resolve().parent.parent
W = V.parent.parent
import os
PROBE = os.environ.get("TB_PROBE") == "1"  # probe mode: always-exit-0 runner, labels "probe_", never a pass
TOOL = (V / "tools" / ("run_one_probe.sh" if PROBE else "run_one_ref.sh")).as_posix()
RESULTS = V / "runs" / "results.txt"
PROG = V / "runs" / "driver_progress.txt"
BASH = "C:/Program Files/Git/bin/bash.exe"
ORIGIN = {"workspace": str(W), "conversation_id": "", "run_id": "", "lead_id": "", "label": "claude-lead"}


def api(name, args):
    req = Request("http://127.0.0.1:7319/api/test-bridge/tool",
                  data=json.dumps({"name": name, "args": args, "origin": ORIGIN}).encode(), method="POST",
                  headers={"Content-Type": "application/json", "X-Test-Bridge": "1"})
    try:
        with build_opener(ProxyHandler({})).open(req, timeout=40) as r:
            return json.load(r)
    except HTTPError as e:
        return {"error": e.read().decode("utf-8", "replace")}


class MS(ctypes.Structure):
    _fields_ = [("l", ctypes.c_ulong), ("load", ctypes.c_ulong)] + [(n, ctypes.c_ulonglong) for n in
                ("tot", "avail", "tp", "ap", "tv", "av", "ae")]


def ram_free_pct():
    m = MS(); m.l = ctypes.sizeof(MS); ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    return 100.0 * m.avail / m.tot


def cpu_pct():
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command",
                              "(Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average"],
                             capture_output=True, text=True, timeout=30).stdout.strip()
        return float(out or 0)
    except Exception:
        return 0.0


def engines_running():
    out = subprocess.run(["tasklist", "/fo", "csv", "/nh"], capture_output=True, text=True).stdout.lower()
    return [l.split(",")[0] for l in out.splitlines() if "godot" in l or "unity" in l]


def log(msg):
    line = time.strftime("%H:%M:%S ") + msg
    print(line, flush=True)
    with PROG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def main():
    rows = [l.strip() for l in Path(sys.argv[1]).read_text(encoding="utf-8-sig").splitlines()
            if l.strip() and not l.strip().startswith("#")]
    start = int(sys.argv[2]); count = int(sys.argv[3]) if len(sys.argv) > 3 else len(rows)
    for i in range(start, min(len(rows), start - 1 + count) + 1):
        parts = rows[i - 1].split()
        test, extra = parts[0], [a for a in parts[1:] if not a.startswith("--watchdog=")]
        label = "v100_b_%03d_%s%s" % (i, test, ("_" + "_".join(a.split("=")[-1] for a in extra))[:40] if extra else "")
        label = "".join(c if c.isalnum() or c in "_-" else "_" for c in label)
        if PROBE:
            label = "probe_" + label
        while True:
            r, c, e = ram_free_pct(), cpu_pct(), engines_running()
            if r >= 20 and c < 95 and not e:
                break
            log(f"HOLD row {i}: ram_free={r:.0f}% cpu={c:.0f}% engines={e}"); time.sleep(20)
        job = {"name": f"bb v0.100 older #{i} {rows[i-1]}"[:200], "helper": "claude-lead", "engine": "Godot",
               "command": [BASH, TOOL, "bb-v097", f"--test=res://tests/{test}.gd", label, *extra],
               "cwd": str(W), "timeout_seconds": 178}
        sub = api("test_bridge_submit", {"job": job})
        jid = (sub.get("id") or (sub.get("job") or {}).get("id")) if isinstance(sub, dict) else None
        if not jid:
            log(f"SUBMIT REFUSED row {i} {rows[i-1]}: {json.dumps(sub)[:600]}"); sys.exit(3)
        t0 = time.time()
        while True:
            time.sleep(5)
            st = api("test_bridge_status", {"job_id": jid})
            j = st.get("job", st) if isinstance(st, dict) else {}
            if j.get("status") in ("passed", "failed", "error", "cancelled", "timed_out", "interrupted", "killed"):
                break
            if time.time() - t0 > 900:
                log(f"STUCK row {i} job {jid}"); sys.exit(4)
        last = RESULTS.read_text(encoding="utf-8").splitlines()[-1]
        ok = j.get("status") == "passed" and last.startswith(label + "|") and "|rc=0|fails=0|script_err=0" in last
        if PROBE:
            log(f"PROBE row {i} {rows[i-1]} :: {last}")
            continue
        log(f"{'PASS' if ok else 'FAIL'} row {i} {rows[i-1]} run={time.time()-t0:.0f}s tb={j.get('status')} :: {last}")
        if not ok:
            # Owner (Nov 15, 5:50 PM): stop-on-first-failure is not their rule. Log the failed row and keep going;
            # it is fixed (Sol + notes-free review) and rerun separately.
            with (V / "runs" / "failed_rows.txt").open("a", encoding="utf-8") as f:
                f.write(f"{i}\t{rows[i-1]}\t{last}\n")
    log("DONE")


if __name__ == "__main__":
    # Retired as the default (owner, Nov 15 2026): one Godot launch per test is not how this project tests.
    # Use tools/run_blocks.py with a block plan (see HOW TO TEST in AGENTS.md). Single-row mode needs --single-row.
    if "--single-row" not in sys.argv:
        sys.exit("tb_driver.py is the old one-test-per-launch feeder. Use tools/run_blocks.py (HOW TO TEST in AGENTS.md), "
                 "or pass --single-row for a test that needs its own process.")
    sys.argv.remove("--single-row")
    main()
