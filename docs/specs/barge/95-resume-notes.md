RESUME NOTES: economy helper, stopped 2026-10-05 ~03:20 (laptop shutdown)

Branch worktree-agent-a4e6b9d2fb9168ab0, commit f949d2b: adds game/tests/diag_barge_years.gd only (year-end report; not run yet). No model changes.

Baseline (diag_presim_econ.gd, 600 days, seed 2026, base d49205d)
- Population: 8,401 -> Y1 7,579 -> Y2 2,229 -> Y3 510 -> Y4 315 -> Y5 313.
- Land worked: 62% at start -> 57% (Y1) -> 9% (Y2) -> 3% (Y4+).
- Hungry households: 51 at the end of Y1; 1,156 in summer of Y2.
- Grain: 0.25-1.18 gold a meal. Farmhand wage: 4.5 gold a day.
- Run time: 42.8 s with the diagnostic's bookkeeping.
- Full suite on the base commit: 38 of 55 tests ran, all passed; the run was killed before the rest.

Planned decisions
- Coin factor: x20 (4.5 gold labourer -> 90 coins). Fits the barge tool and clothes prices; food comes from the barge list (grain about 3.6 coins a meal, meat about 20).
- Coin ledger: cast - melted - drained = all holdings, counting the company, realm treasuries, loot chests, lair gold and caravans. A daily test exposes every place coin appears from nothing. Known so far: contract pay, and the made-up purse on looted men with no family.
- Meat: salted, 120 days (the spec's [ours]). Fruit: [ours] 30 days (orchard fruit, not greens).
- World gen gives farm families oxen; otherwise the 4-acres-without-an-ox rule doubles the hands needed.
- Army.enlist drops a unit when no free person aged 17-30 exists (labourers first) instead of inventing a family. Men captured in AI fights are ransomed home.
- Open question: the money need is either population x 1,000 or the coin actually held at world start.

Spec issues to show Douglas
- Too few people for the work: 3,353 adults at the start, but land and herds need 2,656 hands and the trades 1,221, a gap of about 500. (He offered bigger towns at world gen: run 1.5x and 2x families and acreage with the same land per head, report stability and perf, and put the size behind one constant.)
- "2x hands at harvest" for a whole 30-day autumn can't be met: apply it to labour demand only, not to yield.
- Field hand at 1.15 x 100 coins out-earns his own output at barge grain prices with our 200 meals an acre, so grain must rise until hired farm work pays.

WAR HELPER, stopped at the same time
Branch worktree-agent-a6c130888b9477729, commit 0a8f4b2 (WIP). Nothing pushed.
- Truce (diplomacy.gd): 60-120 days, rolled per treaty, saved. During it fights() is false, no war can be declared, and no caravan raids. Shown in the relations UI.
- Militia: come out only at >= 1.25x the enemy. War bands no longer hunt militia.
- Map 1.5x: 150x96 cells (3600x2304 px), the same layout scaled. Old saves keep 100x64. Side effect: more wild cells means more lairs (cap still 18).
- Tests passing: test_campaign_world, test_campaign_diplomacy.
- test_campaign_monsters: failed only the per-frame perf check while running in parallel; rerun it alone.
- test_campaign_war: 6 checks fail.
  - 2 are the obsolete "militia caught in the field" check; replace it with walls/1.25x checks.
  - 3 are _intercept: the band never goes for the caravan.
  - 1 is "beaten band heads home" (398 -> 354 px, wants 50).
  - Cause not found yet.
- Still to do: truce, militia and map tests; test_all; after numbers; docs; CHANGES.
- Before numbers (base, seed 2026, 600 days): 2,924 men off the field, 1,481 of them in militia rows. March-Orc at war 510 days; 68 wars, median 21 days. 31.0 s.
