# AGENTS.md — правила работы ИИ-ассистента

Этот файл содержит аксиомы, которые Codex обязан соблюдать при работе в этом репозитории.
Читается автоматически при каждом запуске Codex.

---

## Язык

Все ответы — **на русском языке**.
Исключение: код, CLI-команды, пути файлов, stack trace, JSON-ключи, идентификаторы, точные цитаты.

---

## Git-flow — КАТЕГОРИЧЕСКИЕ ПРАВИЛА

### Структура веток

```
main        — продакшн, только через merge из develop
develop     — интеграция, только через merge из feature/*
feature/*   — новая функциональность
bugfix/*    — исправления в develop
hotfix/*    — срочные исправления в main
```

### Правила коммитов

| Правило | Ограничение | Последствие нарушения |
|---|---|---|
| Файлов в коммите | не более 6 | pre-commit hook блокирует |
| Коммитов на ветку | не более 20 | pre-commit hook блокирует |
| Коммитов на ветку | не менее 3 | ветка не принимается в merge |
| Язык сообщений | только английский | — |

### Формат сообщения коммита

```
feature/branch-name: brief imperative description

Optional body explaining what and why (not how).

Co-Authored-By: Codex Sonnet 4.6 <noreply@anthropic.com>
```

Примеры:
- `feature/initial-k8s-lab: add Vagrantfile and env config`
- `bugfix/flannel-cidr: fix pod CIDR mismatch in env example`
- `hotfix/ssh-key-acl: enforce strict ACL on Windows ed25519 keys`

### Merge

```bash
# Всегда --no-ff
git checkout develop
git merge --no-ff feature/branch-name
git branch -d feature/branch-name
```

### Push

Push только в remote `forgejo` (если настроен).
Никогда не делать `git push --force` без явного разрешения пользователя.

---

## Запрет деструктивных операций

Перед ЛЮБЫМ действием, изменяющим историю git:
`git revert` · `git reset --hard` · `git push --force` · удаление коммитов

**Обязательно:**
1. Получить явное разрешение пользователя
2. Объяснить последствия (кто работает в ветке, какие PR затронуты)
3. Предложить альтернативу (fix-forward коммит, новая ветка, soft reset локально)

**Без этого — никаких действий с git-историей.**

---

## Порядок работы в начале сессии

1. Проверить текущую ветку: `git branch --show-current`
2. Проверить количество коммитов на ветке: `git rev-list develop..HEAD --count`
3. Проверить статус: `git status`
4. Только затем — приступать к задаче

---

## Специфика этого репозитория

- **Платформа:** Windows 11 Home + VirtualBox + Vagrant
- **Скрипты provisioning:** bash (Linux inside VMs) + PowerShell (Windows host)
- **Не коммитить:** `.vagrant/`, `.env`, `join-command.sh` (см. `.gitignore`)
- **Идемпотентность:** все provisioning-скрипты должны безопасно выполняться повторно
- **Версии:** Kubernetes `1.34`, Ubuntu `22.04`, containerd, Flannel CNI

---

## Что не нужно делать

- Не добавлять docstrings и комментарии к коду, который не менялся
- Не рефакторить код без явного запроса
- Не добавлять обработку ошибок для сценариев, которые не могут произойти
- Не создавать файлы документации (*.md), если не попросили явно
- Не добавлять эмодзи, если пользователь не просил
