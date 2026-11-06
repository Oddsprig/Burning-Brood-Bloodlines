# Burning Brood documentation and build rules

Owner standing process, 6 November 2026. Include this file's requirements in every helper build brief and link the shared [game testing rules](C:/Users/bligh/Documents/Codex/GAME%20TESTING%20RULES.md).

A version is not done until these three active documents are updated for that version in the same version merge:

- `PROJECT_MAP.md`: owning code, screen routes, entry points, implementation boundaries and remaining gaps.
- `docs/DEV_NOTES.txt`: actual behavior, design constraints, verification evidence and its limits.
- `CHANGES.txt`: that version's shipped changes and unresolved items.

Before merging a version, compare the previous version with the final candidate and check that all three paths changed. Read the changes and confirm they describe that version's actual source. A filename-only or unrelated edit does not satisfy the requirement. If any document is missing its update, do not merge. Do not rewrite prior version history to repair older omissions.

After every version merge, run one light notes-only helper to reconcile all three documents with the final merged version. Use Argon, Grok or Sol 6.1 MAX; never Gemini or Google Opus. For v0.095 the owner explicitly authorized the lead to perform this reconciliation directly. The lead reviews its result, commits any corrections and pushes normally with the owner's authorization. The notes helper counts toward the standing maximum of two concurrent helpers. Preparing the docs before the version merge and reconciling them afterward satisfies both owner instructions.

Every helper build brief must name the exact version/base, bounded source and documentation paths, acceptance evidence required, restrictions, and the three-document gate. Include the owner's testing rules verbatim:

> (1) one Godot test at a time on this PC, headless only, never open a game window; (2) before any test, check for running Godot or Unity processes from any project, and if any are running, queue and wait; (3) every test run must finish in under 3 minutes, so split anything longer into short runs.

The shared machine rules may impose a stricter current bound; read them before any authorized test. Historical commands, results and old briefs never grant permission for a new run. Use Test Bridge for authorized game tests, distinguish queued/interrupted/failed from passed, and do not restart other apps or acquire a nested lane lease.

The earlier three-helper source-only audit exception has ended. The standing maximum is two concurrent helpers, restricted to Argon, Grok or Sol 6.1 MAX; never Gemini or Google Opus. The owner approved the v0.095 merge and normal push after reading the full diff and 203-check output. This approval does not authorize any new test or game launch. Delete nothing.
