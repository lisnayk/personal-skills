#!/usr/bin/env bash
# Інтерактивне очищення відновлюваних кешів усередині WSL і Docker.
# Запускає САМ КОРИСТУВАЧ у терміналі WSL: кожен крок показує розмір і питає [y/N].
# Файли проєктів та іменовані томи Docker не зачіпаються.
# Після цього запусти compact-vhdx.ps1 (PowerShell від адміністратора у Windows), щоб повернути місце на диск.
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

echo "== Кеші менеджерів пакетів"

if has yarn; then
    dir=$(yarn cache dir 2>/dev/null)
    if [ -n "$dir" ] && ask "Кеш yarn ($dir, $(size_of "$dir")) — yarn cache clean?"; then
        yarn cache clean
    fi
fi

if has npm && [ -d "$HOME/.npm" ]; then
    if ask "Кеш npm (~/.npm, $(size_of "$HOME/.npm")) — npm cache clean --force?"; then
        npm cache clean --force
    fi
fi

if has composer; then
    dir=$(composer config --global cache-dir 2>/dev/null)
    if [ -n "$dir" ] && ask "Кеш composer ($dir, $(size_of "$dir")) — composer clear-cache?"; then
        composer clear-cache
    fi
fi

if [ -d /var/cache/apt/archives ] && ask "Кеш пакетів apt ($(size_of /var/cache/apt/archives)) — sudo apt-get clean?"; then
    sudo apt-get clean
fi

echo
echo "== Кеші інструментів (створюються заново за потреби)"

if [ -d "$HOME/.cache/JetBrains" ]; then
    echo "Перед видаленням закрий PhpStorm / Gateway / віддалені бекенди IDE."
    if ask "Кеші JetBrains (~/.cache/JetBrains, $(size_of "$HOME/.cache/JetBrains")) — видалити вміст?"; then
        rm -rf "$HOME/.cache/JetBrains/"*
    fi
fi

browsers=()
[ -d "$HOME/.cache/ms-playwright" ] && browsers+=("$HOME/.cache/ms-playwright")
[ -d "$HOME/.cache/puppeteer" ] && browsers+=("$HOME/.cache/puppeteer")
if [ ${#browsers[@]} -gt 0 ]; then
    if ask "Headless-браузери для playwright/puppeteer ($(size_of "${browsers[@]}")) — видалити? (npx playwright install поверне їх)"; then
        rm -rf "${browsers[@]}"
    fi
fi

if has docker && docker info >/dev/null 2>&1; then
    echo
    echo "== Docker"
    docker system df
    echo
    if ask "Кеш збірки — docker builder prune -a?"; then
        docker builder prune -a -f
    fi
    if ask "Образи, які не використовує жоден контейнер — docker image prune -a? (за потреби їх буде завантажено знову)"; then
        docker image prune -a -f
    fi
    anon=$(docker volume ls -q -f dangling=true | grep -cE '^[0-9a-f]{64}$')
    if [ "$anon" -gt 0 ] && ask "Невикористаних анонімних томів: $anon — docker volume prune? (Docker >= 23 не чіпає іменовані)"; then
        docker volume prune
    fi
    echo "Іменовані томи не чіпаємо — переглянь їх вручну: docker volume ls"
else
    echo
    echo "== Docker: демон недоступний, пропущено (запусти Docker Desktop, щоб почистити його)"
fi

echo
if ask "Позначити вільні блоки, щоб VHDX можна було стиснути — sudo fstrim -av?"; then
    sudo fstrim -av
fi

echo
echo "Готово. Щоб повернути звільнене місце на диск Windows: закрий Docker Desktop, потім"
echo "запусти compact-vhdx.ps1 у PowerShell від адміністратора."
