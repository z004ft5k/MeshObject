# Git wrapper — uses GitHub Desktop bundled git when git is not on PATH.
# Usage: .\scripts\git.ps1 status
#        .\scripts\git.ps1 commit -m "message"

$ErrorActionPreference = "Stop"
$git = & "$PSScriptRoot\resolve-git.ps1"
if (-not $git) { exit 1 }

$gitDir = Split-Path -Parent $git
if ($env:Path -notlike "*$gitDir*") {
    $env:Path = "$gitDir;$env:Path"
}

& $git @args
exit $LASTEXITCODE
