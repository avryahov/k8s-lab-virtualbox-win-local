# STATUS

## Назначение файла

Этот файл — живая точка синхронизации для пользователя и любого следующего ассистента.

Здесь фиксируются:

- текущий этап работ;
- уже подтверждённые результаты;
- незавершённые задачи;
- согласованный порядок следующих шагов;
- важные правила проекта и процесса.

---

## Главная цель проекта

Проект должен быть одновременно:

- рабочим учебным Kubernetes-стендом;
- понятным учебным материалом для школьников и начинающих.

Это означает два обязательных требования:

- кластер должен стабильно подниматься и работать;
- Vagrantfile, shell-скрипты, PowerShell-скрипты и документы должны объяснять, что происходит и зачем.

---

## Система статусов проекта

Базовая система статусов:

### Зрелость

`BACKLOG` → `DRAFT` → `IN_PROGRESS` → `REVIEW` → `VERIFIED` → `PRACTICED`

### Происхождение

`AI_ASSISTED` / `HUMAN_AUTHORED` / `HYBRID`

### Проверка

`SELF_CHECKED` → `PEER_REVIEWED` → `USER_VALIDATED` → `FIELD_PROVEN`

---

## Текущий этап

Оба stage полностью рабочие. Текущая работа — фиксация учебных комментариев и документации.

Согласованный порядок:

1. Stage 1 и Stage 2 полностью рабочие (token persistence, idempotency, orphan VM detection)
2. Учебные комментарии расширены во всех скриптах
3. Зафиксировать документацию и комментарии отдельным коммитом
4. Merge в `main`

---

## Текущая ветка

`docs/educational-comments`

---

## Что уже работает в `stage1`

```text
Maturity: VERIFIED
Origin: HYBRID
Verification: SELF_CHECKED
Real-user validation: NO
```

Подтверждено:

- 3 ноды (`k8s-master`, `k8s-worker1`, `k8s-worker2`) в `Ready`
- Calico CNI работает на всех нодах
- Smoke-тест `nginx-smoke` проходит успешно
- Dashboard доступен по `https://localhost:30443`
- Токен Dashboard сохраняется в `stage1/dashboard-token.txt`
- `kubeconfig` экспортируется на хост, `kubectl` работает из Windows
- **Идемпотентность**: повторный запуск `launch.bat` пропускает готовые фазы и показывает токен
- **Orphan VM detection**: при старте проверяются «хвосты» от предыдущих запусков

---

## Что уже работает в `stage2`

```text
Maturity: VERIFIED
Origin: HYBRID
Verification: SELF_CHECKED
Real-user validation: NO
```

Подтверждено:

- Динамическое количество worker-нод (через `.env` или `proxy-launch.bat`)
- SSH-ключи ed25519 вместо пароля
- Токен Dashboard сохраняется в `stage2/dashboard-token.txt`
- **Идемпотентность**: Фаза 0 проверяет готовность кластера и пропускает лишнее
- **Ready marker**: `.vagrant/stage2-ready` с таймстампом
- Дефолты: Ubuntu 24.04, CPU=2, RAM=2048 (согласованы с proxy-launch.bat)

---

## Что изменено в `stage1` (полный список)

| Файл | Что сделано |
|------|-------------|
| `Vagrantfile` | Уникальный cluster token, пул host-портов, orphan VM cleanup triggers, учебные комментарии |
| `scripts/common.sh` | Идемпотентный gpg, `--yes` для перезаписи keyring |
| `scripts/master.sh` | Calico через Tigera Operator, Dashboard отложен до post-bootstrap |
| `scripts/worker.sh` | Ожидание join-command.sh, идемпотентность |
| `scripts/finalize-cluster.sh` | Отдельная post-join финализация сети, ожидание нод, Calico, Ready-проверки |
| `scripts/install-dashboard.sh` | Helm chart, **токен ВСЕГДА генерируется и сохраняется в `/vagrant/dashboard-token.txt`** |
| `scripts/run-post-bootstrap.ps1` | **Фаза 0** (идемпотентность), 7 фаз, Show-DashboardToken, ready marker |
| `scripts/export-host-kubeconfig.ps1` | Экспорт kubeconfig на хост (127.0.0.1:6443) |
| `scripts/use-stage1-kubectl.ps1` | Helper для быстрой установки KUBECONFIG |
| `scripts/cleanup-stage1-runtime.ps1` | Очистка артефактов после destroy (включая dashboard-token.txt) |
| `scripts/cleanup-vbox-tail.ps1` | Точечная очистка orphan-VM |
| `launch.bat` | **Проверка состояния кластера** перед запуском, **orphan VM detection**, показ токена |

