SOURCE ONLY / UNRUN. Follow-up to db6ad79 / TestBridge 130fe3a3 (eight groups, three failures).

Root's saved-state diagnosis identifies anonymous cohort Academy employment, then load-time removal/payment causing wage/coin drift. Academy now proves proposed places through copied native Persons.work mapping. Direct appointments require the selected cohort person to occupy the offered place. Partial legacy blocks cannot retain an anonymous prefix by shortening to their named count. Earned claims remain preserved.

New mixed-cohort regressions cover refusal, genuine named hiring, exact lead UID/skill, wages, load preservation and partial-block repair. Eight completion groups and >=100 checks remain; save assertions are unchanged.

Required ROOT integration: hiring_places sees the current book; later competing offers can change its final order. The new regression exposes this. Correct support needs a final matcher guard, not mutation in Persons/Population readers. Only root may edit Families. Insert immediately before _best_places commits want:

```gdscript
if Population.is_cohort(f) and not Academy.biz_of(e).is_empty():
	var academy_bid := int(e["academy"])
	var research_key := str(academy_bid)
	var prospective_family := f.duplicate(true)
	var prospective_jobs: Dictionary = prospective_family["jobs"]
	for held_key in prospective_jobs.keys():
		if not want.has(held_key): prospective_jobs.erase(held_key)
	for wanted_key in want:
		prospective_jobs[wanted_key] = int(want[wanted_key])
	if Academy._named_places(Persons.work(e, prospective_family), academy_bid) != int(want.get(research_key, 0)):
		want.erase(research_key)
```

Changed: game/campaign/academy.gd; game/tests/test_academy_v089.gd; REPORT_v089_FIX.md. Families is UNMODIFIED. Full guarantee requires root's hunk above; parsing/runtime remain UNRUN. Inherited companion passes: 8122/0 and 496/0.

Root TestBridge command from v089:

```text
godot --headless --path game res://tests/runner.tscn -- --tests=res://tests/test_academy_v089.gd,res://tests/test_academy_assignments.gd,res://tests/test_steel_smelting_v088.gd --watchdog=180
```
