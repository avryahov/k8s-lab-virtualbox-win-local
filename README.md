# k8s-vagrant-lab

Воспроизводимый локальный Kubernetes-кластер на Windows 11 Home + VirtualBox + Vagrant.

**Состав:** 1 control-plane + 2 workers · Ubuntu 22.04 · containerd · kubeadm · Flannel CNI

---

## Требования

| Инструмент | Минимальная версия | Установка |
|---|---|---|
| VirtualBox | 7.0 | virtualbox.org |
| Vagrant | 2.4 | vagrantup.com |
| PowerShell | 5.1 (встроен) | Windows 11 |
| ssh-keygen | любая | Git for Windows или OpenSSH |

> Windows 11 Home поддерживается полностью. Hyper-V отключать не нужно — VirtualBox 7 работает рядом с Hyper-V через режим совместимости.

---

## Быстрый старт

```powershell
# 1. Клонировать репозиторий
git clone <repo-url> k8s-vagrant-lab
cd k8s-vagrant-lab

# 2. Создать рабочий .env из шаблона
Copy-Item .env.example .env
# Отредактировать при необходимости (порты, сеть, ресурсы)

# 3. Поднять кластер (первый раз ~15-20 мин)
vagrant up

# 4. Проверить состояние нод
vagrant ssh lab-k8s-master -- kubectl get nodes -o wide
```

Подробный разбор — в [docs/quickstart.md](docs/quickstart.md).

---

## Архитектура кластера

```
Windows 11 (host)
├── VirtualBox
│   ├── lab-k8s-master  192.168.56.10  (control-plane)
│   ├── lab-k8s-worker1 192.168.56.11  (worker)
│   └── lab-k8s-worker2 192.168.56.12  (worker)
│
└── Port forwarding (host → guest)
    ├── localhost:2232 → master:22    (SSH)
    ├── localhost:6443 → master:6443  (Kubernetes API)
    └── localhost:30443 → master:30443 (Dashboard / NodePort)
```

Сеть `private_network (192.168.56.0/24)` — стабильная внутренняя адресация.
Bridged-адаптер опционален через `BRIDGE_ADAPTER` в `.env`.

---

## Структура репозитория

```
.
├── Vagrantfile                  # Главный конфиг — читает .env, управляет ВМ
├── .env.example                 # Шаблон конфигурации (копировать в .env)
├── .gitignore
├── scripts/
│   ├── common.sh                # Все ноды: containerd, kubelet, kubeadm, kubectl
│   ├── master.sh                # Control-plane: kubeadm init, Flannel CNI
│   ├── worker.sh                # Workers: ожидание join-command, kubeadm join
│   ├── generate-node-key.ps1    # Windows: генерация ed25519 SSH-ключей
│   └── cleanup-node-key.ps1     # Windows: удаление ключей после vagrant destroy
├── docs/
│   ├── quickstart.md            # Пошаговая инструкция с нуля
│   ├── architecture.md          # Устройство кластера и сети
│   └── troubleshooting.md       # Частые проблемы и их решения
└── CLAUDE.md                    # Правила работы ИИ-ассистента в этом репо
```

---

## Управление кластером

```powershell
# Статус ВМ
vagrant status

# Подключение к нодам
vagrant ssh lab-k8s-master
vagrant ssh lab-k8s-worker1
vagrant ssh lab-k8s-worker2

# Остановить (без удаления данных)
vagrant halt

# Запустить снова
vagrant up

# Полное удаление
vagrant destroy -f
```

---

## Диагностика кластера

```bash
# Все команды выполняются на master после vagrant ssh lab-k8s-master

# Состояние нод
kubectl get nodes -o wide

# Все поды во всех namespace
kubectl get pods -A

# Статус системных сервисов
systemctl status kubelet --no-pager
systemctl status containerd --no-pager

# Логи kubelet
journalctl -u kubelet -n 50 --no-pager
```

---

## Конфигурация (.env)

Параметры можно менять в `.env` без редактирования `Vagrantfile`.
Полный список с описаниями — в `.env.example`.

Ключевые переменные:

| Переменная | По умолчанию | Описание |
|---|---|---|
| `CLUSTER_PREFIX` | `lab-k8s` | Префикс имён ВМ и hostname |
| `VM_CPUS` | `4` | Число CPU на каждую ВМ |
| `VM_MEMORY_MB` | `8192` | ОЗУ на каждую ВМ (МБ) |
| `WORKER_COUNT` | `2` | Количество worker-нод |
| `KUBERNETES_VERSION` | `1.34` | Версия Kubernetes |
| `PRIVATE_NETWORK_PREFIX` | `192.168.56` | Подсеть кластера |
| `BRIDGE_ADAPTER` | _(пусто)_ | Bridged-адаптер (опционально) |

> Если нужно запустить второй независимый кластер — измените `CLUSTER_PREFIX` и `PRIVATE_NETWORK_PREFIX` чтобы избежать конфликтов.

---

## SSH-ключи

При `vagrant up` автоматически генерируются ed25519 ключи в `.vagrant/node-keys/` (папка исключена из git).
При `vagrant destroy` ключи удаляются.
Это управляется через PowerShell-скрипты в `scripts/`.

Для прямого SSH (без vagrant):

```powershell
ssh -i .vagrant\node-keys\lab-k8s-master.ed25519 -p 2232 vagrant@127.0.0.1
```

---

## Документация

- [Быстрый старт](docs/quickstart.md)
- [Архитектура](docs/architecture.md)
- [Устранение неисправностей](docs/troubleshooting.md)
