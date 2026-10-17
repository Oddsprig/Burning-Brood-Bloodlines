param([switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
$bloodlinesRoot = $PSScriptRoot
$bloodlinesGame = Join-Path $bloodlinesRoot 'game'
$bloodlinesRuntime = Join-Path $bloodlinesRoot 'runtime\Godot_v4.7.2-stable_win64.exe'
$bloodlinesMarker = Join-Path $bloodlinesRoot '.bloodlines-v0.022-ready'
$bloodlinesLog = Join-Path $bloodlinesRoot 'launch-log.txt'
try {
    if (-not (Test-Path -LiteralPath $bloodlinesRuntime)) { throw 'Bundled runtime is missing. Extract the whole Windows release folder.' }
    if (-not (Test-Path -LiteralPath (Join-Path $bloodlinesGame 'project.godot'))) { throw 'Game source is missing. Extract the whole Windows release folder.' }
    if (-not (Test-Path -LiteralPath $bloodlinesMarker) -or -not (Test-Path -LiteralPath (Join-Path $bloodlinesGame '.godot\global_script_class_cache.cfg'))) {
        $bloodlinesArguments = '--headless --path "' + $bloodlinesGame + '" --import'
        $bloodlinesStdout = Join-Path $bloodlinesRoot 'launch-prepare.stdout.txt'
        $bloodlinesStderr = Join-Path $bloodlinesRoot 'launch-prepare.stderr.txt'
        $bloodlinesImport = Start-Process -FilePath $bloodlinesRuntime -ArgumentList $bloodlinesArguments -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $bloodlinesStdout -RedirectStandardError $bloodlinesStderr
        $bloodlinesErrors = @(Get-Content -LiteralPath $bloodlinesStdout; Get-Content -LiteralPath $bloodlinesStderr) | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:|\bFAIL\b|Parse Error|Compile Error' -and $_.Trim() -ne 'ERROR: Failed to read the root certificate store.' }
        if ($bloodlinesErrors) { throw 'First-run preparation reported a source error. See launch-prepare logs.' }
        if ($bloodlinesImport.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $bloodlinesGame '.godot\global_script_class_cache.cfg'))) { throw 'First-run preparation failed. See game/.godot and the game user-data logs.' }
        [System.IO.File]::WriteAllText($bloodlinesMarker, 'Burning Brood Bloodlines v0.022 / Godot 4.7.2')
    }
    if ($PrepareOnly) { return }
    $bloodlinesArguments = '--path "' + $bloodlinesGame + '" --rendering-method gl_compatibility'
    Start-Process -FilePath $bloodlinesRuntime -ArgumentList $bloodlinesArguments -WindowStyle Normal | Out-Null
} catch {
    [System.IO.File]::WriteAllText($bloodlinesLog, $_.Exception.Message)
    if ($PrepareOnly) {
        [Console]::Error.WriteLine($_.Exception.Message)
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Burning Brood: Bloodlines') | Out-Null
    }
    exit 1
}

