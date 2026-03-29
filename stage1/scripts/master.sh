#!/usr/bin/env bash
# =============================================================================
# master.sh — Инициализация управляющей ноды (Control Plane)
# =============================================================================
#
# ЗАПУСКАЕТСЯ НА: только k8s-master
# ЗАПУСКАЕТСЯ ПОСЛЕ: common.sh
# ЗАПУСКАЕТСЯ КАК: root
#
# ЧТО ДЕЛАЕТ:
#   1. Запускает kubeadm init — разворачивает control plane Kubernetes
#   2. Настраивает kubeconfig (доступ к кластеру через kubectl)
#   3. Устанавливает Calico CNI (сетевой плагин для Pod-сети)
#   4. Разворачивает Kubernetes Dashboard (веб-интерфейс)
#   5. Создаёт admin ServiceAccount с долгосрочным токеном
#   6. Генерирует команду для присоединения воркеров (join-command.sh)
#
# ИДЕМПОТЕНТНОСТЬ: если kubeadm init уже выполнялся (/etc/kubernetes/admin.conf
# существует), повторная инициализация пропускается.
#
# КНИГИ:
#   EN: "Kubernetes in Action" — Marko Luksa, гл. 11 (Networking)
#   EN: "The Kubernetes Book" — Nigel Poulton, гл. 4 (Pods)
# =============================================================================

set -euo pipefail

MASTER_IP="${MASTER_IP:?Переменная MASTER_IP обязательна}"
POD_CIDR="${POD_CIDR:?Переменная POD_CIDR обязательна}"

echo ">>> [master.sh] Начало. MASTER_IP=${MASTER_IP}, POD_CIDR=${POD_CIDR}"

# =============================================================================
# ШАГ 1: Инициализация кластера через kubeadm init
# =============================================================================
# kubeadm init — главная команда. Она:
#   1. Генерирует TLS-сертификаты для всех компонентов (в /etc/kubernetes/pki/)
#   2. Запускает etcd (база данных)
#   3. Запускает kube-apiserver
#   4. Запускает kube-controller-manager и kube-scheduler
#   5. Создаёт kubeconfig-файлы для kubectl
#   6. Создаёт bootstrap-токен для присоединения воркеров
#
# ПАРАМЕТРЫ:
#   --apiserver-advertise-address — IP, на котором API Server принимает запросы.
#     ВАЖНО: должен быть IP второго адаптера (host-only), а не 10.0.2.15 (NAT).
#     Воркеры будут подключаться к мастеру именно по этому IP.
#
#   --pod-network-cidr — диапазон IP-адресов для Pod-сети.
#     10.244.0.0/16 = 65536 адресов (например, для Calico CNI).
#     Pod-сеть виртуальна: существует только внутри кластера.
#     Calico разобьёт её на блоки по /26 (64 IP) для каждой ноды.
#
#   --control-plane-endpoint — DNS-имя или IP API Server-а.
#     Воркеры и kubectl будут обращаться по этому адресу.
#     Используем имя "k8s-master", которое прописали в /etc/hosts.
if [ -f /etc/kubernetes/admin.conf ]; then
  echo ">>> [ШАГ 1] Кластер уже инициализирован, пропускаем kubeadm init."
else
  echo ">>> [ШАГ 1] Инициализация кластера (kubeadm init)..."
  kubeadm init \
    --apiserver-advertise-address="${MASTER_IP}" \
    --control-plane-endpoint="k8s-master" \
    --pod-network-cidr="${POD_CIDR}" \
    --kubernetes-version="v1.34.6" \
    --ignore-preflight-errors=NumCPU
  echo "  kubeadm init завершён успешно"
fi

# =============================================================================
# ШАГ 2: Настройка kubeconfig
# =============================================================================
# kubeconfig — файл с настройками доступа к кластеру.
# Содержит: адрес API Server, TLS-сертификаты, токен аутентификации.
#
# kubectl ищет kubeconfig в: $KUBECONFIG, ~/.kube/config, /etc/kubernetes/admin.conf
#
# Копируем admin.conf для пользователя vagrant и для root:
echo ">>> [ШАГ 2] Настройка kubeconfig..."

# Для пользователя vagrant (с которым работает интерактивно)
mkdir -p /home/vagrant/.kube
cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
echo "  kubeconfig настроен для пользователя vagrant"

# Для root (чтобы команды в этом скрипте работали)
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "  KUBECONFIG установлен для текущего сеанса root"

kubectl_apply_server_side() {
  kubectl apply --server-side --force-conflicts \
    --kubeconfig=/etc/kubernetes/admin.conf \
    "$@"
}

sleep_with_notice() {
  local seconds="${1:?seconds are required}"
  local reason="${2:?reason is required}"
  echo "  Пауза ${seconds} сек: ${reason}"
  sleep "${seconds}"
}

