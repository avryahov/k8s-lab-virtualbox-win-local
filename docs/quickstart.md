# Быстрый старт: Stage 1 на Windows 11 Home

Этот документ описывает самый короткий и при этом правильный ручной запуск учебного `stage1`.

---

## Перед началом

Проверь, что установлены:

```powershell
vagrant --version
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version
```

Что делает каждая команда:

- `vagrant --version` показывает, что Vagrant установлен и виден из терминала;
- `VBoxManage.exe --version` показывает, что VirtualBox установлен и его CLI доступен PowerShell.

---

## Где запускать команды

Все команды ниже нужно выполнять именно из папки:

```powershell
cd K:\repositories\git\ipr\crm\stage1
```

Почему это важно:

- `Vagrantfile` учебного сценария лежит именно в `stage1`;
- host-side `.ps1` сценарии тоже рассчитаны на запуск из этой папки;
- так Vagrant не перепутает текущий сценарий с другими частями проекта.

---

## Минимальный сценарий в 2 команды

```powershell
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

### Что делает первая команда

`vagrant up`:

1. создаёт 3 виртуальные машины;
2. запускает общую подготовку нод;
3. выполняет `kubeadm init` на master;
4. выполняет `kubeadm join` для двух worker-нод.

### Что делает вторая команда

`run-post-bootstrap.ps1`:

1. проверяет, что все 3 ноды зарегистрировались в API;
2. завершает сетевую настройку и Calico;
3. применяет smoke-тест `nginx`;
4. ждёт успешного завершения `nginx-smoke-check`;
5. только потом устанавливает Dashboard;
6. экспортирует `kubeconfig` для Windows-хоста.

---

## Запуск одной командой

Если хочется запустить всё одной строкой и дальше только наблюдать:

```powershell
.\launch.bat
```

`launch.bat` — это учебная обёртка над тем же сценарием.

Она последовательно запускает:

- `vagrant up`
- `run-post-bootstrap.ps1`
- финальные подсказки по Dashboard и Windows `kubectl`

---

## Проверка через браузер

Открой:

`https://localhost:30443`

Потом:

1. подтверди переход через предупреждение браузера;
2. вставь токен из вывода `run-post-bootstrap.ps1`;
3. открой `Nodes` и проверь, что там 3 ноды;
4. открой namespace `smoke-tests` и проверь `nginx-smoke` и `nginx-smoke-check`.

---

## Работа с `kubectl` из Windows PowerShell

После post-bootstrap в `stage1` автоматически появляется локальный файл:

`K:\repositories\git\ipr\crm\stage1\kubeconfig-stage1.yaml`

Он нужен для обычного Windows `kubectl`.

### Подключение вручную

```powershell
$env:KUBECONFIG = "K:\repositories\git\ipr\crm\stage1\kubeconfig-stage1.yaml"
```

### Подключение через helper

```powershell
. .\scripts\use-stage1-kubectl.ps1
```

Что значит эта команда:

- первая точка говорит PowerShell выполнить скрипт в текущей сессии;
- благодаря этому `KUBECONFIG` остаётся установленным и после завершения скрипта;
- дальше обычный `kubectl` уже смотрит именно в `stage1`-кластер.

---

## Базовая проверка из Windows

```powershell
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get ns
kubectl cluster-info
```

Что показывает каждая команда:

- `kubectl get nodes -o wide` — список нод, их роли, IP и состояние `Ready`;
- `kubectl get pods -A -o wide` — все Pod-ы из всех namespace и ноды, на которых они запущены;
- `kubectl get ns` — список namespace;
- `kubectl cluster-info` — адрес API и базовые сервисы кластера.

---

## Проверка smoke-проекта

```powershell
kubectl get all -n smoke-tests -o wide
kubectl get deployment nginx-smoke -n smoke-tests
kubectl get pods -n smoke-tests -o wide
kubectl get svc -n smoke-tests
kubectl get job nginx-smoke-check -n smoke-tests
kubectl logs job/nginx-smoke-check -n smoke-tests
kubectl describe deployment nginx-smoke -n smoke-tests
kubectl describe svc nginx-smoke -n smoke-tests
kubectl get endpoints nginx-smoke -n smoke-tests
```

Что значит каждая команда:

- `kubectl get all -n smoke-tests -o wide` — сводка всех основных ресурсов тестового проекта;
- `kubectl get deployment nginx-smoke -n smoke-tests` — готовность и число реплик приложения;
- `kubectl get pods -n smoke-tests -o wide` — сами Pod-ы и ноды, на которых они работают;
- `kubectl get svc -n smoke-tests` — сервис, через который приложение доступно внутри кластера;
- `kubectl get job nginx-smoke-check -n smoke-tests` — статус одноразовой проверки;
- `kubectl logs job/nginx-smoke-check -n smoke-tests` — подробности работы проверочного `Job`;
- `kubectl describe deployment nginx-smoke -n smoke-tests` — развёрнутое описание Deployment;
- `kubectl describe svc nginx-smoke -n smoke-tests` — развёрнутое описание Service и его Endpoints;
- `kubectl get endpoints nginx-smoke -n smoke-tests` — реальные IP Pod-ов за сервисом.

Как читать результат:

- `nginx-smoke` должен быть `3/3`;
- `nginx-smoke-check` должен быть `Complete`;
- сервис `nginx-smoke` должен иметь реальные `Endpoints`;
- ранние ошибки `curl` в логах `Job` допустимы, если сам `Job` уже завершился успешно.

---

## Если нужно получить токен Dashboard ещё раз

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
```

Что делает эта команда:

- заходит на master через Vagrant;
- использует системный `admin.conf` внутри master-ноды;
- создаёт новый токен для `admin-user` на 24 часа.

---

## Если нужно начать заново

```powershell
vagrant destroy -f
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

Если `vagrant destroy -f` упал, завис или был прерван, сначала вручную очисти локальное состояние `stage1`:

```powershell
Remove-Item -Recurse -Force .\.vagrant -ErrorAction SilentlyContinue
Remove-Item -Force .\join-command.sh -ErrorAction SilentlyContinue
```

И только потом запускай новый `vagrant up`.

---

## Что читать дальше

- [README](K:\repositories\git\ipr\crm\README.md)
- [Stage 1 README](K:\repositories\git\ipr\crm\stage1\README.md)
- [Архитектура](K:\repositories\git\ipr\crm\docs\architecture.md)
- [Устранение неисправностей](K:\repositories\git\ipr\crm\docs\troubleshooting.md)
- [Тезаурус](K:\repositories\git\ipr\crm\docs\thesaurus.md)
