# personal-skills

Особистий маркетплейс плагінів Claude Code. Один плагін — `munspel`, скіли викликаються як
`munspel:<скіл>`.

| Скіл | Що робить |
|---|---|
| `munspel:disk-cleanup` | Аудит місця на дисках Windows + WSL2 + Docker Desktop: великі папки, роздуті VHDX, кеші, Docker, node_modules/vendor, старі проєкти з перевіркою git. Claude лише аналізує й готує команди; очищення і стискання VHDX запускаєш ти. |
| `munspel:academic-draft` | Наукові статті й тези: IMRaD/CARS, APA/IEEE, 7-розділова схема фахових видань, текст українською. |

## Встановлення

```bash
claude plugin marketplace add lisnayk/personal-skills
claude plugin install munspel@personal-skills
```

Або всередині сесії: `/plugin marketplace add lisnayk/personal-skills`, потім
`/plugin install munspel@personal-skills`.

## Відновлення на чистій машині

Додай у `~/.claude/settings.json` (злити з наявними ключами):

```json
{
  "extraKnownMarketplaces": {
    "personal-skills": {
      "source": { "source": "github", "repo": "lisnayk/personal-skills" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "munspel@personal-skills": true
  }
}
```

Під час старту сесії Claude Code сам склонує маркетплейс і встановить плагін. `autoUpdate`
вмикає автооновлення: для сторонніх маркетплейсів воно за замовчуванням вимкнене.

## Оновлення

У маніфестах навмисно немає `version`: версією слугує SHA коміту, тож кожен пуш — нова
версія. Підтягнути вручну:

```bash
claude plugin marketplace update personal-skills
claude plugin update munspel@personal-skills
```

Потім `/reload-plugins` або нова сесія.

## Розробка

```text
.claude-plugin/marketplace.json     каталог маркетплейсу
plugins/munspel/
  .claude-plugin/plugin.json        маніфест плагіна
  skills/<скіл>/SKILL.md            скіли (+ scripts/, references/, assets/)
```

Перевірка перед пушем:

```bash
claude plugin validate .
claude plugin validate ./plugins/munspel
```

PowerShell-скрипти зберігай у UTF-8 **з BOM**: Windows PowerShell 5.1 без BOM читає файл у
системному кодуванні й ламає кириличні рядки.

Репозиторій публічний: не клади сюди токени, ключі й дані, за якими можна впізнати машину.
