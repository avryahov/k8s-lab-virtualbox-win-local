# k8s-vagrant-lab

Локальный учебный Kubernetes-стенд на Windows 11 Home + VirtualBox + Vagrant.

Проект устроен по этапам:

- `stage1` — учебный сценарий с максимально прозрачной логикой, подробными комментариями и ручной проверкой;
- `stage2` — следующий уровень автоматизации и упаковки;
- `docs/` — учебные и справочные материалы по запуску, архитектуре и диагностике.

---

## Честная пометка о происхождении и проверке

На текущем этапе значительная часть структуры, сценариев, комментариев и документации в этом репозитории была подготовлена с помощью нейросетевых ассистентов.

Это важно фиксировать прямо и без украшений:

- наличие рабочего сценария ещё не означает полноценную реальную эксплуатационную зрелость;
- локальная техническая проверка и ручной smoke-тест уже были выполнены;
- полноценное чек-ревью и верификация от независимых реальных пользователей пока не получены;
- поэтому любые учебные и инженерные выводы пока нужно считать предварительно подтверждёнными, а не окончательно доказанными практикой.

---

## Система статусов артефактов

### Зрелость

- `BACKLOG`
- `DRAFT`
- `IN_PROGRESS`
- `REVIEW`
- `VERIFIED`
- `PRACTICED`

### Происхождение

- `AI_ASSISTED`
- `HUMAN_AUTHORED`
- `HYBRID`

### Проверка

- `SELF_CHECKED`
- `PEER_REVIEWED`
- `USER_VALIDATED`
- `FIELD_PROVEN`

Минимальная честная карточка для артефакта:

```text
Maturity: VERIFIED
Origin: HYBRID
Verification: SELF_CHECKED
Real-user validation: NO
```

Для текущего `stage1` честная формулировка сейчас такая:

```text
Maturity: VERIFIED
Origin: HYBRID
Verification: SELF_CHECKED
Real-user validation: NO
```

---

## C1: Контекст проекта

```mermaid
flowchart LR
    student["Ученик / пользователь"]
    host["Windows 11 Host"]
    vagrant["Vagrant"]
    vbox["VirtualBox"]
    stage1["Stage 1\nУчебный кластер"]
    stage2["Stage 2\nАвтоматизация и упаковка"]
    docs["docs/\nГайды, архитектура, troubleshooting"]
    dashboard["Kubernetes Dashboard"]
    kubectl["Windows kubectl"]

    student --> host
    host --> vagrant
    vagrant --> vbox
    vbox --> stage1
    vbox --> stage2
    stage1 --> dashboard
    host --> kubectl
    kubectl --> stage1
    student --> docs
    docs --> stage1
    docs --> stage2
```

Эта диаграмма показывает проект целиком:

- пользователь работает на Windows-хосте;
- Vagrant управляет VirtualBox;
- в VirtualBox поднимаются сценарии `stage1` и позже `stage2`;
- документация объясняет, как пользоваться и как проверять результат;
- `kubectl` и Dashboard дают два разных способа видеть один и тот же кластер.

---

## C2: Контейнеры внутри репозитория

```mermaid
flowchart TB
    repo["Репозиторий k8s-vagrant-lab"]
    rootReadme["README.md\nОбщий обзор и статусы"]
    status["STATUS.md\nТекущее состояние работ"]
    stage1["stage1/\nУчебный сценарий"]
    stage2["stage2/\nРасширенный сценарий"]
    smoke["smoke-tests/\nТестовые манифесты"]
    docs["docs/\nАрхитектура, quickstart, troubleshooting, thesaurus"]

    repo --> rootReadme
    repo --> status
    repo --> stage1
    repo --> stage2
    repo --> smoke
    repo --> docs
    stage1 --> smoke
    docs --> stage1
    docs --> stage2
```

---

## Flow: Учебный путь пользователя