---

## Что изменено в `stage2` (полный список)

| Файл | Что сделано |
|------|-------------|
| `Vagrantfile` | Динамическая конфигурация через `.env`, SSH-ключи, дефолты: Ubuntu 24.04, CPU=2, RAM=2048 |
| `scripts/common.sh` | Параметризация через аргументы, SSH-key injection, `sed -i` без `.bak` |
| `scripts/master.sh` | `--server-side --force-conflicts` для Calico, `sleep 180` после Tigera Operator, `--duration=24h` для токена |
| `scripts/worker.sh` | Проверка `-s` (не пустой), улучшенная диагностика |
| `scripts/finalize-cluster.sh` | Исправлен баг `grep -c` (убран дублированный вывод) |
| `scripts/install-dashboard.sh` | **Токен ВСЕГДА генерируется и сохраняется в `/vagrant/dashboard-token.txt`** |
| `scripts/run-post-bootstrap.ps1` | **Фаза 0** (идемпотентность), Show-DashboardToken, ready marker, Фаза 5b |
| `scripts/export-host-kubeconfig.ps1` | Динамическое имя ВМ из `.env` вместо хардкода |
| `scripts/use-stage2-kubectl.ps1` | `$ErrorActionPreference`, параметр `$ConfigPath`, `throw` при ошибке |
| `proxy-launch.bat` | Показ токена после завершения, очистка артефактов при destroy |

---

## Согласованная логика этапов

```
1. Поднять ноды (vagrant up)
2. kubeadm init на master
3. kubeadm join для worker-нод
4. Настроить Pod-сеть (Calico)
5. Прогнать smoke-тест
6. Установить Dashboard
7. Сгенерировать и сохранить токен
8. Экспортировать kubeconfig для Windows
9. Проверить кластер через kubectl из Windows
```

---

## Критерий готовности

Текущий этап завершён, когда:

1. `stage1` поднимается с нуля через `launch.bat`
2. `stage2` поднимается через `proxy-launch.bat`
3. Master и worker-ноды переходят в `Ready`
4. Calico стабильно работает
5. Smoke-тест проходит
6. Dashboard доступен, токен сохранён в файле
7. Windows `kubectl` работает
8. Повторный запуск пропускает готовые фазы и показывает токен
9. Комментарии понятны школьнику

---

## Stage 2 — Дорожная карта

| Этап | Название | Статус |
|------|----------|--------|
| 1 | SSH-ключи вместо пароля | ✅ Готово |
| 2 | Параллельный provisioning | ✅ Готово |
| 3 | Конфигурируемые параметры (.env) | ✅ Готово |
| 4 | Учебные комментарии и документация | 🔄 In Progress |
| 5 | Packer-билд золотого образа | ⏳ Backlog |
| 6 | NSIS-wizard / Launcher GUI | ⏳ Backlog |
| 7 | Linked Clones | ⏳ Backlog |

---

## Правила проекта

### Git-flow

- `main` → продакшн
- `develop` → интеграция
- `feature/*` → новая функциональность
- `bugfix/*` → исправления
- Не более 6 файлов в коммите
- Сообщения коммитов на английском
- Merge только через `--no-ff`
- Никаких destructive операций без разрешения

### PowerShell

- Нельзя использовать `&&` в PowerShell 5
- Вложенные кавычки в `vagrant ssh` упрощать
- Сложные команды выносить в `.ps1`

### Язык

Все ответы — на русском языке.
Исключение: код, CLI-команды, пути, логи, идентификаторы.
