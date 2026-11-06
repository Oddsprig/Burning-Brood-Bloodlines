"""Strict, standard-library aggregator for explicit v093 native checkpoint paths.

No engine, discovery, retries, artifact rewriting, or balance pass thresholds.
--self-test uses synthetic IN-MEMORY schema fixtures, never native-result claims.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
import re
import sys

RACES = ("human", "orc", "goblin", "moon_elf", "dwarf", "high_elf", "dark_elf")
ROLES = ("sword", "spear", "archer")
SEEDS = (93017, 100936)
SCHEMA = "balance_engagements_v093/1"
CONTRACT_SCHEMA = "engagement_contract_v093/1"
DONE = {"complete", "complete_censored"}
PARTIAL = {"running", "incomplete_wall", "unmatched", "setup_error", "contract_error", "checkpoint_error"}
PRE_CHECKS = {"continuity_from_previous", "original_unit_body_references", "original_rider_dictionary",
              "picks_fit_no_corpse_or_captive", "native_pool_references", "round_number"}
POST_CHECKS = {"original_references_after", "rider_dictionary_after", "seats_native_merge",
               "downs_native_merge", "native_log_count", "aftermath_complete"}
HASH_KEYS = {"body", "roster", "custody", "rider", "seats", "downs"}


class InvalidEvidence(ValueError):
    pass


def need(condition, message):
    if not condition:
        raise InvalidEvidence(message)


def integer(value, label, lo=0, hi=None):
    need(isinstance(value, (int, float)) and not isinstance(value, bool)
         and math.isfinite(value) and value == int(value), f"{label}: integer required")
    value = int(value)
    need(value >= lo and (hi is None or value <= hi), f"{label}: out of range")
    return value


def number(value, label, lo=None):
    need(isinstance(value, (int, float)) and not isinstance(value, bool)
         and math.isfinite(value), f"{label}: finite number required")
    need(lo is None or value >= lo, f"{label}: out of range")
    return value


def sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def is_hash(value):
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value) is not None


def manifest():
    out = []
    for race in RACES:
        for role in ROLES:
            for seed in SEEDS:
                for side in (0, 1):
                    out.append(dict(index=len(out), id=f"race_{race}_{role}_{seed}_s{side}", kind="race",
                                    race=race, role=role, seed=seed, subject_side=side, mirror=race == "human"))
    for size in ("small", "large"):
        for count in (8, 16, 32):
            for seed in SEEDS:
                for side in (0, 1):
                    out.append(dict(index=len(out), id=f"dragon_{size}_{count}_{seed}_s{side}", kind="dragon",
                                    size=size, opponents=count, role="spear", seed=seed, subject_side=side, mirror=False))
    return out


MANIFEST = manifest()
BY_ID = {trial["id"]: trial for trial in MANIFEST}


def fingerprints(doc):
    result = []
    for field in ("source_sha256", "data_sha256"):
        values = doc.get(field)
        need(isinstance(values, dict) and values, f"missing {field}")
        need(all(isinstance(key, str) and is_hash(value) for key, value in values.items()),
             f"invalid/empty {field} digest")
        result.append(values)
    need("res://battle/battle.gd" in result[0], "explicit native battle scene source fingerprint missing")
    return result


def actor_rows(snapshot):
    return {actor["uid"]: actor for side in snapshot["roster"] for actor in side}


def validate_snapshot(snap, label):
    need(isinstance(snap, dict), f"{label}: missing state")
    need(set(snap.get("hashes", {})) == HASH_KEYS and all(is_hash(v) for v in snap["hashes"].values()),
         f"{label}: missing body/roster/custody/rider/seat/down hashes")
    need(snap.get("continuity_sha256") == sha(snap["hashes"]), f"{label}: wrong continuity hash")
    roster = snap.get("roster")
    need(isinstance(roster, list) and len(roster) == 2 and all(isinstance(v, list) for v in roster),
         f"{label}: two physical rosters required")
    ids = set()
    for side in roster:
        for actor in side:
            uid = actor.get("uid")
            need(isinstance(uid, str) and uid and uid not in ids, f"{label}: duplicate/missing actor UID")
            ids.add(uid)
            need(all(isinstance(actor.get(k), str) and actor[k] for k in ("unit_instance", "body_instance")),
                 f"{label}: original references must be lossless string labels")
            need(all(is_hash(actor.get(k)) for k in ("unit_sha256", "body_sha256", "gear_sha256", "quiver_sha256")),
                 f"{label}: missing actor physical hashes")
            need(all(type(actor.get(k)) is bool for k in ("dead", "fit", "captured", "native_dragon")),
                 f"{label}: actor states must be booleans")
            number(actor.get("injury"), f"{label} injury", 0)
    riders = snap.get("rider_bodies")
    need(isinstance(riders, dict), f"{label}: missing rider body dictionary")
    for person, rider in riders.items():
        need(isinstance(person, str) and person and isinstance(rider.get("uid"), str), f"{label}: rider identity missing")
        need(rider["uid"] not in ids, f"{label}: detached civilian rider leaked into ordinary roster")
        need(all(isinstance(rider.get(k), str) and rider[k] for k in ("unit_instance", "body_instance")),
             f"{label}: rider references missing")
        need(all(is_hash(rider.get(k)) for k in ("unit_sha256", "body_sha256")), f"{label}: rider physical hashes missing")
        need(type(rider.get("dead")) is bool, f"{label}: rider death not boolean")
        number(rider.get("injury"), f"{label} rider injury", 0)
    need(isinstance(snap.get("custody"), dict) and isinstance(snap.get("dragon_seats"), dict)
         and isinstance(snap.get("dragon_downs"), dict), f"{label}: custody/seats/downs missing")
    return snap


def same_references(initial, snap, label):
    original = actor_rows(initial)
    current = actor_rows(snap)
    need(list(map(lambda side: [a["uid"] for a in side], initial["roster"])) ==
         list(map(lambda side: [a["uid"] for a in side], snap["roster"])), f"{label}: roster pool changed")
    for uid, actor in original.items():
        need(all(current[uid][k] == actor[k] for k in ("unit_instance", "body_instance")), f"{label}: rebuilt Unit/body")
    need(set(initial["rider_bodies"]) == set(snap["rider_bodies"]), f"{label}: replaced/admitted rider")
    for person, actor in initial["rider_bodies"].items():
        need(all(snap["rider_bodies"][person][k] == actor[k] for k in ("uid", "unit_instance", "body_instance")),
             f"{label}: rebuilt civilian rider body")


def validate_seats(before, result, after, label):
    downs = dict(before["dragon_downs"])
    for uid, down in result.get("dragon_downs", {}).items():
        need(type(down) is bool, f"{label}: non-boolean dragon down")
        downs[uid] = bool(downs.get(uid, False)) or down
    need(downs == after["dragon_downs"], f"{label}: lost dragon-down continuity")
    seats = copy.deepcopy(before["dragon_seats"])
    for uid, receipt in result.get("dragon_seats", {}).items():
        now = dict(receipt)
        was = seats.get(uid, {})
        if was:
            now["damage"] = float(was.get("damage", 0)) + float(now.get("damage", 0))
            now["dead"] = bool(was.get("dead", False)) or bool(now.get("dead", False))
            if not str(now.get("unseated", "")) or str(was.get("unseated", "")) == "the rider fell":
                now["unseated"] = was.get("unseated", "")
        seats[uid] = now
    # The only approximate comparison is IEEE round-trip addition of cumulative seat damage.
    actual = copy.deepcopy(after["dragon_seats"])
    for uid, seat in seats.items():
        need(uid in actual, f"{label}: lost rider seat")
        if "damage" in seat:
            need(math.isclose(float(seat["damage"]), float(actual[uid].get("damage", 0)), rel_tol=1e-12, abs_tol=1e-12),
                 f"{label}: wrong cumulative rider damage")
            seat["damage"] = actual[uid].get("damage", 0)
    need(seats == actual, f"{label}: wrong native rider seat merge")


def validate_package(row, control=False):
    trial = row["trial"]
    package = row.get("package", {})
    counts = package.get("ordinary_counts", [])
    costs = package.get("starting_costs", [])
    need(len(counts) == len(costs) == 2, "missing real package counts/costs")
    counts = [integer(v, "ordinary count", 0, 32) for v in counts]
    if trial["kind"] == "race":
        need(all(n > 4 for n in counts), "ordinary armies must both exceed round_size 4")
        need(all(number(v, "real starting cost", 0) > 0 for v in costs), "nonpositive race cost")
        gap = abs(costs[0] - costs[1]) / max(costs)
        need(gap <= 0.05 and math.isclose(gap, package.get("match", {}).get("gap", -1), rel_tol=1e-12, abs_tol=1e-12),
             "no actual <=5% match")
        need(package["match"].get("counts") == counts and package["match"].get("costs") == costs, "match metadata differs from actual package")
        expected = counts
    else:
        need(control or (counts == [0, trial["opponents"]] and costs[0] is None), "invented dragon budget or wrong opponent prefix")
        number(costs[1], "actual opposing spend", 0)
        dragon = package.get("dragon", {})
        need(dragon.get("gem") == "ruby" and dragon.get("stage") == "adult" and dragon.get("size") == trial["size"], "wrong original native dragon profile")
        need(dragon.get("purchase_price", "missing") is None, "invented dragon purchase price")
        need(set(dragon.get("seven_day_base_price_estimates", {})) == {"fresh_meat", "meat"}, "estimates must use real DragonCare meat goods")
        need(dragon.get("seven_day_food_units") == 7 * integer(dragon.get("food_need_units_per_day"), "daily dragon requirement"), "wrong pure seven-day requirement")
        person = dragon.get("rider_person_uid")
        need(person in row["initial"]["rider_bodies"], "missing actual native civilian rider")
        rider = row.get("rider_packages", {}).get(person, {})
        need(rider.get("native_civilian_battle_body") is True and "BENCHMARK" in rider.get("basis", ""), "rider wage benchmark incorrectly represented")
        components = [number(rider.get(k), k, 0) for k in ("gear_value", "quiver_value", "seven_day_retainer_wage_benchmark")]
        need(math.isclose(sum(components), number(rider.get("B_body_cost_benchmark"), "rider B benchmark", 0), rel_tol=1e-12), "wrong separate rider benchmark")
        expected = [counts[0] + 1, counts[1]]
    if trial["subject_side"]:
        expected = expected[::-1]
    need(row.get("starting_counts") == expected, "wrong physical starting counts")
    need([len(s) for s in row["initial"]["roster"]] == expected, "initial roster/count mismatch")


def validate_trial(row, expected=None, control=False):
    need(isinstance(row, dict) and isinstance(row.get("trial"), dict), "missing trial record")
    trial = row["trial"]
    if expected is not None:
        need(trial == expected, "unknown/modified manifest trial")
    status = row.get("status")
    need(status in DONE | PARTIAL, "unknown trial status")
    rounds = row.get("engagements")
    need(isinstance(rounds, list), "missing engagement array")
    if "initial" not in row:
        need(status in PARTIAL and not rounds and row.get("final_result") is None, "missing initial state on executed trial")
        return
    initial = validate_snapshot(row["initial"], "initial")
    validate_package(row, control)
    side = integer(trial.get("subject_side"), "subject physical side", 0, 1)
    mapping = [0, 1] if side == 0 else [1, 0]
    need(row.get("physical_to_participant") == mapping, "participant-side normalization changed")
    inputs = row.get("input_sha256_participants", [])
    need(len(inputs) == 2 and all(is_hash(v) for v in inputs) and is_hash(row.get("rider_input_sha256")), "pre-physical input hashes missing")
    need(row.get("input_sha256_physical") == ([inputs[0], inputs[1]] if side == 0 else [inputs[1], inputs[0]]), "physical input permutation incorrect")
    previous = initial
    any_cap = any_draw = False
    for index, engagement in enumerate(rounds, 1):
        label = f"{trial['id']} engagement {index}"
        need(engagement.get("round") == index and engagement.get("trial_id") == trial["id"], f"{label}: skipped/duplicate round")
        need(engagement.get("seed") == trial["seed"] and engagement.get("subject_side") == side
             and engagement.get("native_seed") == trial["seed"] + 7919 * index, f"{label}: seed/physical side mismatch")
        before = validate_snapshot(engagement.get("before"), label + " before")
        after = validate_snapshot(engagement.get("after"), label + " after")
        need(before == previous, f"{label}: physical/roster/custody/rider state changed between rounds")
        same_references(initial, before, label)
        same_references(initial, after, label)
        checks = engagement.get("checks", {})
        need(PRE_CHECKS <= set(checks) and all(v is True for v in checks.values()), f"{label}: wrong transition assertion")
        picks = engagement.get("selected_uids", [])
        need(isinstance(picks, list) and len(picks) == 2, f"{label}: selected UIDs missing")
        for physical in (0, 1):
            available = {a["uid"]: a for a in before["roster"][physical]}
            need(len(picks[physical]) <= 4 and len(set(picks[physical])) == len(picks[physical]), f"{label}: oversized/duplicate picks")
            for uid in picks[physical]:
                need(uid in available and available[uid]["fit"] and not available[uid]["dead"]
                     and not available[uid]["captured"], f"{label}: corpse/captive/unfit or foreign Unit selected")
        ticks = integer(engagement.get("ticks"), label + " ticks")
        maximum = integer(engagement.get("opts", {}).get("max_ticks"), label + " max_ticks", 1)
        need(maximum == (2 if control else 6000), f"{label}: changed declared native tick bound")
        need(engagement.get("tick_capped") is (ticks >= maximum), f"{label}: dishonest tick-cap flag")
        winner = integer(engagement.get("native_winner"), label + " winner", -1, 1)
        if engagement.get("status") == "incomplete_wall":
            need(index == len(rounds) and status in PARTIAL and engagement.get("aftermath_applied") is False
                 and engagement.get("round_applied") is False and engagement.get("draw") is False, f"{label}: wall interruption settled as a result")
            continue
        need(engagement.get("status") == "complete" and POST_CHECKS <= set(checks), f"{label}: unfinished round settled")
        need(engagement.get("aftermath_applied") is True and engagement.get("round_applied") is True, f"{label}: missing native aftermath/after_round")
        need(engagement.get("draw") is (winner < 0), f"{label}: dishonest draw flag")
        result = engagement.get("round_result", {})
        summary = engagement.get("native_summary", {})
        need(result.get("winner") == summary.get("winner") == winner and result.get("ticks") == ticks
             and summary.get("round") == index, f"{label}: native result mismatch")
        need(len(summary.get("morale", [])) == len(summary.get("fresh_left", [])) == 2, f"{label}: morale/casualty summary missing")
        need(result.get("combat_journal", "missing") is None, f"{label}: non-JSON journal object")
        validate_seats(before, result, after, label)
        physical = engagement.get("delta_physical", [])
        need(len(physical) == 2 and engagement.get("delta_participants") == (physical if side == 0 else physical[::-1]),
             f"{label}: loss/injury deltas not normalized")
        need(isinstance(engagement.get("delta_riders"), dict), f"{label}: separate rider injury/death deltas missing")
        previous = after
        any_cap |= engagement["tick_capped"]
        any_draw |= engagement["draw"]
    if status not in DONE:
        need(row.get("final_result") is None and row.get("battle_summary") is None, "interrupted trial fabricated a final settlement")
        return
    need(rounds and row.get("total_rounds") == len(rounds), "missing completed engagement(s)")
    need(row.get("any_tick_cap") is any_cap and row.get("any_draw") is any_draw, "whole-battle cap/draw flags lost")
    term = row.get("termination", {})
    need(type(term.get("reached_native_max_rounds")) is bool and term["reached_native_max_rounds"] == (len(rounds) >= 20), "dishonest native MAX_ROUNDS flag")
    need(term.get("reason") in {"native_army_break", "native_max_rounds"}, "native termination reason missing")
    censored = any_cap or term["reached_native_max_rounds"]
    need(row.get("censored") is censored and status == ("complete_censored" if censored else "complete"), "censored result promoted to resolved win")
    winner = integer(row.get("native_winner"), "whole native winner", 0, 1)
    need(row.get("winner_participant") == (winner if side == 0 else 1 - winner), "whole winner not participant-normalized")
    summary = row.get("battle_summary", {})
    final = row.get("final_result", {})
    final_keys = {"winner", "player_units", "enemy_units", "enemy_fallen", "enemy_fled", "player_fled", "side_names",
                  "fighter_states", "events", "fighter_units", "ticks", "growth", "combat_journal", "kill_pairs",
                  "dragon_downs", "dragon_seats", "history_events_omitted", "arrow_field", "rounds", "battle_summary"}
    need(final_keys <= set(final) and final.get("winner") == summary.get("winner") == winner
         and summary.get("rounds") == len(rounds), "missing/extraneous native final settlement projection")
    need(final["battle_summary"] == summary and final["rounds"] == [e["native_summary"] for e in rounds], "final native round log/summary changed")
    need(final["dragon_downs"] == previous["dragon_downs"] and final["dragon_seats"] == previous["dragon_seats"], "whole-battle rider/down continuity lost")
    final_state = validate_snapshot(row.get("final"), "final")
    same_references(initial, final_state, "final")
    need(all(final_state["hashes"][k] == previous["hashes"][k] for k in HASH_KEYS - {"custody"}), "final settlement rebuilt/healed bodies or lost rider seats")
    need(len(row.get("fit_survivors_physical", [])) == len(row.get("totals_physical", [])) == 2, "whole casualties/fit survivors missing")


def outcome(row):
    if row["status"] not in DONE:
        return "incomplete"
    if row["censored"]:
        return "censored"
    if row["any_draw"]:
        return "draw_influenced"
    return "win" if row["winner_participant"] == 0 else "loss"


def frontier(rows):
    points = []
    for row in rows:
        package = row.get("package", {})
        costs = package.get("starting_costs", [None, None])
        points.append(dict(trial=row["trial"]["id"], seed=row["trial"]["seed"], physical_side=row["trial"]["subject_side"],
                           opponent_spend=costs[1], outcome=outcome(row)))
    wins = [p["opponent_spend"] for p in points if p["outcome"] == "win" and p["opponent_spend"] is not None]
    losses = [p["opponent_spend"] for p in points if p["outcome"] == "loss" and p["opponent_spend"] is not None]
    other = any(p["outcome"] not in {"win", "loss"} or p["opponent_spend"] is None for p in points)
    bracket = None
    reason = "draw/cap/incomplete evidence" if other else "all-win/all-loss or no opposing outcomes"
    if not other and wins and losses:
        if max(wins) < min(losses):
            bracket = [max(wins), min(losses)]
            reason = "observed two-seed spend interval only; no inferred price or fairness claim"
        else:
            reason = "overlapping/reversed win-loss spends or deployment-side disagreement"
    return dict(status="OBSERVED_INTERVAL" if bracket else "UNRESOLVED", bracket=bracket, reason=reason,
                max_observed_win_spend=max(wins) if wins else None, min_observed_loss_spend=min(losses) if losses else None,
                coordinates=sorted(points, key=lambda p: (p["opponent_spend"] is None, p["opponent_spend"] or 0, p["trial"])))


def validate_contract(doc, reference_fingerprints):
    need(doc is not None, "native contract artifact is required for complete mechanical coverage")
    need(doc.get("schema") == CONTRACT_SCHEMA and fingerprints(doc) == reference_fingerprints, "mixed/unknown contract source/data")
    need(doc.get("status") == "complete" and doc.get("complete") is True and doc.get("fails") == 0
         and doc.get("failures") == [] and integer(doc.get("checks"), "contract checks", 1), "native contract did not pass")
    control = doc.get("control", {})
    need(control.get("trial", {}).get("kind") == "control", "missing actual native carry-over control")
    validate_trial(control, control=True)
    need(control["status"] == "complete_censored" and len(control["engagements"]) >= 2
         and control["any_tick_cap"] and control["any_draw"], "native control lacks real >=2 engagement/cap/draw evidence")


def aggregate(books, phase, contract=None, allow_incomplete=False):
    need(books, "explicit checkpoint paths are required")
    reference = fingerprints(books[0])
    need(re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", phase or "") is not None, "explicit valid phase required")
    n = integer(books[0].get("shards"), "shards", 1, 108)
    seen_shards = set()
    rows = {}
    manifest_hash = books[0].get("manifest_sha256")
    need(is_hash(manifest_hash), "manifest fingerprint missing")
    for book in books:
        need(book.get("schema") == SCHEMA and book.get("phase") == phase, "mixed phase/schema")
        need(fingerprints(book) == reference, "mixed source/data fingerprints")
        need(book.get("manifest") == MANIFEST and book.get("manifest_sha256") == manifest_hash, "mixed/modified exact manifest")
        need(book.get("shards") == n, "mixed partition denominator")
        shard = integer(book.get("shard"), "shard", 0, n - 1)
        need(shard not in seen_shards, "duplicate partition/checkpoint; supply only its final chosen artifact")
        seen_shards.add(shard)
        need(book.get("round_size") == 4 and book.get("max_ticks") == 6000 and book.get("internal_wall_ms") == 45000
             and book.get("external_watchdog_seconds") == 55, "changed declared engine bounds")
        only = book.get("only_trial", "")
        need(isinstance(only, str) and (not only or only in BY_ID), "unknown single-trial filter")
        selected = [t["id"] for t in MANIFEST if t["index"] % n == shard and (not only or t["id"] == only)]
        need(selected and book.get("selected_ids") == selected, "missing/modified partition manifest")
        trials = book.get("trials")
        need(isinstance(trials, list), "missing trials array")
        need([r.get("trial", {}).get("id") for r in trials] == selected[:len(trials)], "skipped/duplicate/out-of-partition trial")
        for row in trials:
            tid = row["trial"]["id"]
            need(tid not in rows, "duplicate physical trial")
            validate_trial(row, BY_ID[tid])
            rows[tid] = row
        expected_complete = len(trials) == len(selected) and all(r["status"] in DONE for r in trials)
        need(type(book.get("complete")) is bool and (not book["complete"] or expected_complete), "incomplete shard labelled passed")
        need(book.get("status") in {"running", "incomplete", "complete"} and (book["status"] == "complete") == book["complete"], "inconsistent shard status")
    pairs = defaultdict(list)
    for row in rows.values():
        pairs[row["trial"]["id"][:-3]].append(row)
    for pair in pairs.values():
        if len(pair) != 2 or any("initial" not in r for r in pair):
            continue
        a, b = sorted(pair, key=lambda r: r["trial"]["subject_side"])
        need(a["input_sha256_participants"] == b["input_sha256_participants"]
             and a["rider_input_sha256"] == b["rider_input_sha256"], "fresh side swaps regenerated different physical inputs/rider payloads")
        need(a["package"]["starting_costs"] == b["package"]["starting_costs"]
             and a["package"]["ordinary_counts"] == b["package"]["ordinary_counts"], "fresh side swaps changed actual costs/counts")
    missing = [t["id"] for t in MANIFEST if t["id"] not in rows]
    complete = not missing and len(seen_shards) == n and all(b["complete"] for b in books) and all(r["status"] in DONE for r in rows.values())
    multi = [r["trial"]["id"] for r in rows.values() if r["status"] in DONE and r["total_rounds"] >= 2]
    contract_passed = False
    if contract is not None:
        validate_contract(contract, reference)
        contract_passed = True
    if not allow_incomplete:
        need(complete, f"missing/incomplete coverage: {len(missing)} trials, partitions {sorted(set(range(n)) - seen_shards)}")
        need(contract_passed, "native contract artifact required")
        need(len(multi) >= 2, "actual measured multi-engagement cases required in addition to control")
    summaries = {"race_role": {}, "human_mirrors": {}, "dragon_size": {}}
    groups = defaultdict(list)
    for row in rows.values():
        trial = row["trial"]
        category = "dragon_size" if trial["kind"] == "dragon" else ("human_mirrors" if trial["mirror"] else "race_role")
        key = trial["size"] if trial["kind"] == "dragon" else f"{trial['race']}/{trial['role']}"
        groups[category, key].append(row)
    for (category, key), items in sorted(groups.items()):
        summaries[category][key] = dict(trials=len(items), outcomes=dict(Counter(outcome(r) for r in items)),
                                       native_subject_wins=sum(r.get("winner_participant") == 0 for r in items if r["status"] in DONE),
                                       engagements=sum(len(r["engagements"]) for r in items), observed_frontier=frontier(items))
    return dict(schema="engagement_summary_v093/1", phase=phase, complete_coverage=complete,
                mechanical_complete=complete and contract_passed and len(multi) >= 2, native_contract_passed=contract_passed,
                planned_trials=108, provided_trials=len(rows), missing_trials=missing,
                missing_partitions=sorted(set(range(n)) - seen_shards), measured_multi_engagement_cases=multi,
                one_engagement_native_breaks=[r["trial"]["id"] for r in rows.values() if r["status"] in DONE and r["total_rounds"] == 1],
                censored_engagements=sum(bool(e.get("tick_capped")) or e.get("status") != "complete" for r in rows.values() for e in r["engagements"]),
                statuses=dict(Counter(r["status"] for r in rows.values())), summaries=summaries,
                balance_claim="NONE: 2-seed pilot, human reference only; no all-pairs/native-roster/terrain coverage or fairness pass threshold",
                source_sha256=reference[0], data_sha256=reference[1])


def load(path):
    def reject_constant(value):
        raise InvalidEvidence(f"non-finite JSON number {value}")

    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            need(key not in result, f"duplicate JSON key {key}")
            result[key] = value
        return result

    with Path(path).open(encoding="utf-8-sig") as stream:
        result = json.load(stream, parse_constant=reject_constant, object_pairs_hook=unique_keys)
    need(isinstance(result, dict), "artifact must be a JSON object")
    return result


def _synthetic_state(counts, rider=False, dead=False):
    roster = []
    for side, count in enumerate(counts):
        roster.append([dict(uid=f"{side}-{i}", unit_instance=f"unit-{side}-{i}", body_instance=f"body-{side}-{i}",
                            unit_sha256=sha([side, i, "unit"]), body_sha256=sha([side, i, "body"]),
                            gear_sha256=sha("gear"), quiver_sha256=sha("quiver"), dead=dead and side == 0 and i == count - 1,
                            fit=not (dead and side == 0 and i == count - 1), captured=False, native_dragon=rider and side == 0 and i == 0,
                            injury=0.0) for i in range(count)])
    riders = {"native-person": dict(uid="rider", unit_instance="rider-unit", body_instance="rider-body", unit_sha256=sha("r-unit"),
                                      body_sha256=sha("r-body"), dead=False, injury=0.0)} if rider else {}
    snap = dict(roster=roster, rider_bodies=riders, custody={}, dragon_seats={}, dragon_downs={})
    hashes = {k: sha(k) for k in HASH_KEYS}
    snap.update(hashes=hashes, continuity_sha256=sha(hashes))
    return snap


def _synthetic_row(trial, control=False):
    """Mechanical schema fixture only. No engine/combat result is claimed by --self-test."""
    side = trial["subject_side"]
    dragon = trial["kind"] != "race"
    counts = [10, 9] if control else ([1, trial["opponents"]] if dragon else [12, 12])
    physical_counts = counts[::-1] if side else counts
    state = _synthetic_state(physical_counts, dragon, control)
    if dragon and side:
        for s, actors in enumerate(state["roster"]):
            for i, actor in enumerate(actors):
                actor["native_dragon"] = s == 1 and i == 0
    costs = [1200.0, 1200.0] if not dragon else [900.0 if control else None, float(counts[1] * 100)]
    package = dict(ordinary_counts=([9, 9] if control else ([0, counts[1]] if dragon else counts)), starting_costs=costs)
    rider_packages = {}
    if dragon:
        package["dragon"] = dict(gem="ruby", stage="adult", size=trial["size"], purchase_price=None, rider_person_uid="native-person",
                                 food_need_units_per_day=2, seven_day_food_units=14,
                                 seven_day_base_price_estimates={"fresh_meat": 42, "meat": 56})
        rider_packages["native-person"] = dict(native_civilian_battle_body=True, gear_value=0, quiver_value=0,
                                              seven_day_retainer_wage_benchmark=7, B_body_cost_benchmark=7, basis="unpaid BENCHMARK")
    else:
        package["match"] = dict(gap=0, counts=counts, costs=costs)
    inputs = [sha(trial["id"][:-3] + "a"), sha(trial["id"][:-3] + "b")]
    rounds = []
    for index in (1, 2):
        winner = -1 if control else side
        summary = dict(round=index, winner=winner, morale=[62, 62], fresh_left=physical_counts)
        result = dict(winner=winner, ticks=2 if control else 10, combat_journal=None, dragon_seats={}, dragon_downs={})
        delta = [dict(injury=0, dead=0), dict(injury=0, dead=0)]
        rounds.append(dict(trial_id=trial["id"], seed=trial["seed"], native_seed=trial["seed"] + index * 7919,
                           subject_side=side, round=index, before=copy.deepcopy(state), after=copy.deepcopy(state),
                           checks={key: True for key in PRE_CHECKS | POST_CHECKS},
                           selected_uids=[[a["uid"] for a in actors[:min(4, len(actors))] if not a["dead"]] for actors in state["roster"]],
                           opts=dict(max_ticks=2 if control else 6000), ticks=2 if control else 10, native_winner=winner,
                           draw=control, tick_capped=control, status="complete", aftermath_applied=True, round_applied=True,
                           native_summary=summary, round_result=result, delta_physical=delta,
                           delta_participants=delta[::-1] if side else delta, delta_riders={}))
    summary = dict(winner=side, rounds=2)
    final = dict(winner=side, player_units=[], enemy_units=[], enemy_fallen=[], enemy_fled=[], player_fled=[], side_names=[],
                 fighter_states=[], events=[], fighter_units=[], ticks=rounds[-1]["ticks"], growth={}, combat_journal=None,
                 kill_pairs=[], dragon_downs={}, dragon_seats={}, history_events_omitted=0, arrow_field=[],
                 rounds=[e["native_summary"] for e in rounds], battle_summary=summary)
    return dict(trial=trial, status="complete_censored" if control else "complete", package=package, rider_packages=rider_packages,
                initial=state, starting_counts=physical_counts, physical_to_participant=[1, 0] if side else [0, 1],
                input_sha256_participants=inputs, input_sha256_physical=inputs[::-1] if side else inputs,
                rider_input_sha256=sha("normalized-person-rider"), engagements=rounds, total_rounds=2,
                any_tick_cap=control, any_draw=control, censored=control,
                termination=dict(reason="native_army_break", reached_native_max_rounds=False),
                native_winner=side, winner_participant=0, battle_summary=summary, final_result=final,
                final=copy.deepcopy(state), fit_survivors_physical=physical_counts, totals_physical=[{}, {}])


def self_test():
    book = dict(schema=SCHEMA, phase="selftest", shard=0, shards=1, only_trial="", manifest=MANIFEST,
                manifest_sha256=sha(MANIFEST), selected_ids=list(BY_ID), trials=[_synthetic_row(t) for t in MANIFEST],
                round_size=4, max_ticks=6000, internal_wall_ms=45000, external_watchdog_seconds=55, status="complete", complete=True,
                source_sha256={"res://battle/battle.gd": sha("SYNTHETIC source")}, data_sha256={"test": sha("SYNTHETIC data")})
    ct = dict(id="contract_native_carry", index=-1, kind="control", size="small", opponents=9, seed=SEEDS[0], subject_side=0, role="spear", mirror=False)
    contract = dict(schema=CONTRACT_SCHEMA, status="complete", complete=True, checks=1, fails=0, failures=[],
                    control=_synthetic_row(ct, True), source_sha256=book["source_sha256"], data_sha256=book["data_sha256"])
    result = aggregate([book], "selftest", contract)
    need(result["complete_coverage"] and result["mechanical_complete"] and len(result["summaries"]["human_mirrors"]) == 3,
         "positive complete synthetic coverage fixture")
    negatives = []

    def rejected(name, mutate):
        b = copy.deepcopy(book)
        c = copy.deepcopy(contract)
        docs = [b]
        mutate(b, c, docs)
        try:
            aggregate(docs, "selftest", c)
        except (InvalidEvidence, KeyError, TypeError, IndexError) as error:
            # Shape errors must also be rejected, but the negative must actually exercise validation.
            negatives.append(dict(name=name, rejected=True, reason=str(error)))
            return
        raise AssertionError(f"negative control accepted: {name}")

    rejected("missing trial", lambda b, c, d: b["trials"].pop())
    rejected("duplicate trial", lambda b, c, d: b["trials"].append(copy.deepcopy(b["trials"][0])))
    rejected("duplicate partition/checkpoint", lambda b, c, d: d.append(copy.deepcopy(b)))
    rejected("mixed phase", lambda b, c, d: b.update(phase="other"))
    rejected("mixed source", lambda b, c, d: c["source_sha256"].update({"res://battle/battle.gd": sha("other")}))
    rejected("mixed data", lambda b, c, d: c["data_sha256"].update(test=sha("other")))
    rejected("mixed partition", lambda b, c, d: b.update(shards=2))
    rejected("modified manifest", lambda b, c, d: b.update(manifest=[]))
    rejected("skipped engagement", lambda b, c, d: b["trials"][0]["engagements"][1].update(round=3))
    rejected("wrong continuity", lambda b, c, d: b["trials"][0]["engagements"][1]["before"]["hashes"].update(body=sha("healed")))
    rejected("rebuilt rider", lambda b, c, d: b["trials"][84]["engagements"][1]["after"]["rider_bodies"]["native-person"].update(body_instance="new body"))
    rejected("dead selected actor", lambda b, c, d: b["trials"][0]["engagements"][0]["before"]["roster"][0][0].update(dead=True))
    rejected("false native assertion", lambda b, c, d: b["trials"][0]["engagements"][0]["checks"].update(seats_native_merge=False))
    rejected("lost dragon down", lambda b, c, d: b["trials"][84]["engagements"][0]["round_result"].update(dragon_downs={"dragon": True}))
    rejected("unlabelled cap", lambda b, c, d: b["trials"][0]["engagements"][0].update(ticks=6000))
    rejected("draw inferred win", lambda b, c, d: b["trials"][0]["engagements"][0].update(native_winner=-1))
    rejected("side swap drift", lambda b, c, d: b["trials"][1].update(input_sha256_participants=[sha("different"), sha("different")], input_sha256_physical=[sha("different"), sha("different")]))
    rejected("invented dragon price", lambda b, c, d: b["trials"][84]["package"]["dragon"].update(purchase_price=999))
    rejected("no native carry-over control", lambda b, c, d: c.update(control={}))
    partial = copy.deepcopy(book)
    partial.update(trials=partial["trials"][:1], complete=False, status="incomplete")
    report = aggregate([partial], "selftest", allow_incomplete=True)
    need(not report["complete_coverage"] and not report["mechanical_complete"] and len(report["missing_trials"]) == 107,
         "explicit partial diagnostic cannot pass coverage")
    one = [_synthetic_row(MANIFEST[0])]
    need(frontier(one)["status"] == "UNRESOLVED", "all-win frontier unresolved")
    one[0]["winner_participant"] = 1
    need(frontier(one)["status"] == "UNRESOLVED", "all-loss frontier unresolved")
    a, b = _synthetic_row(MANIFEST[0]), _synthetic_row(MANIFEST[1])
    b["winner_participant"] = 1
    need(frontier([a, b])["status"] == "UNRESOLVED", "same-coordinate side disagreement unresolved")
    b["package"]["starting_costs"][1] = 1300
    need(frontier([a, b])["bracket"] == [1200, 1300], "observed spend interval uses actual coordinates")
    a["any_draw"] = True
    need(frontier([a, b])["status"] == "UNRESOLVED", "draw prevents a bracket")
    print(json.dumps(dict(self_test="PASS", native_runtime="UNRUN", synthetic_only=True,
                          positive_controls=7, negative_controls=len(negatives), negatives=negatives), indent=2))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", nargs="*", help="explicit final chosen checkpoint per partition; no glob expansion inside this script")
    parser.add_argument("--phase")
    parser.add_argument("--contract", help="explicit successful native contract JSON path")
    parser.add_argument("--allow-incomplete", action="store_true", help="diagnose partial evidence; never asserts mechanical completeness")
    parser.add_argument("--self-test", action="store_true", help="bounded in-memory mechanical controls only")
    args = parser.parse_args(argv)
    try:
        if args.self_test:
            need(not args.artifacts and not args.contract and not args.phase, "self-test does not consume native artifacts")
            self_test()
            return 0
        need(args.phase and args.artifacts, "--phase and explicit artifact paths are required")
        paths = [str(Path(p).resolve()) for p in args.artifacts]
        need(len(paths) == len(set(paths)), "duplicate explicit artifact path")
        report = aggregate([load(p) for p in paths], args.phase, load(args.contract) if args.contract else None, args.allow_incomplete)
        print(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
        return 0
    except (InvalidEvidence, OSError, json.JSONDecodeError, KeyError, TypeError, IndexError) as error:
        print(json.dumps(dict(status="REJECTED", error=str(error)), indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
