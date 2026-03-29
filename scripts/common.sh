#!/usr/bin/env bash
# =============================================================================
# scripts/common.sh — Базовая подготовка всех нод кластера
# =============================================================================
# Используется: root-level Vagrantfile (Stage 2, с .env и SSH-ключами)
# Для учебного Stage 1 (хардкодом) — смотри stage1/scripts/common.sh
#
# АРГУМЕНТЫ (передаются из Vagrantfile через args: [...]):
#   $1 HOSTNAME_VALUE  — имя хоста (например, lab-k8s-master)
#   $2 NODE_IP         — IP второго сетевого адаптера (host-only)
#   $3 HOST_ENTRIES    — запятая-разделённые записи для /etc/hosts
#   $4 K8S_VERSION     — версия Kubernetes (например, 1.34)
#   $5 GATEWAY_IP      — IP шлюза по умолчанию (не используется напрямую)
#   $6 NODE_NAME       — имя ВМ в Vagrant (для SSH-ключей)
#
# ИДЕМПОТЕНТНОСТЬ: безопасно запускать несколько раз.
# ДОКУМЕНТАЦИЯ: kubernetes.io/docs/setup/production-environment/tools/kubeadm/
# =============================================================================

set -euo pipefail

HOSTNAME_VALUE="${1:?hostname is required}"
NODE_IP="${2:?node ip is required}"
HOST_ENTRIES="${3:?host entries are required}"
K8S_VERSION="${4:?kubernetes version is required}"
GATEWAY_IP="${5:?gateway ip is required}"
NODE_NAME="${6:?node name is required}"

# Путь к публичному SSH-ключу ноды (генерируется generate-node-key.ps1).
# Используется для добавления в authorized_keys — чтобы SSH без пароля работал.
NODE_PUBLIC_KEY="/vagrant/.vagrant/node-keys/${NODE_NAME}.ed25519.pub"

echo ">>> [common.sh] Нода: ${HOSTNAME_VALUE} | IP: ${NODE_IP} | K8s: ${K8S_VERSION}"

# ---------------------------------------------------------------------------
# Имя хоста
# ---------------------------------------------------------------------------
# hostnamectl set-hostname — изменяет имя текущей машины.
# Kubernetes идентифицирует ноды по hostname (kubectl get nodes показывает их).
# Важно: hostname должен быть уникальным в кластере и разрешаться через DNS/hosts.
sudo hostnamectl set-hostname "${HOSTNAME_VALUE}"

# ---------------------------------------------------------------------------
# /etc/hosts — таблица локального DNS
# ---------------------------------------------------------------------------
# Все три ноды должны «знать» друг о друге по имени.
# Формат: "192.168.56.10 k8s-master" — сопоставить IP и имя.
# Мы перезаписываем весь файл чисто, без дубликатов.
{
  echo "127.0.0.1 localhost"
  echo "127.0.1.1 ${HOSTNAME_VALUE}"
  echo
  echo "::1 localhost ip6-localhost ip6-loopback"
  echo "ff02::1 ip6-allnodes"
  echo "ff02::2 ip6-allrouters"
  echo
  # HOST_ENTRIES приходит в формате "ip1 host1,ip2 host2,..."
  IFS=',' read -ra ENTRIES <<< "${HOST_ENTRIES}"
  for entry in "${ENTRIES[@]}"; do
    echo "${entry}"
  done
} | sudo tee /etc/hosts >/dev/null

# ---------------------------------------------------------------------------
# Отключение swap
# ---------------------------------------------------------------------------
# Kubernetes требует: swap ВЫКЛЮЧЕН. Подробнее — в stage1/scripts/common.sh.
sudo swapoff -a
sudo sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab

# ---------------------------------------------------------------------------
# Модули ядра: overlay + br_netfilter
# ---------------------------------------------------------------------------
# overlay   — файловая система контейнеров (Copy-on-Write слои)
# br_netfilter — iptables для трафика через сетевые мосты (нужен kube-proxy)
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# ---------------------------------------------------------------------------
# sysctl: параметры сети ядра
# ---------------------------------------------------------------------------
# ip_forward — разрешить маршрутизацию пакетов между интерфейсами (Pod → Service)
# bridge-nf-call-iptables — iptables обрабатывает трафик через мосты (kube-proxy)
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system > /dev/null

# ---------------------------------------------------------------------------
# Утилиты
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq apt-transport-https ca-certificates curl gpg

# ---------------------------------------------------------------------------
# containerd (Ubuntu-репозиторий)
# ---------------------------------------------------------------------------
# Используем containerd из стандартного репозитория Ubuntu 24.04.
# Это надёжнее, чем Docker Hub: обновления синхронизированы с Ubuntu LTS.
# Docker Hub (download.docker.com) не требуется — K8s работает с containerd напрямую.
#
# Справка: https://kubernetes.io/docs/setup/production-environment/container-runtimes/
sudo apt-get install -y -qq containerd

sudo mkdir -p /etc/containerd
# containerd config default генерирует полный конфиг с параметрами по умолчанию.
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
# SystemdCgroup = true: передаём управление cgroups системному systemd.
# Без этого: kubelet и containerd конфликтуют за cgroups → ноды NotReady.
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Проверяем, что замена успешна (защита от тихой ошибки)
if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
  echo "[ОШИБКА] SystemdCgroup не изменён в containerd/config.toml" >&2
  exit 1
fi

sudo systemctl enable containerd
sudo systemctl restart containerd

# ---------------------------------------------------------------------------
# Репозиторий Kubernetes
# ---------------------------------------------------------------------------
# pkgs.k8s.io — официальный репозиторий Kubernetes, разделён по версиям.
# GPG-ключ гарантирует подлинность пакетов (apt проверяет подпись).
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

sudo apt-get update -qq

# ---------------------------------------------------------------------------
# Установка kubeadm, kubelet, kubectl
# ---------------------------------------------------------------------------
# apt-mark hold — запрещает автоматическое обновление (K8s обновляется планово).
sudo apt-get install -y -qq kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# ---------------------------------------------------------------------------
# NODE_IP для kubelet
# ---------------------------------------------------------------------------
# Без --node-ip kubelet сообщает мастеру NAT-IP (10.0.2.15) — одинаковый
# для всех ВМ. С --node-ip каждая нода сообщает свой уникальный host-only IP.
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}
EOF
sudo systemctl enable kubelet

# ---------------------------------------------------------------------------
# SSH-ключ ноды (только если файл существует — Stage 2)
# ---------------------------------------------------------------------------
# Публичный ключ генерируется на Windows через generate-node-key.ps1.
# Добавляется в authorized_keys → можно подключаться по ключу без пароля.
if [ -f "${NODE_PUBLIC_KEY}" ]; then
  install -d -m 700 /home/vagrant/.ssh
  touch /home/vagrant/.ssh/authorized_keys
  grep -qxF "$(cat "${NODE_PUBLIC_KEY}")" /home/vagrant/.ssh/authorized_keys \
    || cat "${NODE_PUBLIC_KEY}" >> /home/vagrant/.ssh/authorized_keys
  chmod 600 /home/vagrant/.ssh/authorized_keys
  chown -R vagrant:vagrant /home/vagrant/.ssh
  echo "  SSH-ключ для ${NODE_NAME} добавлен в authorized_keys"
fi

echo ">>> [common.sh] Нода ${HOSTNAME_VALUE} готова."
