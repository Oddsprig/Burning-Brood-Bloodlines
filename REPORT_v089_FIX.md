SOURCE ONLY / UNRUN. Handoff for failed exact8a23b32, TestBridge add7f976257643bebca9f7e35efce7d8.

Failure classifications from source tracing:

- Three capital assertions: invalid fixture assumptions. Coverage now checks every actual economic capital, exactly one house, and every settled race; factions without economic capitals must report no house.
- Funding and two idle-wallet failures: retained native plots can make Families.crop_work -> CropRotation.work_acres -> Families.reassign create/fund a farm for replacement family ID 1. The fixture removes inherited plots, recounts population, and asserts zero land/herd work. Public debit, house credit, private purse and total coin remain checked.
- Legacy operator: inherited land can repopulate owns with a farm. The regression now calls after_load with valid keeper/employee accounting and verifies assignments, actual staff, unpaid claims and receipts across repeated loads.
- Empty crew and incomplete group: invalid startup staffing precondition. Public funding uses the real army bill; an empty house receives a native Persons._new/Families.set_job fixture employee. Native disk reload checks UID, skill, prepaid fractions, claims, receipts, stock, roster and replay guard.

Production: Academy.after_load idles blocked/completed houses before future payroll/upkeep. Regressions distinguish earned-wage settlement from honorary-post pay. Exact counts accept whole JSON floats and reject changed/fractional quantities. Eight completion counters and >=100 checks remain.

Changed: game/campaign/academy.gd; game/tests/test_academy_v089.gd; REPORT_v089_FIX.md.

Root TestBridge command, from v089:

```text
godot --headless --path game res://tests/runner.tscn -- --tests=res://tests/test_academy_v089.gd,res://tests/test_academy_assignments.gd,res://tests/test_steel_smelting_v088.gd --watchdog=180
```

Frozen handoff. Root reports legacy assignments 8122/0 and steel v088 496/0 PASS on exact4f544ce, job bc242121 (9.906s). These are inherited results, not verification of this patch. No root fixture/source was copied. This patch's parsing, runtime causality, save repair, timing and combined three-suite gate remain UNRUN; root owns application and execution.
