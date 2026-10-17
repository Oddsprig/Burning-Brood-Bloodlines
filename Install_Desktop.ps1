param([string]$Version = '0.022')
$ErrorActionPreference = 'Stop'
$bloodlinesSource = [System.IO.Path]::GetFullPath($PSScriptRoot)
if ($Version -notmatch '^\d+\.\d{3}$') { throw 'Invalid release version.' }
$bloodlinesManifestRelative = 'releases/v' + $Version + '_RELEASE_MANIFEST.json'
$bloodlinesManifestSource = Join-Path $bloodlinesSource $bloodlinesManifestRelative
$bloodlinesManifest = Get-Content -LiteralPath $bloodlinesManifestSource -Raw | ConvertFrom-Json
if ($bloodlinesManifest.title -ne 'Burning Brood: Bloodlines' -or $bloodlinesManifest.version -ne $Version) { throw 'Release identity differs.' }
$bloodlinesDesktop = [Environment]::GetFolderPath('Desktop')
if (-not $bloodlinesDesktop) { throw 'Windows Desktop could not be resolved.' }
$bloodlinesInstalled = [System.IO.Path]::GetFullPath((Join-Path $bloodlinesDesktop ('Burning_Brood_Bloodlines_v' + $Version)))
$bloodlinesShortcutPath = Join-Path $bloodlinesDesktop ('Burning Brood Bloodlines v' + $Version + '.lnk')
$bloodlinesFiles = @($bloodlinesManifest.files)
$bloodlinesDesktopPrefix = [System.IO.Path]::GetFullPath($bloodlinesDesktop).TrimEnd('\') + '\'
if (-not $bloodlinesInstalled.StartsWith($bloodlinesDesktopPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Install path is outside the Desktop.' }

function Get-BloodlinesPayloadPath([string]$basePath, [string]$relativePath) {
    if ([System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Unsafe release path.' }
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $basePath $relativePath))
    if (-not $fullPath.StartsWith($basePath.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Release path escapes its folder.' }
    return $fullPath
}

# Validate all source bytes and existing destinations before copying any file.
foreach ($bloodlinesFile in $bloodlinesFiles) {
    $bloodlinesFrom = Get-BloodlinesPayloadPath $bloodlinesSource $bloodlinesFile.path
    $bloodlinesTo = Get-BloodlinesPayloadPath $bloodlinesInstalled $bloodlinesFile.path
    $bloodlinesInfo = Get-Item -LiteralPath $bloodlinesFrom
    if ($bloodlinesInfo.Length -ne $bloodlinesFile.bytes -or (Get-FileHash -LiteralPath $bloodlinesFrom -Algorithm SHA256).Hash.ToLowerInvariant() -ne $bloodlinesFile.sha256) { throw ('Release bytes differ: ' + $bloodlinesFile.path) }
    if (Test-Path -LiteralPath $bloodlinesTo) {
        if ((Get-FileHash -LiteralPath $bloodlinesTo -Algorithm SHA256).Hash.ToLowerInvariant() -ne $bloodlinesFile.sha256) { throw ('Existing Desktop file differs: ' + $bloodlinesFile.path) }
    }
}
$bloodlinesInstalledManifest = Get-BloodlinesPayloadPath $bloodlinesInstalled $bloodlinesManifestRelative
if ((Test-Path -LiteralPath $bloodlinesInstalledManifest) -and (Get-FileHash -LiteralPath $bloodlinesInstalledManifest -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $bloodlinesManifestSource -Algorithm SHA256).Hash) { throw 'Existing Desktop release manifest differs.' }
foreach ($bloodlinesFile in $bloodlinesFiles) {
    $bloodlinesTo = Get-BloodlinesPayloadPath $bloodlinesInstalled $bloodlinesFile.path
    if (-not (Test-Path -LiteralPath $bloodlinesTo)) {
        $bloodlinesParent = Split-Path $bloodlinesTo -Parent
        if (-not (Test-Path -LiteralPath $bloodlinesParent)) { New-Item -ItemType Directory -Path $bloodlinesParent -Force | Out-Null }
        Copy-Item -LiteralPath (Get-BloodlinesPayloadPath $bloodlinesSource $bloodlinesFile.path) -Destination $bloodlinesTo
    }
}
if (-not $bloodlinesManifestSource.Equals($bloodlinesInstalledManifest, [System.StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item -LiteralPath $bloodlinesManifestSource -Destination $bloodlinesInstalledManifest
}
foreach ($bloodlinesFile in $bloodlinesFiles) {
    $bloodlinesTo = Get-BloodlinesPayloadPath $bloodlinesInstalled $bloodlinesFile.path
    if ((Get-Item -LiteralPath $bloodlinesTo).Length -ne $bloodlinesFile.bytes -or (Get-FileHash -LiteralPath $bloodlinesTo -Algorithm SHA256).Hash.ToLowerInvariant() -ne $bloodlinesFile.sha256) { throw ('Desktop readback differs: ' + $bloodlinesFile.path) }
}

$bloodlinesLauncher = Join-Path $bloodlinesInstalled 'Launch_Bloodlines.ps1'
$bloodlinesIcon = Join-Path $bloodlinesInstalled 'Bloodlines.ico'
if (-not (Test-Path -LiteralPath $bloodlinesIcon)) { throw 'Branded Desktop icon missing.' }
$bloodlinesShell = New-Object -ComObject WScript.Shell
$bloodlinesLink = $bloodlinesShell.CreateShortcut($bloodlinesShortcutPath)
$bloodlinesLink.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$bloodlinesLink.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $bloodlinesLauncher + '"'
$bloodlinesLink.WorkingDirectory = $bloodlinesInstalled
$bloodlinesLink.IconLocation = $bloodlinesIcon + ',0'
$bloodlinesLink.Description = 'Burning Brood: Bloodlines v' + $Version
$bloodlinesLink.WindowStyle = 7
$bloodlinesLink.Save()
$bloodlinesReadback = $bloodlinesShell.CreateShortcut($bloodlinesShortcutPath)
if ($bloodlinesReadback.TargetPath -ne $bloodlinesLink.TargetPath -or $bloodlinesReadback.Arguments -ne $bloodlinesLink.Arguments -or $bloodlinesReadback.WorkingDirectory -ne $bloodlinesInstalled -or $bloodlinesReadback.IconLocation -ne ($bloodlinesIcon + ',0')) { throw 'Desktop shortcut readback differs.' }
[ordered]@{
    result = 'PASS'
    version = $Version
    installed_folder = $bloodlinesInstalled
    shortcut = $bloodlinesShortcutPath
    target = $bloodlinesReadback.TargetPath
    arguments = $bloodlinesReadback.Arguments
    icon = $bloodlinesReadback.IconLocation
    verified_payload_files = $bloodlinesFiles.Count
    source_commit = $bloodlinesManifest.source_commit
    game_launched = $false
} | ConvertTo-Json

