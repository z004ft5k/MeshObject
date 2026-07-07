# Resolves git.exe: PATH -> GitHub Desktop -> Git for Windows.
# Dot-source from other scripts: . "$PSScriptRoot\resolve-git.ps1"
# Or: $git = & "$PSScriptRoot\resolve-git.ps1"

function Resolve-GitExecutable {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }

    $candidates = @()

    $ghd = Get-ChildItem "$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\cmd\git.exe" -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName } -Descending
    if ($ghd) { $candidates += $ghd[0].FullName }

    $candidates += @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )

    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    }

    return $null
}

$git = Resolve-GitExecutable
if (-not $git) {
    Write-Error "git not found. Install GitHub Desktop or Git for Windows."
    exit 1
}

# When invoked as script, print path for callers.
if ($MyInvocation.InvocationName -ne '.') {
    $git
}
