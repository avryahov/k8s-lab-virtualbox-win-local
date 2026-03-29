# Kubernetes Cluster — Stage 1 (учебный сценарий)

> **Это Stage 1.**
> Здесь всё намеренно максимально прямолинейно: фиксированные имена нод, фиксированные IP, подробные комментарии и пошаговый сценарий.
> Цель Stage 1 — не «спрятать сложность», а показать ученику, из каких шагов реально собирается рабочий Kubernetes-кластер.

---

## Что получится в конце

После запуска у тебя будет локальный кластер из трёх виртуальных машин:

- `k8s-master` — управляющая нода;
- `k8s-worker1` — рабочая нода;
- `k8s-worker2` — рабочая нода.

После финальной post-bootstrap настройки ты увидишь:

- 3 ноды в состоянии `Ready`;
- Pod-сеть Calico;
- тестовый namespace `smoke-tests`;
- приложение `nginx-smoke`;
- веб-интерфейс Kubernetes Dashboard.

---

## Самый короткий ручной запуск

Открой PowerShell именно в папке `stage1` и выполни:

```powershell
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

Или просто запусти:

```powershell
.\launch.bat
```

`launch.bat` — это удобная учебная обёртка, которая выполнит те же шаги автоматически.

После этого:

1. открой `https://localhost:30443`;
2. подтверди переход на страницу с самоподписанным сертификатом;
3. вставь токен, который вывел `run-post-bootstrap.ps1`;
4. в Dashboard проверь:
   - раздел `Nodes` — там должны быть 3 ноды;
   - namespace `smoke-tests` — там должен быть `Deployment`, `Service` и завершившийся `Job`.

---

## Что делает каждая команда

### `vagrant up`

Эта команда:

1. создаёт 3 виртуальные машины в VirtualBox;
2. подготавливает на них Linux, containerd, kubeadm, kubelet и kubectl;
3. выполняет `kubeadm init` на master;
4. присоединяет worker-ноды через `kubeadm join`.

Это базовый bootstrap кластера.
После него кластер уже существует, но учебный сценарий ещё не завершён.

### `run-post-bootstrap.ps1`

Эта команда завершает сценарий в правильном учебном порядке:

1. проверяет, что все 3 ноды зарегистрировались;
2. доводит сетевую часть и Calico;
3. применяет smoke-тест из корня проекта;
4. ждёт успешного завершения smoke-проверки;
5. только потом устанавливает Dashboard.

Именно поэтому Dashboard не ставится в начале:
сначала мы должны доказать, что работает сам кластер, а уже потом добавлять удобный веб-интерфейс.

---

## Ручная проверка без Dashboard

Если хочешь быстро проверить кластер в консоли:

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A -o wide"
```

Что должно быть:

- `k8s-master`, `k8s-worker1`, `k8s-worker2` — `Ready`;
- `calico-system` — Pod-ы `Running`;
- `smoke-tests` — `nginx-smoke` в `Running`, `nginx-smoke-check` в `Completed`;
- `kubernetes-dashboard` — Pod-ы `Running`.

---

## Где смотреть в браузере

Dashboard доступен по адресу:

`https://localhost:30443`

Важно:

- используется `HTTPS`, не `HTTP`;
- браузер предупредит о самоподписанном сертификате — для учебной локальной лаборатории это нормально;
- токен входа выводится в конце `run-post-bootstrap.ps1`.

Если токен потерялся, его можно получить заново:

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
```

---

## Полный сброс и повторный старт

Если нужно удалить текущий кластер и начать заново:

```powershell
vagrant destroy -f
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

После `destroy` сценарий теперь чистит:

- виртуальные машины текущего `stage1`;
- `join-command.sh`;
- локальный runtime-каталог `.vagrant`;
- токен экземпляра кластера;
- зафиксированный пул host-портов;
- временные Vagrant-ключи и служебные хвосты.

То есть следующий запуск идёт уже без мусора от предыдущего стенда.

---

## Частые вопросы

### Почему ноды могут не сразу стать `Ready`?

Потому что после присоединения worker-нод Kubernetes ещё ждёт готовности Pod-сети.
Calico может стартовать не мгновенно, поэтому в post-bootstrap сценарии есть ожидания и повторные проверки.

### Почему Dashboard ставится не сразу?

Потому что Dashboard — это удобство, а не основа жизнеспособности кластера.
Учебно и технически правильнее сначала проверить сам кластер и простое приложение.

### Почему в smoke-тесте именно `nginx`?

Потому что это простой и понятный пример:

- `Deployment` показывает, что Pod-ы запускаются;
- `Service` показывает, что сервисная сеть работает;
- `Job` проверяет доступность сервиса изнутри кластера.

---

## Что читать дальше

- [Быстрый старт](K:\repositories\git\ipr\crm\docs\quickstart.md)
- [Архитектура](K:\repositories\git\ipr\crm\docs\architecture.md)
- [Устранение неисправностей](K:\repositories\git\ipr\crm\docs\troubleshooting.md)
- [Список литературы и источников](K:\repositories\git\ipr\crm\docs\references.md)
