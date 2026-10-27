# Заметки о рабочей машине

Факты на момент последнего аудита. Перед тем как на них опираться, перепроверь: после
переустановки Windows или переноса WSL пути могут поменяться. Если что-то изменилось, обнови
этот файл.

## Диски

- **C:** — системный, ~280 ГБ.
- **D:** (метка `Work`) — ~195 ГБ, NTFS. Здесь лежат WSL, Docker и старые проекты; именно он
  обычно заканчивается.
- **G:** — Google Drive в режиме стриминга (в `Get-Volume` его нет). Не локальный диск:
  переносить туда VHDX или рабочие данные нельзя.
- **F:** — пустой съёмный (кардридер).

## WSL и Docker

- WSL 2.6.x; дистрибутив по умолчанию — `Ubuntu`, его диск: `D:\wsl\Ubuntu\ext4.vhdx`.
- Docker Desktop с интеграцией в WSL: дистрибутив `docker-desktop` в `D:\wsl\DockerDesktopWSL\main`,
  диск данных — `D:\wsl\DockerDesktopWSL\disk\docker_data.vhdx`. Внутри Ubuntu нет
  `/var/lib/docker`, движок — Docker Desktop (`docker info` → `Docker Desktop`).
- Модуль Hyper-V для PowerShell установлен, `Optimize-VHD` доступен (нужны права админа).
- Кто держит WSL запущенной: Docker Desktop, WSL-терминалы, PhpStorm/VS Code remote, Codex
  (`codex-windows-sandbox-service`). Перед сжатием их все нужно закрыть.
- `D:\wsl\Ubuntu.tar.gz` — старый `wsl --export` (05.2025), не актуальный бэкап.

## Наследие

- `D:\OS` — Open Server Panel, давно не используется (последние логи — 02.2026). `modules`,
  `progs` и `userdata` — это сам Open Server; `domains` — ~128 старых проектов.
- Файлы в `D:\OS\domains` принадлежат SID старой установки Windows → git ругается на
  dubious ownership; читать через `git -c safe.directory=*`.
- Многие проекты из `D:\OS\domains` есть и в WSL `~/projects`, но у части старых копий есть
  незапушенные коммиты: перед удалением нужен `repo-audit.ps1`.

## Baseline (аудит 2026-10-25)

Свободно 3,8 ГБ из 195.

| Что | Размер | Комментарий |
|---|---|---|
| `D:\wsl\Ubuntu\ext4.vhdx` | 62,8 ГБ | внутри занято 50 ГБ; кэши: yarn 7,8, npm 6,2, JetBrains 3,6, `~/.codex` 2,3 |
| `D:\wsl\DockerDesktopWSL\disk\docker_data.vhdx` | 48,7 ГБ | внутри ~30 ГБ: образы 13,9 (11,9 не используются), build cache 10,5, тома 5,2 (53 шт., большинство анонимные) |
| `D:\OS` | 36,9 ГБ | domains 25, modules 7,8, userdata 3,3 |
| `$RECYCLE.BIN` | 11,6 ГБ | корзина текущего пользователя |
| `node_modules` / `vendor` вне WSL | ~20 / ~4 ГБ | 163 и 129 папок, в основном `D:\OS\domains` |
| `D:\projects\isosurface-extraction-comparison\.venv` | 5,2 ГБ | |
| Не учтено сканом | ~9 ГБ | скорее всего `System Volume Information` (теневые копии) |
