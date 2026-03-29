# Устранение неисправностей

Этот документ нужен для типовых проблем `stage1` на Windows 11 Home + VirtualBox + Vagrant.

Все команды ниже нужно выполнять из:

```powershell
cd K:\repositories\git\ipr\crm\stage1
```

---

## `vagrant destroy -f` упал или был прерван

Это аварийный сценарий.
В таком случае не надо сразу запускать новый `vagrant up`, потому что `stage1` может упереться в старое локальное состояние.

Сделай ручную очистку только для `stage1`:

```powershell
Remove-Item -Recurse -Force .\.vagrant -ErrorAction SilentlyContinue
Remove-Item -Force .\join-command.sh -ErrorAction SilentlyContinue
```

После этого можно запускать заново:

```powershell
.\launch.bat
```

Или вручную:

```powershell
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

Важно:

- удаляй только машины текущего `stage1`;
- не трогай старые чужие VirtualBox-кластеры.

---

## `kubectl` из Windows не видит stage1-кластер

Симптомы:

- `kubectl get nodes` пытается идти в `localhost:8080`;
- `kubectl` пишет про отсутствие подходящего контекста;
- Windows PowerShell не видит `stage1`, хотя сам кластер уже работает.

Причина:

Windows-сессия ещё не подключена к `stage1`-`kubeconfig`.

Решение вручную:

```powershell
$env:KUBECONFIG = "K:\repositories\git\ipr\crm\stage1\kubeconfig-stage1.yaml"
```

Решение через helper:

```powershell
. .\scripts\use-stage1-kubectl.ps1
```

Проверка:

```powershell
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl cluster-info
```

Важно:

- `kubeconfig-stage1.yaml` создаётся автоматически post-bootstrap-сценарием;
- это локальный runtime-файл текущего ПК, поэтому он не коммитится в git;
- helper меняет только текущую PowerShell-сессию.

---

## В логах `nginx-smoke-check` есть ошибки `curl`

Симптом:

```powershell
kubectl logs job/nginx-smoke-check -n smoke-tests
```

может показать первые неудачные подключения к `nginx-smoke`.

Причина:

`Job` стартует очень быстро и может сделать первые обращения к сервису раньше, чем `nginx` и Service полностью прогреются.

Когда это нормально:

```powershell
kubectl get job nginx-smoke-check -n smoke-tests
kubectl get endpoints nginx-smoke -n smoke-tests
```

Если `Job` уже `Complete`, а у сервиса есть `Endpoints`, то ранние ошибки в логах не означают поломку smoke-сценария.

---

## Предупреждение про deprecated `Endpoints`

Симптом:

```powershell
kubectl get endpoints nginx-smoke -n smoke-tests
```

может показать предупреждение, что `v1 Endpoints` устаревает.

Что это значит:

Это не поломка кластера. Команда по-прежнему полезна как учебная быстрая проверка, потому что наглядно показывает IP Pod-ов за сервисом.

Современный дополнительный вариант:

```powershell
kubectl get endpointslices -n smoke-tests
```

---

## `kubectl top` не работает

Симптом:

```powershell
kubectl top nodes
kubectl top pods -A
```

могут возвращать `Metrics API not available`.

Причина:

В `stage1` сейчас не установлен `metrics-server`.

Что это означает:

- это не поломка базового кластера;
- это означает только отсутствие отдельного компонента метрик;
- для проверки рабочего состояния `stage1` это не блокер.

---

## Dashboard не открывается

Проверь:

```powershell
kubectl get svc -n kubernetes-dashboard
kubectl get pods -n kubernetes-dashboard -o wide
```

Нормальный результат:

- сервис `kubernetes-dashboard-kong-proxy` имеет `NodePort 30443`;
- Pod-ы `kubernetes-dashboard-*` находятся в `Running`.

После этого открывай:

`https://localhost:30443`

Важно:

- используется именно `https`;
- предупреждение о самоподписанном сертификате для локального учебного стенда нормально.
