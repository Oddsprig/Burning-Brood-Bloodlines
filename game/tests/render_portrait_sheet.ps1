param(
    [ValidateSet('all', 'human', 'dwarf', 'orc', 'goblin', 'troll', 'high_elf', 'moon_elf', 'dark_elf')]
    [string]$Race = 'all',
    [string]$GodotExe = 'C:\Users\bligh\Android\godot\Godot_v4.7.2-stable_win64_console.exe',
    [switch]$VerifyV067
)

# CPU-only headless render; no editor, visible player, or shared log file.
$ErrorActionPreference = 'Stop'
$projectPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resultsPath = [System.IO.Path]::GetFullPath((Join-Path $projectPath '..\test-results'))
$runId = '{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), ([Guid]::NewGuid().ToString('N'))
$logPath = Join-Path $resultsPath ('v0068_portrait_{0}_{1}.log' -f $Race, $runId)
$godotArgs = @(
    '--headless', '--path', $projectPath,
    '--script', 'res://tests/render_portrait_sheet.gd',
    '--log-file', $logPath,
    '--', $Race
)
if ($VerifyV067) {
    $godotArgs += '--verify-v067'
}
Write-Output ('LOG ' + $logPath)
& $GodotExe @godotArgs
$renderExitCode = $LASTEXITCODE
exit $renderExitCode
