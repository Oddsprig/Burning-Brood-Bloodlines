# v093 source-only delivery

Implemented the limited **108 whole-battle** manifest: 7 races × 3 same-role human references × 2 fixed seeds × 2 fresh deployment sides = **84**, plus 2 native Ruby sizes × 3 human spear prefixes × 2 seeds × 2 sides = **24**. Human mirrors are retained separately.

The driver uses actual BattleRounds begin/selection/after_round/next_round/summary/final_result, real BattleSim, native scene opts, inherited aftermath and native civilian riders. It preserves actor/body/roster/custody/rider state, exports engagement and whole-battle evidence, normalizes deployment swaps and keeps caps, draws, wall interruptions and MAX_ROUNDS endings honest. Actual opponent spend, rider benchmarks and meat provisioning estimates remain separate; no dragon purchase price exists.

Added the native carry-over contract, strict explicit-path aggregator and controller commands in `docs/balance_v093.md`. The bounded Python aggregator self-test **PASSED**, including **19 negative controls**. Its schema fixtures are synthetic and make no combat claim.

**All current native compilation/import, contract, timing pilot and 108-trial runtime tests are UNRUN by this worker.** Root owns exact-source TestBridge execution and partition selection after timing. No runtime balance result or reproducibility pass is claimed. No remaining API blocker.

Changed only:

- `game/tests/balance_engagements_v093.gd`
- `game/tests/test_engagement_contract_v093.gd`
- `game/tests/summarize_engagements_v093.py`
- `docs/balance_v093.md`
- `REPORT_v093.md`

Production, BalanceV070 and the old unaccepted standalone draft were untouched. No engine, GPU, git, deletion, download, upload or helper calls.
