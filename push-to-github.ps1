# 首次推送 MeshObject 文档到 GitHub
# 仓库: https://github.com/z004ft5k/MeshObject
# 用法: 在 PowerShell 中右键「使用 PowerShell 运行」，或:
#   cd "C:\Users\xin.zeng\Documents\CurProjects\MeshObject"
#   .\push-to-github.ps1

$ErrorActionPreference = "Stop"
$RepoDir = $PSScriptRoot
$RemoteUrl = "https://github.com/z004ft5k/MeshObject.git"

# 查找 git
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    $candidates = @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $git = $c; break }
    }
}
if (-not $git) {
    Write-Host "未找到 Git。请先安装 Git for Windows:" -ForegroundColor Red
    Write-Host "  https://git-scm.com/download/win" -ForegroundColor Yellow
    Write-Host "或安装 GitHub Desktop（更简单）:" -ForegroundColor Yellow
    Write-Host "  https://desktop.github.com/" -ForegroundColor Yellow
    exit 1
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
    & $git commit -m "Initial commit: MeshObject DS V1.3 and discussion notes"
} else {
    $status = & $git status --porcelain
    if ($status) {
        & $git commit -m "docs: update MeshObject design documents"
    } else {
        Write-Host "没有需要提交的更改。" -ForegroundColor Green
    }
}

$remotes = & $git remote 2>$null
if ($remotes -notcontains "origin") {
    & $git remote add origin $RemoteUrl
}

Write-Host "正在推送到 $RemoteUrl ..." -ForegroundColor Cyan
Write-Host "若提示登录，用户名填 GitHub 用户名，密码填 Personal Access Token（不是账号密码）。" -ForegroundColor Yellow
& $git push -u origin main

Write-Host "完成。请打开: https://github.com/z004ft5k/MeshObject" -ForegroundColor Green
