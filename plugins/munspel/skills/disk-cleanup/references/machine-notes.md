# Нотатки про робочу машину

Факти на момент останнього аудиту. Перш ніж на них спиратися, перевір: після перевстановлення
Windows або перенесення WSL шляхи можуть змінитися. Якщо щось змінилося, онови цей файл.

## Диски

- **C:** — системний, ~280 ГБ.
- **D:** (мітка `Work`) — ~195 ГБ, NTFS. Тут лежать WSL, Docker і старі проєкти; саме він
  зазвичай закінчується.
- **G:** — Google Drive у режимі стримінгу (у `Get-Volume` його немає). Не локальний диск:
  переносити туди VHDX чи робочі дані не можна.
- **F:** — порожній знімний (кардрідер).

## WSL і Docker

- WSL 2.6.x; дистрибутив за замовчуванням — `Ubuntu`, його диск: `D:\wsl\Ubuntu\ext4.vhdx`.
- Docker Desktop з інтеграцією у WSL: дистрибутив `docker-desktop` у `D:\wsl\DockerDesktopWSL\main`,
  диск даних — `D:\wsl\DockerDesktopWSL\disk\docker_data.vhdx`. Усередині Ubuntu немає
  `/var/lib/docker`, рушій — Docker Desktop (`docker info` → `Docker Desktop`).
- Модуль Hyper-V для PowerShell встановлено, `Optimize-VHD` доступний (потрібні права адміна).
- Хто тримає WSL запущеною: Docker Desktop, WSL-термінали, PhpStorm/VS Code remote, Codex
  (`codex-windows-sandbox-service`). Перед стисканням їх усі треба закрити.
- `D:\wsl\Ubuntu.tar.gz` — старий `wsl --export` (05.2025), не актуальний бекап.

## Спадщина

- `D:\OS` — Open Server Panel, давно не використовується (останні логи — 02.2026). `modules`,
  `progs` і `userdata` — це сам Open Server; `domains` — ~128 старих проєктів.
- Файли в `D:\OS\domains` належать SID старої інсталяції Windows → git свариться на
  dubious ownership; читати через `git -c safe.directory=*`.
- Багато проєктів із `D:\OS\domains` є і в WSL `~/projects`, але частина старих копій має
  незапушені коміти: перед видаленням потрібен `repo-audit.ps1`.

## Baseline (аудит 2026-10-25)

Вільно 3,8 ГБ зі 195.

| Що | Розмір | Коментар |
|---|---|---|
| `D:\wsl\Ubuntu\ext4.vhdx` | 62,8 ГБ | усередині зайнято 50 ГБ; кеші: yarn 7,8, npm 6,2, JetBrains 3,6, `~/.codex` 2,3 |
| `D:\wsl\DockerDesktopWSL\disk\docker_data.vhdx` | 48,7 ГБ | усередині ~30 ГБ: образи 13,9 (11,9 не використовуються), build cache 10,5, томи 5,2 (53 шт., більшість анонімні) |
| `D:\OS` | 36,9 ГБ | domains 25, modules 7,8, userdata 3,3 |
| `$RECYCLE.BIN` | 11,6 ГБ | кошик поточного користувача |
| `node_modules` / `vendor` поза WSL | ~20 / ~4 ГБ | 163 і 129 папок, переважно `D:\OS\domains` |
| `D:\projects\isosurface-extraction-comparison\.venv` | 5,2 ГБ | |
| Не враховано сканом | ~9 ГБ | найімовірніше `System Volume Information` (тіньові копії) |

Станом на 2026-10-27 кеші yarn і npm усередині Ubuntu вже почищено: зайнято 37 ГБ.
