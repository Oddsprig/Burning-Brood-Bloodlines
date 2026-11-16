extends "res://tests/make_fixture_econ_sanity_v100.gd"
## Shared seed-2026 Large native-600-day producer; inherited run() executes one --fixture-chunk=0..59, ten real days.
## Use this entry OR make_fixture_econ_sanity_v100.gd, never both at the same chunk index; seal every process before its successor.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
