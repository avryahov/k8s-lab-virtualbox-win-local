# Архитектура кластера

## Топология

```
┌─────────────────────────────────────────────────────────────┐
│  Windows 11 Home (host)                                     │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  VirtualBox                                         │   │
│  │                                                     │   │
│  │  ┌──────────────────────┐   private_network         │   │
│  │  │  lab-k8s-master      │   192.168.56.0/24         │   │
│  │  │  192.168.56.10       │◄──────────────────────┐  │   │
│  │  │  control-plane       │                       │  │   │
│  │  │  4 CPU / 8 GB RAM    │                       │  │   │
│  │  └──────────────────────┘                       │  │   │
│  │                                                 │  │   │
│  │  ┌──────────────────────┐                       │  │   │
│  │  │  lab-k8s-worker1     │───────────────────────┤  │   │
│  │  │  192.168.56.11       │                       │  │   │
│  │  │  4 CPU / 8 GB RAM    │                       │  │   │
│  │  └──────────────────────┘                       │  │   │
│  │                                                 │  │   │
│  │  ┌──────────────────────┐                       │  │   │
│  │  │  lab-k8s-worker2     │───────────────────────┘  │   │
│  │  │  192.168.56.12       │                          │   │
│  │  │  4 CPU / 8 GB RAM    │                          │   │
│  │  └──────────────────────┘                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Port forwarding (NAT):                                     │
│  127.0.0.1:2232  →  master:22     (SSH)                    │
│  127.0.0.1:6443  →  master:6443   (Kubernetes API)         │
│  127.0.0.1:30443 →  master:30443  (Dashboard / NodePort)   │
└─────────────────────────────────────────────────────────────┘
```

---

## Компоненты стека

| Слой | Компонент | Версия |
|---|---|---|
| ОС | Ubuntu | 22.04 LTS (jammy) |
| Container runtime | containerd | latest (Docker repo) |
| Cgroup driver | systemd | — |
| Bootstrap | kubeadm | 1.34.x |
| Node agent | kubelet | 1.34.x |
| CLI | kubectl | 1.34.x |
| CNI | Flannel | latest release |
| Pod CIDR | — | 10.244.0.0/16 |

---

## Сеть

### Адресация нод

Каждая нода получает IP из `private_network`. Адреса фиксированы через `.env`.

| Нода | Private IP | Назначение |
|---|---|---|
| master | `192.168.56.10` | control-plane API, etcd |
| worker1 | `192.168.56.11` | рабочая нагрузка |
| worker2 | `192.168.56.12` | рабочая нагрузка |

### Проброс портов с хоста

| Host (localhost) | Guest | Назначение |
|---|---|---|
| `2232` | master:22 | SSH → master |
| `2242` | worker1:22 | SSH → worker1 |
| `2252` | worker2:22 | SSH → worker2 |
| `6443` | master:6443 | Kubernetes API server |
| `30443` | master:30443 | NodePort / Dashboard |

### Почему private_network, а не bridged?

`private_network` обеспечивает:
- Воспроизводимые фиксированные IP на любой машине
- Изоляцию от внешней сети (нет конфликтов с DHCP роутера)
- Корректный `--node-ip` для kubelet (не `10.0.2.15` от NAT-адаптера)

Bridged-режим (`BRIDGE_ADAPTER=`) добавляет третий адаптер для прямого доступа из внешней сети (например, для студентов через VPN/Keenetic).

---

## Provisioning

### Последовательность при `vagrant up`

```
1. Vagrantfile читает .env
2. PowerShell: generate-node-key.ps1 для каждой ноды
3. VirtualBox: создание ВМ (master → workers)
4. На каждой ВМ:
   └── common.sh
       ├── hostname + /etc/hosts
       ├── swap off
       ├── kernel modules (overlay, br_netfilter)
       ├── sysctl (ip_forward, bridge-nf-call)
       ├── containerd + systemd cgroup
       ├── kubelet (--node-ip=<private_ip>)
       └── SSH authorized_keys
5. На master:
   └── master.sh
       ├── kubeadm init --apiserver-advertise-address=192.168.56.10
       ├── kubeconfig → /home/vagrant/.kube/config
       ├── kubeadm token create → join-command.sh
       └── kubectl apply flannel CNI
6. На каждом worker:
   └── worker.sh
       ├── ждёт join-command.sh (до 10 мин)
       └── kubeadm join
```

### Идемпотентность

Все скрипты защищены от повторного выполнения:
- `master.sh` — проверяет `/etc/kubernetes/admin.conf`
- `worker.sh` — проверяет `/etc/kubernetes/kubelet.conf`
- `master.sh` Flannel — проверяет наличие DaemonSet `kube-flannel-ds`

### SSH-ключи

`generate-node-key.ps1` создаёт `ed25519` ключ для каждой ВМ в `.vagrant/node-keys/`.
Windows требует строгих прав доступа на приватный ключ — скрипт устанавливает их через `icacls`.
`common.sh` добавляет публичный ключ в `authorized_keys` пользователя `vagrant`.

---

## Ресурсы

По умолчанию каждая ВМ получает `4 CPU / 8 GB RAM`.
Для ноутбука с 16 GB RAM можно снизить до `2 CPU / 4096 MB`:

```
VM_CPUS=2
VM_MEMORY_MB=4096
```

Минимально рабочий кластер: master `2 CPU / 2048 MB`, workers `2 CPU / 2048 MB`.
