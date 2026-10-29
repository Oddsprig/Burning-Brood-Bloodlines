"""Read-only aggregation of balance_v070 JSON shards; prints JSON to stdout."""
import argparse
import json
from pathlib import Path


def summarize(directory, phase, allow_partial=False):
    reports = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(directory.glob("*.json"))]
    reports = [r for r in reports if r.get("phase") == phase and "suite" in r]
    expanded = []
    for report in reports:
        if report["suite"] != "sweep":
            expanded.append(report)
            continue
        for family in ["race", "unit", "mount", "roster_matrix"]:
            part = dict(report)
            part["suite"] = family
            part["rows"] = [row for row in report["rows"] if row["suite"] == family]
            part["selected_cases"] = len(part["rows"]) // 2
            part["shared_run"] = True
            expanded.append(part)
    reports = expanded
    if not reports:
        raise ValueError(f"{phase}: no survey results")
    required = {"race", "unit", "mount", "roster_matrix", "campaign"}
    missing = required - {r["suite"] for r in reports}
    if missing and not allow_partial:
        raise ValueError(f"{phase}: missing suites: {sorted(missing)}")
    fingerprints = {json.dumps(r["data_sha256"], sort_keys=True) for r in reports}
    if len(fingerprints) != 1:
        raise ValueError(f"{phase}: mixed data fingerprints across suites")
    output = {"phase": phase, "suites": {}, "incomplete": sorted(missing), "failed_attempts": [
        {"suite": r["suite"], "shard": r["shard"], "errors": r.get("errors", [])}
        for r in reports if not r["complete"]]}
    for suite in sorted({r["suite"] for r in reports}):
        shards = [r for r in reports if r["suite"] == suite and r["complete"]]
        if not shards:
            output["incomplete"].append(suite)
            if not allow_partial:
                raise ValueError(f"{phase}/{suite}: no complete shards")
            continue
        declared = {r["shards"] for r in shards}
        if len(declared) != 1:
            raise ValueError(f"{phase}/{suite}: inconsistent shard counts")
        expected = declared.pop()
        if len({r["shard"] for r in shards}) != len(shards):
            raise ValueError(f"{phase}/{suite}: duplicate shard; use a fresh phase name")
        if len(shards) != expected or not all(r["complete"] for r in shards):
            output["incomplete"].append(suite)
            if not allow_partial:
                raise ValueError(f"{phase}/{suite}: incomplete survey")
        signatures = {json.dumps(r["data_sha256"], sort_keys=True) for r in shards}
        if len(signatures) != 1:
            raise ValueError(f"{phase}/{suite}: mixed data fingerprints")
        if suite == "campaign":
            output["suites"][suite] = shards[0]
            continue
        category = "unit" if suite in ["roster", "roster_matrix"] else suite
        groups = {}
        mirrors = 0
        capped = 0
        seen = set()
        duplicate_mirrors = 0
        for report in shards:
            if report["complete"] and len(report["rows"]) != report["selected_cases"] * 2:
                raise ValueError("a complete shard omitted battles")
            for row in report["rows"]:
                identity = (row["a"]["id"], row["b"]["id"], row["seed"], row["swap"])
                if identity in seen:
                    # The initial baseline repeated the reference's own mirror.
                    # It never contributes to cross-match balance estimates.
                    if row["mirror"]:
                        duplicate_mirrors += 1
                        continue
                    raise ValueError("duplicate seeded battle")
                seen.add(identity)
                if row["cost_match"]["gap"] > report["max_cost_gap"] + 1e-9:
                    raise ValueError("unequal-cost battle")
                capped += int(row["tick_capped"])
                if row["mirror"]:
                    mirrors += 1
                    continue
                # Native rosters are each tested against the same reference.
                # Count candidate trials; do not overweight the reference's opponents.
                for side in ([0] if suite == "roster" else [0, 1]):
                    profile = row["a" if side == 0 else "b"]
                    key = profile[category]
                    st = groups.setdefault(key, {"n": 0, "won": 0, "draw": 0, "kills": 0,
                                                  "damage_dealt": 0.0, "damage_taken": 0.0,
                                                  "value_killed": 0.0, "cost_spent": 0.0})
                    st["n"] += 1
                    for field in st:
                        if field != "n":
                            st[field] += row["sides"][side][field]
        for st in groups.values():
            st["win_pct"] = round(100 * st["won"] / st["n"], 2)
            st["score_pct"] = round(100 * (st["won"] + st["draw"] / 2) / st["n"], 2)
            st["efficiency"] = round(st["value_killed"] / st["cost_spent"], 4)
            for field in ["damage_dealt", "damage_taken"]:
                st[field + "_per_battle"] = round(st[field] / st["n"], 3)
        output["suites"][suite] = {"battles": len(seen) + duplicate_mirrors, "mirrors": mirrors, "duplicate_mirrors": duplicate_mirrors, "tick_capped": capped,
                                    "elapsed_ms": None if any(r.get("shared_run") for r in shards) else sum(r["elapsed_ms"] for r in shards), "groups": groups}
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", required=True)
    parser.add_argument("--allow-partial", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    print(json.dumps(summarize(root / "test-results" / "balance_v070", args.phase, args.allow_partial), indent=2))
