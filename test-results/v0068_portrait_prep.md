# v0.068 portrait prep

Implemented the five race-local static `paint(spec)` delegates and runtime dispatch.
The delegates call the existing `_render(spec)` directly to avoid recursion. Elf
dispatch and all drawing methods remain unchanged. Each redo job owns only its
`game/art/portraits/portrait_<race>.gd` file.

`render_portrait_sheet.gd` draws five labelled variants at 4x nearest-neighbor
scale, using the exact v0.067 fixture specs. A race invocation writes its own PNG;
`all` writes all eight race sheets and the overview. Elf renders always compare
all five portrait tiles against that race's saved v0.067 AFTER row. Optional
`--verify-v067` extends this exact RGBA-byte comparison to all redo races during
prep. The PowerShell launcher supplies a timestamp/GUID log for each invocation.

## Validation and blocker

- PowerShell 5.1 launcher syntax: passed.
- Existing elf baseline dimensions: confirmed 1508x712 for all three races.
- Godot entry script parsed, but the render could not load the existing painter
  and fixtures: `PixelCanvas`, `FigurePainter`, and the `DB` autoload were not
  registered in this scoped copy. The watchdog ended that failed run with code
  124; the script now checks failed loads and exits immediately with code 1.
- Failure log: `test-results/v0068_portrait_all_314079b5e89d4f90944ed2fe8baf6ee6.log`.
- **No v0.068 PNGs were generated. Elf pixel identity is unverified.**

Finishing the render requires the complete game project and its initialized
class registry/autoloads. Accessing or restoring those files is outside the
three authorized folders, so no such changes were attempted. No files were
deleted, and no git commands were used.

## Exact commands

Run from the complete `bb-v059` root after the changed files are applied there.
The launcher defaults to the existing executable recorded in the allowed logs:
`C:\Users\bligh\Android\godot\Godot_v4.7.2-stable_win64_console.exe`.
`-ExecutionPolicy Bypass` below affects only the child PowerShell process and
does not change the computer's execution-policy settings.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tests\render_portrait_sheet.ps1 -Race human
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tests\render_portrait_sheet.ps1 -Race dwarf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tests\render_portrait_sheet.ps1 -Race orc
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tests\render_portrait_sheet.ps1 -Race goblin
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tests\render_portrait_sheet.ps1 -Race troll
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tests\render_portrait_sheet.ps1 -Race high_elf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tests\render_portrait_sheet.ps1 -Race moon_elf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tests\render_portrait_sheet.ps1 -Race dark_elf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\game\tests\render_portrait_sheet.ps1 -Race all -VerifyV067
```

Each launches Godot with `--headless --path <game> --script
res://tests/render_portrait_sheet.gd --log-file <unique-log> -- <race>`.
No visible window is opened and this CPU-only render does not queue behind other
Godot processes, as requested by this task.

## Intended PNG paths (not generated)

All are relative to the complete `bb-v059` root:

- `test-results/v0068_portrait_human.png`
- `test-results/v0068_portrait_dwarf.png`
- `test-results/v0068_portrait_orc.png`
- `test-results/v0068_portrait_goblin.png`
- `test-results/v0068_portrait_troll.png`
- `test-results/v0068_portrait_high_elf.png`
- `test-results/v0068_portrait_moon_elf.png`
- `test-results/v0068_portrait_dark_elf.png`
- `test-results/v0068_portrait_all_races.png`
