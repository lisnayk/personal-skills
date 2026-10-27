# personal-skills

Личный маркетплейс плагинов Claude Code. Один плагин — `munspel`, скилы вызываются как
`munspel:<скил>`.

| Скил | Что делает |
|---|---|
| `munspel:disk-cleanup` | Аудит места на дисках Windows + WSL2 + Docker Desktop: крупные папки, раздутые VHDX, кэши, Docker, node_modules/vendor, старые проекты с проверкой git. Claude только анализирует и готовит команды; очистку и сжатие VHDX запускаешь ты. |
| `munspel:academic-draft` | Наукові статті й тези: IMRaD/CARS, APA/IEEE, 7-розділова схема фахових видань, текст українською. |

## Установка

```bash
claude plugin marketplace add lisnayk/personal-skills
claude plugin install munspel@personal-skills
```

Или внутри сессии: `/plugin marketplace add lisnayk/personal-skills`, затем
`/plugin install munspel@personal-skills`.

## Восстановление на чистой машине

Добавь в `~/.claude/settings.json` (слить с существующими ключами):

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

При старте сессии Claude Code сам склонирует маркетплейс и поставит плагин. `autoUpdate`
включает автообновление: для сторонних маркетплейсов оно по умолчанию выключено.

## Обновление

В манифестах намеренно нет `version`: версией служит SHA коммита, поэтому каждый пуш —
новая версия. Подтянуть вручную:

```bash
claude plugin marketplace update personal-skills
claude plugin update munspel@personal-skills
```

Затем `/reload-plugins` или новая сессия.

## Разработка

```text
.claude-plugin/marketplace.json     каталог маркетплейса
plugins/munspel/
  .claude-plugin/plugin.json        манифест плагина
  skills/<скил>/SKILL.md            скилы (+ scripts/, references/, assets/)
```

Проверка перед пушем:

```bash
claude plugin validate .
claude plugin validate ./plugins/munspel
```

Репозиторий публичный: не клади сюда токены, ключи и данные, по которым можно опознать машину.
