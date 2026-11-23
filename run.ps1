# Runs Clay Garden. Arguments after -- go to the game, for example:
#   .\run.ps1 -- --fresh            # new island, the save is left untouched
# Godot 4.7.2: the GODOT environment variable, otherwise godot from PATH, otherwise the CodexTools folder.
$godot = $env:GODOT
if (-not $godot) { $cmd = Get-Command godot -ErrorAction SilentlyContinue; if ($cmd) { $godot = $cmd.Source } }
if (-not $godot) { $godot = "$env:LOCALAPPDATA\CodexTools\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe" }
if (-not (Test-Path $godot)) { Write-Error "Godot 4.7.2 not found: set `$env:GODOT = 'path\to\Godot_v4.7.2-stable_win64.exe'"; exit 1 }
& $godot --path $PSScriptRoot @args
