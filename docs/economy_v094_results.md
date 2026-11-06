# v0.094 short acceptance results

Accepted source `ad5ebefdfc5729f601012e0516f6f3f96ce422dc`, normally merged and pushed as `a48ea0d69c1b79843b027272d7bb29b36b66ec9f`.

The owner stopped the 240-day campaign acceptance and required short runs covering the day-53 mint overdraft and save/reload. The old P10 phase completed 165 checkpointed days before a day-173 census failure; its exact source records and all earlier failed phases are preserved. Current source acceptance covers the replacement short checks below. Two-year stability remains unverified.

(1) one Godot test at a time on this PC, headless only, never open a game window; (2) before any test, check for running Godot or Unity processes from any project, and if any are running, queue and wait; (3) every test run must finish in under 3 minutes, so split anything longer into short runs.

| Check | Passed | Engine seconds | Whole admitted run seconds | Test Bridge job |
|---|---:|---:|---:|---|
| Regression/protocol controls | 321 | 4.99 | 5.95 | `08dda1d1369844849f47111c58c5fd08` |
| Days 46–53 mint, native save and live day 54 | 3848 | 37.28 | 38.19 | `ec3cf831c8954aa3aaaa57ed771c79f2` |
| Fresh-process day-53 reload and day-54 parity | 475 | 12.03 | 12.99 | `624b52bf05fe4eb3a42fd50151a979fd` |

All runs were headless with Dummy audio on the shared Test Bridge lane, with a 120-second engine bound and a 150-second whole-job bound. Queue wait is recorded separately from execution. Source fingerprints match across accepted jobs. The preexisting missing splash image warning remains; no script errors, timeouts or source mutations were accepted.

The native day-46 input SHA256 is `8d81898815b9bf15546c6349be5822cba8b17c00f65efa0996282de1b8ac9ad9`. Its historical unguarded replay ended day 53 with treasury −197.59569512111216. Current native execution hits the same Ithilspire business job and keeps treasury nonnegative after every ordered work step, ending day 53 at 9140.34586455427. Native coin, goods, arms, Item, ration and treasure gates pass. No credit, grant or balance clamp was added.

The existing native writer saves day 53. A fresh process loads that SHA-bound save and compares observations, holdings, Item IDs and RNG with the saved endpoint; its native day-54 continuation equals the original live day-54 endpoint exactly. Both input saves and the manifest remain unchanged. This uses the existing v074 codec; v095 upgrades remain on hold.

Production fixes plan actual rounded mint inputs and reject losing or unfunded transactions before mutation, register and dispose newly constructed recruit template IDs, book kit removed when recruits or force members die naturally, and transfer anonymous population categories using each family row's stored year, including newly adult naming. Native category regressions reproduced 13 old failures and now pass 40/40; totals, money and ordinary year turns remain checks. Pricing, recipe, debasement, staffing, age policy and save schema are unchanged.

Regressions: Mint affordability v094: 69, Recruit item custody v094: 65, Population categories v094: 40, Existing population economy controls: 60, Protocol and physical controls: 87.

Evidence is in root run086-095: AGGREGATED-094-short.json, SHORT-COLLECTED receipts, MERGED-094.json, PUSHED-094.json and immutable Test Bridge artifacts. The helper's original REPORT_v094.md is a historical source delivery report; this results report supersedes its unrun status. v0.095 stays on owner hold. The last packaged Desktop/Android release remains 0.085.
