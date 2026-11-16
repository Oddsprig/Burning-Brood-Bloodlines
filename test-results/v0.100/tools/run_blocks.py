"""Run test blocks: one headless Godot launch per block through runner.gd's existing --tests= list (or --block=NAME
from blocks.json), submitted to Test Bridge one at a time. Usage: python tools/run_blocks.py runs/blocks_v100.txt
Each line of the plan: BLOCK_NAME<TAB>--tests=res://tests/a.gd,res://tests/b.gd   (or --block=name)."""
import sys, time, json
from pathlib import Path
V = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(V / "tools"))
import tb_driver as tb
PROG = V / "runs" / "block_progress.txt"
RESULTS = V / "runs" / "results.txt"
def log(s):
    line = time.strftime("%H:%M:%S ") + s
    with PROG.open("a", encoding="utf-8") as f: f.write(line + "\n")
    print(line, flush=True)
plan = [l.split("\t", 1) for l in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")]
for name, arg in plan:
    while True:
        r, c, e = tb.ram_free_pct(), tb.cpu_pct(), tb.engines_running()
        if r >= 20 and c < 95 and not e: break
        log(f"HOLD block {name}: ram_free={r:.0f}% cpu={c:.0f}% engines={e}"); time.sleep(20)
    label = "v100_blk_" + name
    job = {"name": f"bb v0.100 block {name}"[:200], "helper": "claude-lead", "engine": "Godot",
           "command": [tb.BASH, tb.TOOL, "bb-v097", arg, label], "cwd": str(tb.W), "timeout_seconds": 178}
    sub = tb.api("test_bridge_submit", {"job": job})
    jid = (sub.get("id") or (sub.get("job") or {}).get("id")) if isinstance(sub, dict) else None
    if not jid: log(f"SUBMIT REFUSED block {name}: {json.dumps(sub)[:400]}"); continue
    log(f"START block {name} job {jid}")
    t0 = time.time()
    while True:
        time.sleep(5)
        st = tb.api("test_bridge_status", {"job_id": jid}); j = st.get("job", st) if isinstance(st, dict) else {}
        if j.get("status") in ("passed", "failed", "error", "cancelled", "timed_out", "interrupted", "killed"): break
    last = RESULTS.read_text(encoding="utf-8").splitlines()[-1]
    ok = j.get("status") == "passed" and last.startswith(label + "|") and "|rc=0|fails=0|script_err=0" in last
    log(f"{'PASS' if ok else 'FAIL'} block {name} run={time.time()-t0:.0f}s tb={j.get('status')} :: {last}")
log("DONE")
