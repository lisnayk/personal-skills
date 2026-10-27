#!/usr/bin/env bash
# Interactive cleanup of regenerable caches inside WSL and Docker.
# Meant to be run BY THE USER in a WSL terminal: every step shows its size and asks [y/N].
# Nothing here touches project files or named Docker volumes.
# Afterwards run compact-vhdx.ps1 (elevated PowerShell on Windows) to give the space back to the host drive.
set -u

ask() {
    local answer
    read -r -p "$1 [y/N] " answer
    [[ "$answer" =~ ^[yY]$ ]]
}

size_of() {
    local total
    total=$(du -csh "$@" 2>/dev/null | tail -1 | cut -f1)
    echo "${total:-0}"
}

has() { command -v "$1" >/dev/null 2>&1; }

echo "== Package manager caches"

if has yarn; then
    dir=$(yarn cache dir 2>/dev/null)
    if [ -n "$dir" ] && ask "yarn cache ($dir, $(size_of "$dir")) - yarn cache clean?"; then
        yarn cache clean
    fi
fi

if has npm && [ -d "$HOME/.npm" ]; then
    if ask "npm cache (~/.npm, $(size_of "$HOME/.npm")) - npm cache clean --force?"; then
        npm cache clean --force
    fi
fi

if has composer; then
    dir=$(composer config --global cache-dir 2>/dev/null)
    if [ -n "$dir" ] && ask "composer cache ($dir, $(size_of "$dir")) - composer clear-cache?"; then
        composer clear-cache
    fi
fi

if [ -d /var/cache/apt/archives ] && ask "apt package cache ($(size_of /var/cache/apt/archives)) - sudo apt-get clean?"; then
    sudo apt-get clean
fi

echo
echo "== Tool caches (re-created on demand)"

if [ -d "$HOME/.cache/JetBrains" ]; then
    echo "Close PhpStorm / Gateway / remote dev backends before removing this one."
    if ask "JetBrains caches (~/.cache/JetBrains, $(size_of "$HOME/.cache/JetBrains")) - remove contents?"; then
        rm -rf "$HOME/.cache/JetBrains/"*
    fi
fi

browsers=()
[ -d "$HOME/.cache/ms-playwright" ] && browsers+=("$HOME/.cache/ms-playwright")
[ -d "$HOME/.cache/puppeteer" ] && browsers+=("$HOME/.cache/puppeteer")
if [ ${#browsers[@]} -gt 0 ]; then
    if ask "Headless browsers for playwright/puppeteer ($(size_of "${browsers[@]}")) - remove? (npx playwright install brings them back)"; then
        rm -rf "${browsers[@]}"
    fi
fi

if has docker && docker info >/dev/null 2>&1; then
    echo
    echo "== Docker"
    docker system df
    echo
    if ask "Build cache - docker builder prune -a?"; then
        docker builder prune -a -f
    fi
    if ask "Images not used by any container - docker image prune -a? (they will be pulled again when needed)"; then
        docker image prune -a -f
    fi
    anon=$(docker volume ls -q -f dangling=true | grep -cE '^[0-9a-f]{64}$')
    if [ "$anon" -gt 0 ] && ask "$anon unused anonymous volumes - docker volume prune? (Docker >= 23 keeps named volumes)"; then
        docker volume prune
    fi
    echo "Named volumes are left alone - review them by hand: docker volume ls"
else
    echo
    echo "== Docker: daemon not reachable, skipped (start Docker Desktop to clean it)"
fi

echo
if ask "Trim free blocks so the VHDX can be compacted - sudo fstrim -av?"; then
    sudo fstrim -av
fi

echo
echo "Done. To return the freed space to the Windows drive: quit Docker Desktop, then run"
echo "compact-vhdx.ps1 in PowerShell as Administrator."
