# Commit and push MeshObject docs to GitHub
# Usage: cd MeshObject; .\push-to-github.ps1

$ErrorActionPreference = "Stop"
$RepoDir = $PSScriptRoot
$RemoteUrl = "git@github.com:z004ft5k/MeshObject.git"

$git = & "$RepoDir\scripts\resolve-git.ps1"
if (-not $git) {
    Write-Host "未找到 Git。请安装 GitHub Desktop 或 Git for Windows。" -ForegroundColor Red
    exit 1
}

$gitDir = Split-Path -Parent $git
if ($env:Path -notlike "*$gitDir*") {
    $env:Path = "$gitDir;$env:Path"
}

Set-Location $RepoDir

if (-not (Test-Path ".git")) {
    & $git init
    & $git branch -M main
}

& $git add README.md *.md
& $git status

$hasCommit = & $git rev-parse HEAD 2>$null
if (-not $hasCommit) {
    & $git commit -m "Initial commit: MeshObject design documents"
} else {
    $status = & $git status --porcelain
    if ($status) {
        & $git commit -m "docs: update MeshObject design documents"
    } else {
        Write-Host "没有需要提交的更改。" -ForegroundColor Green
        exit 0
    }
}

$remotes = & $git remote 2>$null
if ($remotes -notcontains "origin") {
    & $git remote add origin $RemoteUrl
}

Write-Host "正在推送到 origin (main) ..." -ForegroundColor Cyan
& $git push -u origin main

Write-Host "完成: https://github.com/z004ft5k/MeshObject" -ForegroundColor Green