# =============================================================================
# ШАГ 3: Установка Calico CNI
# =============================================================================
# ЧТО ТАКОЕ CNI (Container Network Interface):
#   Kubernetes сам не умеет создавать сети для Pod-ов. Он делегирует это
#   CNI-плагину. CNI-плагин отвечает за:
#     - Выдачу IP-адреса каждому Pod-у
#     - Маршрутизацию трафика между Pod-ами на разных нодах
#     - Реализацию NetworkPolicy (правила файрвола между Pod-ами)
#
# ПОЧЕМУ CALICO (а не Flannel):
#   - Flannel: простой, только базовая маршрутизация
#   - Calico: поддерживает NetworkPolicy, BGP, VXLAN, IPIP
#   - В production используют Calico или Cilium
#   - Наш реальный кластер работает на Calico — берём за основу
#
# КАК РАБОТАЕТ CALICO VXLAN:
#   Каждая нода имеет свой /26-блок из 10.244.0.0/16.
#   Трафик между нодами оборачивается в VXLAN (UDP 4789) — «туннель».
#   Flannel делал то же самое проще, но без NetworkPolicy.
#
# ДОКУМЕНТАЦИЯ: https://docs.tigera.io/calico/latest/getting-started/kubernetes/
#
# Версия Calico: 3.28.0 (проверена с K8s 1.34)
CALICO_VERSION="v3.28.0"

echo ">>> [ШАГ 3] Установка Calico CNI ${CALICO_VERSION}..."

# Ждём, пока API Server полностью запустится (может занять 30–60 секунд).
echo "  Ожидаем готовности API Server..."
for i in $(seq 1 30); do
  kubectl cluster-info --kubeconfig=/etc/kubernetes/admin.conf > /dev/null 2>&1 && break
  echo "  попытка ${i}/30..."
  sleep 5
done

# Шаг 3a: Устанавливаем Tigera Operator.
# Tigera Operator — «менеджер» для Calico. Он управляет Calico как
# Kubernetes Custom Resource (CRD). Это современный способ установки Calico.
kubectl_apply_server_side -f \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"
echo "  Tigera Operator применён"

# Шаг 3b: Конфигурируем Calico через Custom Resource.
# Installation — это Kubernetes-объект (CRD), который описывает как должен
# работать Calico. Tigera Operator читает его и разворачивает нужные компоненты.
#
# calicoNetwork.bgp: Disabled — отключаем BGP (нужен только в больших сетях).
# encapsulation: VXLANCrossSubnet — VXLAN только между разными подсетями.
# cidr: 10.244.0.0/16 — должен совпадать с --pod-network-cidr в kubeadm init!
# blockSize: 26 — каждой ноде выделяется /26 = 64 IP для Pod-ов.
echo "  Настройка Calico Installation..."
kubectl_apply_server_side -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    bgp: Disabled
    ipPools:
    - blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF
echo "  Calico Installation создан"

# Даём оператору Calico время создать CRD-ресурсы, deployment'ы и сетевые pod'ы.
# В реальном мире это часто занимает минуты, а не секунды.
sleep_with_notice 180 "ожидаем первичную настройку Tigera Operator и Calico"

# Ждём, пока Calico-поды запустятся (обычно 2–5 минут).
echo "  Ожидаем готовности нод после установки Calico..."
kubectl wait --for=condition=Ready node/k8s-master \
  --timeout=300s \
  --kubeconfig=/etc/kubernetes/admin.conf || true

# =============================================================================
# ШАГ 4: Команда для присоединения воркеров
# =============================================================================
# kubeadm join — команда, которую нужно выполнить на каждом воркере.
# Она содержит:
#   - Адрес и порт API Server мастера
#   - Bootstrap-токен (действителен 24 часа)
#   - Хэш CA-сертификата (для безопасной проверки мастера)
#
# ЗАЧЕМ ФАЙЛ /vagrant/join-command.sh:
#   /vagrant/ — общая папка между хостом (Windows) и всеми ВМ.
#   Vagrant монтирует рабочую директорию проекта в /vagrant/ каждой ВМ.
#   Мастер записывает команду → воркеры читают её → используют для join.
#
# Альтернативный способ: передать через Vagrantfile, но файл проще.
echo ">>> [ШАГ 4] Генерация команды join для воркеров..."

# Создаём новый токен (действителен 24 часа) и формируем полную команду join.
kubeadm token create --print-join-command > /vagrant/join-command.sh
chmod +x /vagrant/join-command.sh
echo "  /vagrant/join-command.sh создан"

echo ">>> [ШАГ 5] Dashboard пока пропускаем."
echo "  Приоритет текущего provisioning: полностью поднять рабочий кластер (master + workers)."
echo "  Dashboard будет настраиваться отдельным шагом уже после того, как все ноды войдут в Ready."

echo ""
echo ">>> [master.sh] Готово!"
echo ""
echo "=== СОСТОЯНИЕ КЛАСТЕРА ==="
kubectl get nodes -o wide --kubeconfig=/etc/kubernetes/admin.conf
echo ""
echo "=== POD-Ы СИСТЕМЫ ==="
kubectl get pods -n kube-system --kubeconfig=/etc/kubernetes/admin.conf
