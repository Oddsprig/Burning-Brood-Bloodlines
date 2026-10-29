# Full suite, headless, one Godot process at a time. Submit through Test Bridge only.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$godot = 'C:\Users\bligh\Desktop\Burning_Brood_Bloodlines_v0.022\runtime\Godot_v4.7.2-stable_win64.exe'
$game = Join-Path $root 'game'
$log = Join-Path $root 'test-results\v0070_full_suite.log'
'' | Out-File -Encoding utf8 $log
$runs = @(
  @('--block=headless'), @('--block=spirewing_v061'),
  @('--block=balance_v070'), @('--block=identity_v070'), @('--block=popup_cleanup_v070'),
  @('--block=display_a'), @('--block=display_b'), @('--block=display_c'),
  @('--tests=res://tests/claude_fangs_v036.gd,res://tests/test_art_menus.gd,res://tests/test_art_redesign.gd,res://tests/test_bloodlines_ruler_art.gd,res://tests/test_humanoid_art_import.gd,res://tests/test_humanoid_interface.gd,res://tests/test_races_v065.gd')
)
$failed = 0
& $godot --headless --audio-driver Dummy --editor --quit --path $game 2>&1 | Out-Null
foreach ($r in $runs) {
  "### $($r -join ' ')" | Out-File -Append -Encoding utf8 $log
  $out = & $godot --headless --audio-driver Dummy --path $game res://tests/runner.tscn -- @r --watchdog=60 2>&1 | Out-String
  $code = $LASTEXITCODE
  $out | Out-File -Append -Encoding utf8 $log
  "### exit $code" | Out-File -Append -Encoding utf8 $log
  if ($code -ne 0) { $failed++ }
}
"SUITE RESULT: $failed failed run(s)" | Out-File -Append -Encoding utf8 $log
Get-Content $log
exit $failed
