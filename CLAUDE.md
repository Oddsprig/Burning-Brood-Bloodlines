# Burning Brood: Bloodlines (Claude Code)

Read AGENTS.md and docs/BUILD_RULES.md first: they hold every project rule. The first section of AGENTS.md, HOW TO TEST, is copied below so no session misses it.

## HOW TO TEST (owner's rule; read before running any test)

- Before any work, read CLAUDE.md, AGENTS.md and docs/BUILD_RULES.md and follow them. Paste this line into every helper task.
- Test in blocks: one headless Godot launch runs many tests through `game/tests/runner.tscn`, with `-- --block=<name>` (from `game/tests/blocks.json`) or `-- --tests=res://tests/a.gd,res://tests/b.gd`. `game/tests/run_full_suite_headless.ps1` shows the pattern. Submit each block through Test Bridge with `test-results/<version>/tools/run_blocks.py <plan>`.
- NEVER launch Godot once per test. A test gets its own launch only when it needs process-wide arguments (its own `--part=` or chain arguments). `older_runplan_batch_v100.gd` runs exactly one part per fresh process.
- Each version runs only the blocks that cover what it changed. The targeted list and block plan go in `test-results/<version>/targeted_tests_<version>.md` and `runs/blocks_<version>*.txt`. Every merge report states the number of tests and blocks.
- The full suite runs only once, right before a store launch.
- A block aims for under 60 s and has a 180 s hard cap; split any block that runs longer. A failed test is logged and fixed, then its block is rerun.
- Testing rules, verbatim: run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
