# k8s-vagrant-lab

Локальный учебный Kubernetes-стенд на Windows 11 Home + VirtualBox + Vagrant.

Проект устроен по этапам:

- `stage1` — учебный сценарий с максимально прозрачной логикой, подробными комментариями и ручной проверкой;
- `stage2` — следующий уровень автоматизации и упаковки;
- `docs/` — учебные и справочные материалы по запуску, архитектуре и диагностике.

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

## Что поднимается в Stage 1

Учебный `stage1` создаёт три ноды:

- `k8s-master`
- `k8s-worker1`
- `k8s-worker2`

Сетевые адреса:

- `192.168.56.10` — master
- `192.168.56.11` — worker1
- `192.168.56.12` — worker2

Основные проброшенные порты:

- `2232` — SSH master
- `2242` — SSH worker1
- `2252` — SSH worker2
- `6443` — Kubernetes API
- `30443` — Kubernetes Dashboard

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

Точка и пробел перед путём означают `dot-sourcing`: скрипт выполняется в текущей PowerShell-сессии и оставляет переменную `KUBECONFIG` доступной после завершения.

### Что можно проверить из Windows

```powershell
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get ns
kubectl get all -n smoke-tests -o wide
kubectl get svc -n kubernetes-dashboard
kubectl cluster-info
```

Если эти команды работают из Windows PowerShell, значит host-side доступ к `stage1`-кластеру настроен правильно.

---

## Проверка smoke-проекта из Windows

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

Как читать результат:

- `nginx-smoke` должен быть `3/3`;
- `nginx-smoke-check` должен быть `Complete`;
- сервис `nginx-smoke` должен иметь реальные `Endpoints`;
- ранние ошибки `curl` в логах `Job` допустимы, если сам `Job` уже завершился успешно.

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

После `destroy` сценарий должен очищать:

- локальный `.vagrant`;
- `join-command.sh`;
- токен экземпляра кластера;
- пул host-портов;
- временные runtime-хвосты текущего запуска.

---

## Документация

- [Stage 1 README](K:\repositories\git\ipr\crm\stage1\README.md)
- [Быстрый старт](K:\repositories\git\ipr\crm\docs\quickstart.md)
- [Архитектура](K:\repositories\git\ipr\crm\docs\architecture.md)
- [Устранение неисправностей](K:\repositories\git\ipr\crm\docs\troubleshooting.md)
- [Тезаурус](K:\repositories\git\ipr\crm\docs\thesaurus.md)
