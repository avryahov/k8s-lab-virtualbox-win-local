# Быстрый старт: K8s Vagrant Lab на Windows 11 Home

## Предварительная проверка

Перед первым запуском убедитесь, что всё установлено:

```powershell
# Проверить VirtualBox
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version
# Ожидается: 7.x.x

# Проверить Vagrant
vagrant --version
# Ожидается: Vagrant 2.4.x

# Проверить ssh-keygen
ssh-keygen --help 2>&1 | Select-String "usage"
# Ожидается: usage: ssh-keygen ...
```

---

## Шаг 1. Клонировать репозиторий

```powershell
git clone <repo-url> k8s-vagrant-lab
cd k8s-vagrant-lab
```

---

## Шаг 2. Создать .env

```powershell
Copy-Item .env.example .env
```

Для первого запуска `.env` можно не трогать — значения по умолчанию работают на чистой машине.

Если порт `2232`, `6443` или `30443` занят другим приложением — измените соответствующую переменную в `.env`:

```
MASTER_SSH_PORT=2232      # SSH к master
MASTER_API_PORT=6443      # Kubernetes API
MASTER_DASHBOARD_PORT=30443
```

---

## Шаг 3. Поднять кластер

```powershell
vagrant up
```

Время первого запуска: **15–25 минут** (скачивание box + установка пакетов).

Что происходит:
1. PowerShell генерирует ed25519 SSH-ключи для каждой ВМ
2. VirtualBox создаёт 3 ВМ (master + 2 workers)
3. `common.sh` — настраивает containerd, kubelet, kubeadm на каждой ноде
4. `master.sh` — запускает `kubeadm init`, применяет Flannel CNI, генерирует `join-command.sh`
5. `worker.sh` — ждёт `join-command.sh` и подключается к кластеру

---

## Шаг 4. Проверить кластер

```powershell
vagrant ssh lab-k8s-master
```

Внутри мастера:

```bash
# Статус нод — все должны быть Ready
kubectl get nodes -o wide

# Системные поды — все должны быть Running или Completed
kubectl get pods -A

# Версия кластера
kubectl version --short
```

Ожидаемый вывод `kubectl get nodes`:

```
NAME              STATUS   ROLES           AGE   VERSION
lab-k8s-master    Ready    control-plane   5m    v1.34.x
lab-k8s-worker1   Ready    <none>          3m    v1.34.x
lab-k8s-worker2   Ready    <none>          3m    v1.34.x
```

---

## Шаг 5. Подключить kubectl с хоста Windows (опционально)

```powershell
# Скопировать kubeconfig с мастера
vagrant ssh lab-k8s-master -- cat /home/vagrant/.kube/config > kubeconfig.yaml

# Использовать через переменную окружения
$env:KUBECONFIG = "$(pwd)\kubeconfig.yaml"
kubectl get nodes
```

> В kubeconfig адрес сервера будет `192.168.56.10:6443`. Для доступа через localhost замените на `127.0.0.1:6443` (порт пробрасывается Vagrant).

---

## Жизненный цикл кластера

```powershell
# Остановить (сохраняет состояние ВМ)
vagrant halt

# Запустить снова
vagrant up

# Перезапустить конкретную ВМ
vagrant reload lab-k8s-master

# Повторно запустить provisioning
vagrant provision lab-k8s-master

# Уничтожить кластер полностью
vagrant destroy -f
```

---

## Следующие шаги

- [Архитектура кластера и сети](architecture.md)
- [Устранение неисправностей](troubleshooting.md)
