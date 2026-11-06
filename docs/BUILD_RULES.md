# Burning Brood documentation and build rules

Owner standing process, 6 November 2026. Include this file's requirements in every helper build brief and link the shared [game testing rules](C:/Users/bligh/Documents/Codex/GAME%20TESTING%20RULES.md).

A version is not done until these three active documents are updated for that version in the same version merge:

- `PROJECT_MAP.md`: owning code, screen routes, entry points, implementation boundaries and remaining gaps.
- `docs/DEV_NOTES.txt`: actual behavior, design constraints, verification evidence and its limits.
- `CHANGES.txt`: that version's shipped changes and unresolved items.

Before merging a version, compare the previous version with the final candidate and check that all three paths changed. Read the changes and confirm they describe that version's actual source. A filename-only or unrelated edit does not satisfy the requirement. If any document is missing its update, do not merge. Do not rewrite prior version history to repair older omissions.

After every version merge, run one light notes-only helper, preferably antigravity Gemini 3.8 or the cheapest available, to reconcile all three documents with the final merged version. The lead reviews its result, commits any corrections and pushes normally with the owner's authorization. The notes helper counts toward the standing maximum of two concurrent helpers. Preparing the docs before the version merge and reconciling them afterward satisfies both owner instructions.

Every helper build brief must name the exact version/base, bounded source and documentation paths, acceptance evidence required, restrictions, and the three-document gate. Include the owner's testing rules verbatim:

> (1) one Godot test at a time on this PC, headless only, never open a game window; (2) before any test, check for running Godot or Unity processes from any project, and if any are running, queue and wait; (3) every test run must finish in under 3 minutes, so split anything longer into short runs.

The shared machine rules may impose a stricter current bound; read them before any authorized test. Historical commands, results and old briefs never grant permission for a new run. Use Test Bridge for authorized game tests, distinguish queued/interrupted/failed from passed, and do not restart other apps or acquire a nested lane lease.

Current job exception: the owner named Argon high for economy/towns/people, Grok 4.7 high for war/battles/dragons and Sol 6.1 Max for houses/court/diplomacy/UI, at most three helpers for this source-only documentation audit. This replaces the earlier Gemini/Opus allocation for this job only. No game launches, builds or tests are authorized. Delete nothing. v0.095 is unbuilt and awaits the owner's go-ahead.
