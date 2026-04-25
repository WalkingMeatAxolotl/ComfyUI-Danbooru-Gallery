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
# Or right-click the .ps1 file -> "Run with PowerShell". The window will stay
# open at the end so you can read the result; press Enter to close it.
#
# Or one-liner:
#   iwr -useb https://raw.githubusercontent.com/WalkingMeatAxolotl/ComfyUI-Danbooru-Gallery/main/tools/migrate-to-fork.ps1 | iex

$ErrorActionPreference = "Stop"

$ForkUrl  = "https://github.com/WalkingMeatAxolotl/ComfyUI-Danbooru-Gallery.git"
$Sentinel = "py/danbooru_gallery/danbooru_gallery.py"

function Invoke-Migration {
    if ((Test-Path ".git") -and (Test-Path $Sentinel)) {
        $RepoDir = (Get-Location).Path
    } elseif ((Test-Path "ComfyUI-Danbooru-Gallery/.git") -and (Test-Path "ComfyUI-Danbooru-Gallery/$Sentinel")) {
        $RepoDir = Join-Path (Get-Location).Path "ComfyUI-Danbooru-Gallery"
    } else {
        throw "Run this script from inside ComfyUI-Danbooru-Gallery, or from the parent custom_nodes/ directory.  Current dir: $((Get-Location).Path)"
    }

    Set-Location -LiteralPath $RepoDir
    Write-Host "Repo: $RepoDir"

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "'git' not found on PATH. Install Git for Windows: https://git-scm.com/download/win"
    }

    $BackupDir = ".migrate-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $backedUp = 0
    foreach ($f in @("config.json", "settings.json", "py/shared/data/tags_cache.db")) {
        if (Test-Path -LiteralPath $f) {
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
    $script:Stashed = $false
    if ($dirty -or $untracked) {
        $stashTag = "migrate-to-fork-" + [DateTimeOffset]::Now.ToUnixTimeSeconds()
        git stash push -u -m $stashTag | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "git stash failed (exit $LASTEXITCODE)."
        }
        $script:Stashed = $true
        Write-Host "Stashed local changes."
    }

    $currentOrigin = (git remote get-url origin 2>$null)
    if ($currentOrigin -ne $ForkUrl) {
        git remote set-url origin $ForkUrl
        Write-Host "origin -> $ForkUrl"
    }

    git fetch origin --prune
    if ($LASTEXITCODE -ne 0) {
        throw "git fetch failed (exit $LASTEXITCODE). Check your network / GitHub access."
    }

    git merge --ff-only origin/main
    if ($LASTEXITCODE -ne 0) {
        $msg = "Fast-forward failed: your local main has diverged from the fork.`nResolve manually, e.g.:  git rebase origin/main"
        if ($script:Stashed) { $msg += "`nYour stash is still saved (see 'git stash list')." }
        throw $msg
    }

    if ($script:Stashed) {
        git stash pop
        if ($LASTEXITCODE -ne 0) {
            throw "Stash pop hit conflicts. Your changes are still in 'git stash list'.`nFiles in $BackupDir are an untouched copy of your pre-migration state."
        }
    }

    Write-Host ""
    Write-Host "Done. Restart ComfyUI to pick up the fix." -ForegroundColor Green
}

$exitCode = 0
try {
    Invoke-Migration
} catch {
    Write-Host ""
    Write-Host "Migration failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $exitCode = 1
}

# Keep the console open if launched by double-click / "Run with PowerShell",
# where the host would otherwise close before the user can read anything.
if ($Host.Name -eq 'ConsoleHost' -and -not $env:CI) {
    Write-Host ""
    Read-Host "Press Enter to close"
}
exit $exitCode