```mermaid
flowchart TD
    start["Старт работы с проектом"]
    choose["Выбор сценария"]
    s1["Stage 1"]
    s2["Stage 2"]
    up["vagrant up / launch.bat"]
    post["run-post-bootstrap.ps1"]
    smoke["Smoke-тест"]
    dash["Dashboard"]
    hostkubectl["Windows kubectl"]
    docs["Чтение docs/"]

    start --> choose
    choose --> s1
    choose --> s2
    s1 --> up
    up --> post
    post --> smoke
    smoke --> dash
    dash --> hostkubectl
    s1 --> docs
    s2 --> docs
```

---

## Timeline: Дорожная карта работ

```mermaid
timeline
    title Дорожная карта проекта
    section Stage 1
      Подъём master и worker : завершено
      Calico и smoke-тест : завершено
      Dashboard и Windows kubectl : завершено
      Учебная документация : в развитии
    section Stage 2
      Перенос практик stage1 : backlog
      Проверка .env и installer-сценариев : backlog
      Расширенная валидация : backlog
    section Future
      Золотой образ : backlog
      Packer-пайплайн : backlog
      Перенос практик в другие проекты : backlog
```

---

## С чего начинать

Если цель — быстро поднять рабочий кластер, понять его шаги и проверить его из браузера и из терминала Windows, начинать нужно со `stage1`.

Именно там сейчас подтверждён рабочий сценарий:

1. `vagrant up`
2. `powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1`
3. вход в Dashboard
4. проверка `smoke-tests`
5. проверка `kubectl` прямо из Windows PowerShell

---

## Самый короткий запуск Stage 1

```powershell
cd K:\repositories\git\ipr\crm\stage1
.\launch.bat
```

`launch.bat` последовательно делает:

1. `vagrant up`
2. post-bootstrap сценарий
3. настройку Calico
4. smoke-тест `nginx`
5. установку Dashboard
6. подготовку `kubeconfig` для Windows-хоста

Если хочется видеть шаги явно:

```powershell
cd K:\repositories\git\ipr\crm\stage1
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

---

## Проверка через браузер

Открой:

`https://localhost:30443`

После входа нужно увидеть:

- 3 ноды в разделе `Nodes`;
- namespace `smoke-tests`;
- развёрнутый `nginx-smoke`;
- завершившийся `nginx-smoke-check`.

---

## Работа с `kubectl` прямо из Windows PowerShell

После успешного `run-post-bootstrap.ps1` сценарий `stage1` автоматически создаёт локальный host-side файл:

`K:\repositories\git\ipr\crm\stage1\kubeconfig-stage1.yaml`

Этот файл позволяет использовать обычный `kubectl` прямо из Windows PowerShell, без `vagrant ssh`.

### Подключение вручную

```powershell
$env:KUBECONFIG = "K:\repositories\git\ipr\crm\stage1\kubeconfig-stage1.yaml"
```

### Подключение через helper

```powershell
cd K:\repositories\git\ipr\crm\stage1
. .\scripts\use-stage1-kubectl.ps1
```

### Что можно проверить из Windows

```powershell
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get ns
kubectl get all -n smoke-tests -o wide
kubectl get svc -n kubernetes-dashboard
kubectl cluster-info
```

---

## Если нужно начать заново

```powershell
cd K:\repositories\git\ipr\crm\stage1
vagrant destroy -f
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

Если `destroy` был прерван или машины удалялись вручную через VirtualBox, сначала очисти локальное состояние `stage1`:

```powershell
cd K:\repositories\git\ipr\crm\stage1
Remove-Item -Recurse -Force .\.vagrant -ErrorAction SilentlyContinue
Remove-Item -Force .\join-command.sh -ErrorAction SilentlyContinue
```

---

## Документация

- [Stage 1 README](K:\repositories\git\ipr\crm\stage1\README.md)
- [Stage 2 README](K:\repositories\git\ipr\crm\stage2\README.md)
- [Быстрый старт](K:\repositories\git\ipr\crm\docs\quickstart.md)
- [Архитектура](K:\repositories\git\ipr\crm\docs\architecture.md)
- [Устранение неисправностей](K:\repositories\git\ipr\crm\docs\troubleshooting.md)
- [Тезаурус](K:\repositories\git\ipr\crm\docs\thesaurus.md)
