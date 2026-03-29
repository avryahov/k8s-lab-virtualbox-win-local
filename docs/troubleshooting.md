# Устранение неисправностей

> Базовый принцип диагностики:
> сначала понять, на каком этапе произошёл сбой.
>
> В `stage1` этапов два:
> 1. `vagrant up`
> 2. `run-post-bootstrap.ps1`

---

## Сбой на `vagrant up`

Если кластер не поднялся ещё до post-bootstrap, проверь:

```powershell
vagrant status
```

Потом зайди на master:

```powershell
vagrant ssh k8s-master
```

И уже внутри master проверь:

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A -o wide
systemctl status kubelet --no-pager
journalctl -u kubelet -n 50 --no-pager
```

---

## Ноды не стали `Ready`

Сначала посмотри:

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n calico-system -o wide"
```

Частая причина:

- кластер уже создан;
- но Calico ещё не успел полностью выйти в рабочее состояние.

Для этого в post-bootstrap уже есть ожидания.
Если ты проверяешь вручную сразу после запуска, просто подожди ещё 2-5 минут.

---

## Smoke-тест не проходит

Сначала посмотри ресурсы namespace `smoke-tests`:

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get all -n smoke-tests -o wide"
```

Если `Job` не завершился:

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs job/nginx-smoke-check -n smoke-tests"
```

Если `Deployment` не стал доступен:

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl describe deployment nginx-smoke -n smoke-tests"
```

Что это обычно значит:

- сеть между нодами ещё не готова;
- Service ещё не начал направлять трафик;
- Calico ещё не дошёл до полного `Running`.

---

## Dashboard не открывается

Проверь URL:

`https://localhost:30443`

Важно:

- только `HTTPS`;
- предупреждение о сертификате для учебной локальной лаборатории нормально;
- токен надо брать из вывода post-bootstrap или генерировать вручную.

Проверка Pod-ов Dashboard:

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n kubernetes-dashboard -o wide"
```

Получение нового токена:

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
```

---

## `vagrant up` или `vagrant ssh` ругается на каталог или кавычки

Для этого проекта важно помнить правила Windows PowerShell:

- запускать команды нужно из правильной папки;
- для `stage1` это `K:\repositories\git\ipr\crm\stage1`;
- в Windows PowerShell 5 нельзя использовать `&&`;
- сложные команды лучше выносить в `.ps1`, а не собирать длинной строкой вручную;
- внутри `vagrant ssh ... -c ...` лучше использовать простые и короткие команды.

---

## `destroy` прошёл, но раньше оставался мусор

Сейчас `stage1` должен чистить после `destroy`:

- локальный `.vagrant`;
- `join-command.sh`;
- токен текущего экземпляра;
- файл пула портов;
- служебные runtime-хвосты.

Если нужно проверить руками:

```powershell
Get-ChildItem -Force .
Get-ChildItem -Force .\.vagrant
```

После корректного полного `destroy` в `stage1`:

- `join-command.sh` не должно быть;
- `.vagrant` не должно быть;
- чужие VirtualBox-кластеры трогаться не должны.

---

## Порт занят

Если какая-то команда сообщает, что порт уже используется, проверь:

```powershell
netstat -ano | findstr :2232
netstat -ano | findstr :2242
netstat -ano | findstr :2252
netstat -ano | findstr :6443
netstat -ano | findstr :30443
```

В `stage1` пул портов фиксируется заранее для текущего экземпляра кластера.
Но если нужный порт уже занят другим приложением на host-машине, запуск всё равно может потребовать освобождения этого порта.

---

## Быстрый полный пересоздание сценария

Если нужно просто начать заново:

```powershell
cd K:\repositories\git\ipr\crm\stage1
vagrant destroy -f
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

Это главный ручной сценарий для ученика и для проверки стенда без внешней помощи.
