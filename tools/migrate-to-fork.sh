#!/usr/bin/env bash
# Migrate an existing ComfyUI-Danbooru-Gallery installation from the upstream
# Aaalice233 repo to the WalkingMeatAxolotl fork (which carries the Cloudflare
# 403 fix while upstream is unmaintained).
#
# Preserves config.json, settings.json, and py/shared/data/tags_cache.db by
# backing them up and by stashing any uncommitted changes around the pull.
#
# Usage:
#   cd ComfyUI/custom_nodes/ComfyUI-Danbooru-Gallery
#   bash tools/migrate-to-fork.sh
#
# Or one-liner (run from the repo root):
#   curl -fsSL https://raw.githubusercontent.com/WalkingMeatAxolotl/ComfyUI-Danbooru-Gallery/main/tools/migrate-to-fork.sh | bash

set -euo pipefail

FORK_URL="https://github.com/WalkingMeatAxolotl/ComfyUI-Danbooru-Gallery.git"
SENTINEL="py/danbooru_gallery/danbooru_gallery.py"

if [ -d ".git" ] && [ -f "$SENTINEL" ]; then
    REPO_DIR="$(pwd)"
elif [ -d "ComfyUI-Danbooru-Gallery/.git" ] && [ -f "ComfyUI-Danbooru-Gallery/$SENTINEL" ]; then
    REPO_DIR="$(pwd)/ComfyUI-Danbooru-Gallery"
else
    echo "Error: run this script from inside ComfyUI-Danbooru-Gallery, or from the parent custom_nodes/ directory."
    exit 1
fi

cd "$REPO_DIR"
echo "Repo: $REPO_DIR"

BACKUP_DIR=".migrate-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
backed_up=0
for f in config.json settings.json py/shared/data/tags_cache.db; do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
        backed_up=$((backed_up + 1))
    fi
done
if [ "$backed_up" -gt 0 ]; then
    echo "Backed up $backed_up file(s) to $BACKUP_DIR"
else
    rmdir "$BACKUP_DIR"
fi

stashed=0
if ! git diff --quiet --ignore-submodules HEAD 2>/dev/null \
   || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    git stash push -u -m "migrate-to-fork-$(date +%s)" >/dev/null
    stashed=1
    echo "Stashed local changes."
fi

current_origin="$(git remote get-url origin 2>/dev/null || echo "")"
if [ "$current_origin" != "$FORK_URL" ]; then
    git remote set-url origin "$FORK_URL"
    echo "origin -> $FORK_URL"
fi

git fetch origin --prune
if ! git merge --ff-only origin/main; then
    echo
    echo "Fast-forward failed: your local main has diverged from the fork."
    echo "Resolve manually, e.g.:"
    echo "    git rebase origin/main"
    if [ "$stashed" -eq 1 ]; then
        echo "Your stash is still saved (see 'git stash list')."
    fi
    exit 1
fi

if [ "$stashed" -eq 1 ]; then
    if ! git stash pop; then
        echo
        echo "Stash pop hit conflicts. Your changes are still in 'git stash list'."
        echo "Files in $BACKUP_DIR are an untouched copy of your pre-migration state."
        exit 1
    fi
fi

echo
echo "Done. Restart ComfyUI to pick up the fix."
