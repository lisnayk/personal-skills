#!/usr/bin/env bash
# Огляд зайнятого місця всередині дистрибутива WSL і його Docker. Лише читання.
# Запуск із Windows:  wsl.exe -e bash -ic 'bash /mnt/c/<тека-скіла>/scripts/wsl-usage.sh'
set -u

section() { printf '\n== %s\n' "$1"; }

section "Файлова система (/)"
df -h / 2>/dev/null

section "Домашній каталог, топ-20"
du -xsh "$HOME"/* "$HOME"/.[!.]* 2>/dev/null | sort -rh | head -20

section "~/.cache, топ-15"
du -xsh "$HOME"/.cache/* 2>/dev/null | sort -rh | head -15

section "Системні кеші та логи"
du -xsh /var/cache/apt /var/log /tmp 2>/dev/null

section "Рушій Docker"
if ! command -v docker >/dev/null 2>&1; then
    echo "docker CLI не знайдено"
    exit 0
fi
if ! docker info >/dev/null 2>&1; then
    echo "демон docker недоступний (Docker Desktop не запущено?) — розділи Docker пропущено"
    exit 0
fi
docker version --format 'server {{.Server.Version}}' 2>/dev/null
docker info --format '{{.OperatingSystem}} | root {{.DockerRootDir}}' 2>/dev/null

section "docker system df"
docker system df 2>/dev/null

section "Образи"
docker images --format '{{.Size}}\t{{.CreatedSince}}\t{{.Repository}}:{{.Tag}}' 2>/dev/null

section "Томи"
all=$(docker volume ls -q 2>/dev/null | wc -l)
anon=$(docker volume ls -q 2>/dev/null | grep -cE '^[0-9a-f]{64}$')
echo "усього: $all, анонімних: $anon, іменованих: $((all - anon))"
echo "-- іменовані томи (переглядати вручну, можуть містити бази даних):"
docker volume ls -q 2>/dev/null | grep -vE '^[0-9a-f]{64}$'
echo "-- найбільші томи:"
docker system df -v 2>/dev/null \
    | sed -n '/^Local Volumes space usage/,/^Build cache usage/p' \
    | grep -vE '^(Local Volumes space usage|Build cache usage|VOLUME NAME|$)' \
    | sort -k3 -rh | head -15
