Source-only handoff for controller-supplied native baseline `bc028fa7064a38a2044aa2a59739acb092089870`. Runtime **UNRUN**; no git or native-tree access.

The original `game/tests/test_academy_v089.gd:619` snapshots research with `JSON.parse_string(JSON.stringify(...))`. The controller's exact `Game.load_game` excerpt calls `restore_exact(d)` to restore `__fx` float bits before deserialization and Academy repair. The test therefore compares two different numeric reconstruction paths. `Academy.state` also contains integer `places` alongside float fields. This establishes the fixture mismatch mechanism; the actual failing native leaf remains unobserved.

Changed `game/tests/test_academy_v089.gd`:

- Capture all research keys and nested values with `duplicate(true)`.
- Compare every dictionary key, array position and leaf exactly. Only mathematically identical int/float values may differ in type. Fractional drift has zero tolerance; mixed numeric comparison rejects lossy integers above 2^53 and out-of-range float-to-int conversion.
- Add three comparator controls covering nested numeric equivalence, one-bit float drift, integer boundaries, changed keys/order and nonnumeric types.
- Retain the old JSON round trip solely for pre-save diagnostics, reporting typed differences and the semantic-difference count. A remaining load failure prints before/after till/owed, their existing `near` results, and recursive research paths with values, types and serialized bytes.

The till/owed threshold remains 0.000001. Earned-claim, receipt, stock, training, identity and paid-staff assertions remain intact. `game/campaign/academy.gd` and `game/campaign/families.gd` are byte-identical to their supplied baselines, preserving both cohort fixes.

Root should rerun the bounded `test_academy_v089.gd` check, inspect snapshot diagnostics, and require 8/8 groups with zero failures, then retain the existing assignments/steel regressions. Risk: source has not been parsed or executed; any remaining `LOAD v089` differences require investigation. Changed files: this report and the test only. Handoff complete; stopped.
