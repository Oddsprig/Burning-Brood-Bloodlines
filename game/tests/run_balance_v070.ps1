# Submit one bounded job to the shared lane. No direct Godot launch or file cleanup.
param(
    [ValidateSet('Survey','Regression','Import','Candidate','Related','FinalChecks')][string]$Mode = 'Survey',
    [ValidateSet('race','unit','mount','roster','roster_matrix','campaign','sweep','all','core')][string]$Suite = 'race',
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$Phase = 'survey',
    [ValidateRange(0,8191)][int]$Shard = 0,
    [ValidateRange(1,8192)][int]$Shards = 8,
    [ValidateRange(1,64)][int]$Samples = 2,
    [switch]$AllShards
)
$ErrorActionPreference = 'Stop'
if ($Shard -ge $Shards) { throw 'Shard must be smaller than Shards.' }
if ($AllShards) {
    $suites = if ($Suite -eq 'all') { @('race','unit','mount','roster_matrix','campaign') } elseif ($Suite -eq 'core') { @('race','unit','mount','campaign') } else { @($Suite) }
    foreach ($currentSuite in $suites) {
        $count = if ($currentSuite -eq 'campaign') { 1 } else { $Shards }
        $first = if ($Suite -eq 'all' -or $currentSuite -eq 'campaign') { 0 } else { $Shard }
        for ($index = $first; $index -lt $count; $index++) {
            & $PSCommandPath -Mode $Mode -Suite $currentSuite -Phase $Phase -Shard $index -Shards $count -Samples $Samples
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
    }
    exit 0
}
if ($Suite -in @('all','core')) { throw 'Use -AllShards with -Suite all or core.' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$godot = 'C:\Users\bligh\Desktop\Burning_Brood_Bloodlines_v0.022\runtime\Godot_v4.7.2-stable_win64.exe'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$label = 'v070a_{0}_{1}_{2}_{3}of{4}_{5}' -f $Mode,$Phase,$Suite,$Shard,$Shards,$stamp
$arguments = @('--headless','--audio-driver','Dummy','--path',(Join-Path $root 'game'))
$logPath = Join-Path $root ('test-results\' + $label + '.log')
$arguments += @('--log-file',$logPath)
if ($Mode -eq 'Import') {
    $arguments += @('--editor','--quit','--','--watchdog=60')
} else {
    $test = switch ($Mode) {
        'Regression' { 'test_balance_v070.gd' }
        'Candidate' { 'test_balance_v070.gd,res://tests/balance_v070.gd' }
        'Related' { 'test_sim_determinism.gd,res://tests/test_horses_v056.gd' }
        'FinalChecks' { 'balance_v070.gd,res://tests/test_sim_determinism.gd,res://tests/test_horses_v056.gd' }
        default { 'balance_v070.gd' }
    }
    $selection = if ($Mode -eq 'Regression') { '--block=balance_v070' } else { '--tests=res://tests/' + $test }
    $arguments += @('res://tests/runner.tscn','--',$selection,'--watchdog=60','--keep-test-files')
    $arguments += @(('--balance-suite=' + $Suite),('--balance-phase=' + $Phase),('--balance-shard=' + $Shard + '/' + $Shards),('--balance-samples=' + $Samples))
}
$response = & 'C:\Users\bligh\Documents\Codex\tools\game-testing\Submit-GameTest.ps1' `
    -Name $label -WorkflowId 'bb-v070a-balance-20261029' -Helper 'Codex balance v070a' `
    -Engine 'Godot' -Source 'v0.070a measured balance' -FilePath $godot `
    -ArgumentList $arguments -WorkingDirectory $root -TimeoutSeconds 55 -IdempotencyKey $label -Wait
$submitExit = $LASTEXITCODE
$reply = $response -join [Environment]::NewLine
$jsonStart = $reply.IndexOf('{')
if ($jsonStart -lt 0) { Write-Output $reply; exit 1 }
$receipt = $reply.Substring($jsonStart) | ConvertFrom-Json
$job = $receipt.job
if ($null -eq $job) { $job = $receipt }
[pscustomobject]@{id=$job.id; name=$job.name; status=$job.status; result=$job.result; log=$logPath} | ConvertTo-Json -Depth 5 -Compress
if ($submitExit -ne 0 -or $job.status -ne 'passed' -or $job.result.exit_code -ne 0) { exit 1 }
exit 0
