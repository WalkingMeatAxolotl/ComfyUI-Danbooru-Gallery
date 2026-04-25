# Migrate an existing ComfyUI-Danbooru-Gallery installation from the upstream
# Aaalice233 repo to the WalkingMeatAxolotl fork (which carries the Cloudflare
# 403 fix while upstream is unmaintained).
#
# Preserves config.json, settings.json, and py/shared/data/tags_cache.db by
# backing them up and by stashing any uncommitted changes around the pull.
#
# Usage (PowerShell):
#   cd ComfyUI\custom_nodes\ComfyUI-Danbooru-Gallery
#   powershell -ExecutionPolicy Bypass -File tools\migrate-to-fork.ps1
#
# Or one-liner:
#   iwr -useb https://raw.githubusercontent.com/WalkingMeatAxolotl/ComfyUI-Danbooru-Gallery/main/tools/migrate-to-fork.ps1 | iex

$ErrorActionPreference = "Stop"

$ForkUrl  = "https://github.com/WalkingMeatAxolotl/ComfyUI-Danbooru-Gallery.git"
$Sentinel = "py/danbooru_gallery/danbooru_gallery.py"

if ((Test-Path ".git") -and (Test-Path $Sentinel)) {
    $RepoDir = (Get-Location).Path
} elseif ((Test-Path "ComfyUI-Danbooru-Gallery/.git") -and (Test-Path "ComfyUI-Danbooru-Gallery/$Sentinel")) {
    $RepoDir = Join-Path (Get-Location).Path "ComfyUI-Danbooru-Gallery"
} else {
    Write-Error "Run this script from inside ComfyUI-Danbooru-Gallery, or from the parent custom_nodes/ directory."
    exit 1
}

Set-Location $RepoDir
Write-Host "Repo: $RepoDir"

$BackupDir = ".migrate-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
$backedUp = 0
foreach ($f in @("config.json", "settings.json", "py/shared/data/tags_cache.db")) {
    if (Test-Path $f) {
        $dest = Join-Path $BackupDir $f
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $f -Destination $dest -Force
        $backedUp++
    }
}
if ($backedUp -gt 0) {
    Write-Host "Backed up $backedUp file(s) to $BackupDir"
} else {
    Remove-Item -LiteralPath $BackupDir -Force
}

git diff --quiet --ignore-submodules HEAD 2>$null
$dirty     = ($LASTEXITCODE -ne 0)
$untracked = [bool](git ls-files --others --exclude-standard)
$stashed   = $false
if ($dirty -or $untracked) {
    $stashTag = "migrate-to-fork-" + [int][double]::Parse((Get-Date -UFormat %s))
    git stash push -u -m $stashTag | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git stash failed."
        exit 1
    }
    $stashed = $true
    Write-Host "Stashed local changes."
}

$currentOrigin = (git remote get-url origin 2>$null)
if ($currentOrigin -ne $ForkUrl) {
    git remote set-url origin $ForkUrl
    Write-Host "origin -> $ForkUrl"
}

git fetch origin --prune
if ($LASTEXITCODE -ne 0) {
    Write-Error "git fetch failed."
    exit 1
}

git merge --ff-only origin/main
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Fast-forward failed: your local main has diverged from the fork."
    Write-Host "Resolve manually, e.g.:"
    Write-Host "    git rebase origin/main"
    if ($stashed) {
        Write-Host "Your stash is still saved (see 'git stash list')."
    }
    exit 1
}

if ($stashed) {
    git stash pop
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Stash pop hit conflicts. Your changes are still in 'git stash list'."
        Write-Host "Files in $BackupDir are an untouched copy of your pre-migration state."
        exit 1
    }
}

Write-Host ""
Write-Host "Done. Restart ComfyUI to pick up the fix."
