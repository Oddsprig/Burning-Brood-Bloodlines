# v094 source-only report

Implemented a resumable native campaign-economy runner with contract/batch/final modes. It declares Normal seed4242, creatures, one-day history and 240 complete native daily steps. Batches soft-stop at40s, drain ordered native work under explicit deadlines, and publish immutable, sequential native saves/observations/manifests with source, parameter, saved-file, metadata, RNG and daily-chain continuity checks. Only final validation can report overallComplete=true.

Observations cover WORLD/all seven native culture races, native cumulative census, hunger, actual worked/owned/arable acres, wages/prices/stocks and cash. Smith/maker selection uses native arms definitions; book profit, rolling NET receipts, wage claims/receipt snapshots and smoothed spend remain distinct. Unsupported gross sales/exact input expense/individual throughput are unavailable. Native conservation residuals remain authoritative; direct household stores/gems/treasure receive physical checks. No production tuning or v095 work.

The controller can use this protocol for the requested measurement **subject to native validation**. Import/contract controls, first saved/load continuity and the full240-day experiment are **UNRUN**. Source inspection is not runtime proof. Root owns every execution through PinnedTest/TestBridge; exact raw commands and persistent-profile requirements are in docs/economy_v094.md.

Changed only:

- game/tests/test_economy_stability_v094.gd
- game/tests/economy_stability_v094.gd
- docs/economy_v094.md
- REPORT_v094.md

No engine/import/build/tests, Git mutations, downloads, UI/process control or external uploads were performed.
