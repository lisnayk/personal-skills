#!/usr/bin/env bash
# Read-only overview of disk usage inside a WSL distro and its Docker engine.
# Run from Windows:  wsl.exe -e bash -ic 'bash /mnt/c/<skill-dir>/scripts/wsl-usage.sh'
set -u

section() { printf '\n== %s\n' "$1"; }

section "Filesystem (/)"
df -h / 2>/dev/null

section "Home directory, top 20"
du -xsh "$HOME"/* "$HOME"/.[!.]* 2>/dev/null | sort -rh | head -20

section "~/.cache, top 15"
du -xsh "$HOME"/.cache/* 2>/dev/null | sort -rh | head -15

section "System caches and logs"
du -xsh /var/cache/apt /var/log /tmp 2>/dev/null

section "Docker engine"
if ! command -v docker >/dev/null 2>&1; then
    echo "docker CLI not found"
    exit 0
fi
if ! docker info >/dev/null 2>&1; then
    echo "docker daemon is not reachable (Docker Desktop not running?) - Docker sections skipped"
    exit 0
fi
docker version --format 'server {{.Server.Version}}' 2>/dev/null
docker info --format '{{.OperatingSystem}} | root {{.DockerRootDir}}' 2>/dev/null

section "docker system df"
docker system df 2>/dev/null

section "Images"
docker images --format '{{.Size}}\t{{.CreatedSince}}\t{{.Repository}}:{{.Tag}}' 2>/dev/null

section "Volumes"
all=$(docker volume ls -q 2>/dev/null | wc -l)
anon=$(docker volume ls -q 2>/dev/null | grep -cE '^[0-9a-f]{64}$')
echo "total: $all, anonymous: $anon, named: $((all - anon))"
echo "-- named volumes (review by hand, may hold databases):"
docker volume ls -q 2>/dev/null | grep -vE '^[0-9a-f]{64}$'
echo "-- largest volumes:"
docker system df -v 2>/dev/null \
    | sed -n '/^Local Volumes space usage/,/^Build cache usage/p' \
    | grep -vE '^(Local Volumes space usage|Build cache usage|VOLUME NAME|$)' \
    | sort -k3 -rh | head -15
