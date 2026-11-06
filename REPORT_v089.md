# v089 Academy source handoff — UNRUN

Concrete gaps closed in the seeded draft:

- `game/campaign/academy.gd`: `init_world`, `after_load`, `_state_owner` restore state ownership; `_release_unregistered` preserves claims while releasing unnamed places. `hiring_places` limits offers to registered adults. `lead_gone`, `mark_lead`, `appoint`, `vacate` protect head UID, keeper work and personal successor skill. `_training`/`day` retain personal skill and aptitude; `materials`/`_trials` require paid iron/flux/charcoal, preserve fractional prepaid trial capacity, stop unfunded work, and guard repeated days. `state`/`start_kh` enforce racial steel rules and independent data-line initialization. `faction_turn` records exact treasury receipts. `report` adds actual employee identities, skills, wages and material receipts.
- `game/campaign/businesses.gd`: `_row` exempts Academies from private operators; `daily` uses the Academy path before keeper/tool work; `books_day` idles without spending; `_books` protects accrued salary; `kh_of` rejects forbidden stale steel mirrors.
- `game/campaign/persons.gd`: `RESEARCH = 20`; `work` uses each employee's training for their trade title.
- `game/campaign/families.gd`: **new director authorization used**, only three Academy-specific offer clamps in `_best_places`.
- `game/ui/town_research_tab.gd`: `_summary`, `house_state`, `_history` show registered staffing, productive short staffing, employee skills, salary claims and trial inputs.
- `game/tests/test_academy_v089.gd`: eight completion-counted native groups cover cash/stock/claims, negatives, hiring, departures/succession, native marriage identity, steel gates and actual isolated save/load.

Director command, from `v089`, after predecessors merge and shared-lane admission:

```text
godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_academy_v089.gd --watchdog=180
```

UNRUN: no engine, imports, builds, runtime tests, timings, UI or century tuning. Test aims below 60 s, hard limit 180 s; one cached Normal/one-day world. Depends on accepted v087 charcoal data; adds no fuel/smelting/reservation patches. Keeps existing bronze/iron research rows. No outstanding external hook; no git or native/director files touched.
