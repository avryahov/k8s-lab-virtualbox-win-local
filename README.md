# k8s-vagrant-lab

Локальный учебный Kubernetes-стенд на Windows 11 Home + VirtualBox + Vagrant.

Проект устроен по этапам:

- `stage1` — учебный сценарий с максимально прозрачной логикой;
- `stage2` — следующий уровень автоматизации и упаковки;
- `docs/` — справочные и учебные материалы по запуску, архитектуре и диагностике.

---

## Что важно знать сразу

Если цель — поднять кластер руками, понять его шаги и быстро проверить его в браузере, начинать нужно со `stage1`.

Именно там сейчас подтверждён рабочий сценарий:

1. `vagrant up`
2. `run-post-bootstrap.ps1`
3. вход в Dashboard и проверка smoke-проекта

---

## Самый короткий запуск Stage 1

```powershell
cd K:\repositories\git\ipr\crm\stage1
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

Или одной командой:

```powershell
cd K:\repositories\git\ipr\crm\stage1
.\launch.bat
```

После этого:

- открой `https://localhost:30443`;
- возьми токен из вывода второго скрипта;
- в Dashboard проверь 3 ноды;
- в namespace `smoke-tests` проверь тестовый `nginx`-проект.

---

## Что именно поднимается

Учебный `stage1` создаёт:

- `k8s-master`
- `k8s-worker1`
- `k8s-worker2`

Сетевые параметры:

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

## Почему запуск разделён на 2 команды

Потому что проект учебный, и здесь важно показать ученику два разных слоя:

1. как поднимается сам кластер;
2. как поверх него уже добавляются сеть, smoke-проверка и Dashboard.

Поэтому:

- `vagrant up` создаёт и собирает базовый кластер;
- `run-post-bootstrap.ps1` завершает сценарий в правильном порядке:
  - Calico;
  - smoke-тест;
  - Dashboard.

---

## Как проверить, что всё действительно работает

### В терминале

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A -o wide"
```

### В браузере

Открой:

`https://localhost:30443`

Там должны быть:

- 3 ноды;
- Pod-ы Dashboard;
- namespace `smoke-tests`;
- `nginx-smoke`;
- завершившийся `nginx-smoke-check`.

---

## Полный сброс

Если нужно начать заново:

```powershell
cd K:\repositories\git\ipr\crm\stage1
vagrant destroy -f
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

`stage1` после `destroy` должен чистить:

- локальный `.vagrant`;
- `join-command.sh`;
- токен экземпляра кластера;
- пул host-портов;
- временные runtime-хвосты текущего учебного запуска.

---

## Документация

- [Stage 1 README](K:\repositories\git\ipr\crm\stage1\README.md)
- [Быстрый старт](K:\repositories\git\ipr\crm\docs\quickstart.md)
- [Архитектура](K:\repositories\git\ipr\crm\docs\architecture.md)
- [Устранение неисправностей](K:\repositories\git\ipr\crm\docs\troubleshooting.md)
- [Список литературы и источников](K:\repositories\git\ipr\crm\docs\references.md)
