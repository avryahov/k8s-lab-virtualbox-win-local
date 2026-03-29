#!/usr/bin/env bash
# =============================================================================
# scripts/master.sh — Инициализация Control Plane
# =============================================================================
# Используется: root-level Vagrantfile (Stage 2, с .env)
# Для Stage 1 (хардкодом) — смотри stage1/scripts/master.sh
#
# АРГУМЕНТЫ:
#   $1 MASTER_IP — IP master-ноды (host-only адаптер, например 192.168.56.10)
#   $2 POD_CIDR  — Pod-сеть (например 10.244.0.0/16)
#
# ИДЕМПОТЕНТНОСТЬ: проверяет /etc/kubernetes/admin.conf перед kubeadm init.
#
# ДОКУМЕНТАЦИЯ:
#   https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
#   https://docs.tigera.io/calico/latest/getting-started/kubernetes/
# =============================================================================

set -euo pipefail

MASTER_IP="${1:?master ip is required}"
POD_CIDR="${2:?pod cidr is required}"
JOIN_FILE="/vagrant/join-command.sh"
CALICO_VERSION="v3.28.0"
DASHBOARD_VERSION="v3.0.0"

echo ">>> [master.sh] MASTER_IP=${MASTER_IP}, POD_CIDR=${POD_CIDR}"

# ---------------------------------------------------------------------------
# kubeadm init — инициализация кластера
# ---------------------------------------------------------------------------
# Запускается ОДИН РАЗ. Если admin.conf уже есть — кластер уже поднят.
# --control-plane-endpoint: DNS-имя мастера (из /etc/hosts).
# --apiserver-advertise-address: IP на котором API Server принимает запросы.
#   Должен быть IP host-only адаптера, не NAT (10.0.2.15).
# --pod-network-cidr: диапазон IP для Pod-сети. Должен совпадать с Calico Installation.
# --kubernetes-version: фиксируем версию, чтобы результат был воспроизводимым.
if [ ! -f /etc/kubernetes/admin.conf ]; then
  echo ">>> kubeadm init..."
  sudo kubeadm init \
    --apiserver-advertise-address="${MASTER_IP}" \
    --control-plane-endpoint="$(hostname)" \
    --pod-network-cidr="${POD_CIDR}" \
    --kubernetes-version="v1.34.6" \
    --ignore-preflight-errors=NumCPU
fi

# ---------------------------------------------------------------------------
# kubeconfig для vagrant и root
# ---------------------------------------------------------------------------
mkdir -p /home/vagrant/.kube
sudo cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

# ---------------------------------------------------------------------------
# Команда join для воркеров
# ---------------------------------------------------------------------------
# Записываем в /vagrant/ — общую папку всех ВМ.
# Воркеры читают этот файл через worker.sh.
sudo kubeadm token create --print-join-command | sudo tee "${JOIN_FILE}" >/dev/null
sudo chmod +x "${JOIN_FILE}"
echo "  join-command.sh создан"

# ---------------------------------------------------------------------------
# Calico CNI (Tigera Operator)
# ---------------------------------------------------------------------------
# Ждём готовности API Server.
echo ">>> Ожидаем API Server..."
for i in $(seq 1 30); do
  kubectl cluster-info --kubeconfig=/etc/kubernetes/admin.conf > /dev/null 2>&1 && break
  sleep 5
done

# Tigera Operator управляет Calico как Kubernetes-ресурсом.
# Это современный (рекомендованный) способ установки Calico.
if ! kubectl --kubeconfig=/etc/kubernetes/admin.conf \
     get namespace calico-system > /dev/null 2>&1; then
  echo ">>> Установка Calico ${CALICO_VERSION}..."
  kubectl apply -f \
    "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" \
    --kubeconfig=/etc/kubernetes/admin.conf

  # Installation CRD — описывает желаемую конфигурацию Calico.
  # VXLAN encapsulation — туннелирование Pod-трафика между нодами.
  # BGP: Disabled — только для малых сетей (BGP нужен в крупных кластерах).
  # POD_CIDR должен совпадать с --pod-network-cidr в kubeadm init.
  kubectl apply -f - --kubeconfig=/etc/kubernetes/admin.conf <<EOF
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
fi

# Ожидаем Ready мастер-ноды.
echo ">>> Ожидаем Ready нод..."
kubectl wait --for=condition=Ready node/"$(hostname)" \
  --timeout=300s \
  --kubeconfig=/etc/kubernetes/admin.conf || true

# ---------------------------------------------------------------------------
# Kubernetes Dashboard
# ---------------------------------------------------------------------------
# Официальный веб-интерфейс кластера.
# Доступен после настройки по: https://localhost:30443
# Требует токен для входа (генерируется ниже).
if ! kubectl --kubeconfig=/etc/kubernetes/admin.conf \
     get namespace kubernetes-dashboard > /dev/null 2>&1; then
  echo ">>> Установка Dashboard ${DASHBOARD_VERSION}..."
  kubectl apply -f \
    "https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/charts/kubernetes-dashboard.yaml" \
    --kubeconfig=/etc/kubernetes/admin.conf 2>/dev/null || \
  kubectl apply -f \
    "https://raw.githubusercontent.com/kubernetes/dashboard/master/charts/kubernetes-dashboard.yaml" \
    --kubeconfig=/etc/kubernetes/admin.conf
fi

# NodePort — открываем Dashboard наружу (порт 30443 на всех нодах кластера).
# targetPort: 8443 — Dashboard Pod слушает HTTPS на 8443.
kubectl apply -f - --kubeconfig=/etc/kubernetes/admin.conf <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard-nodeport
  namespace: kubernetes-dashboard
  labels:
    app: kubernetes-dashboard
spec:
  type: NodePort
  selector:
    app: kubernetes-dashboard
  ports:
  - name: https
    protocol: TCP
    port: 443
    targetPort: 8443
    nodePort: 30443
EOF

# admin-user ServiceAccount — для входа в Dashboard без лишних ограничений.
# В production использовать ограниченные RBAC-роли!
kubectl apply -f - --kubeconfig=/etc/kubernetes/admin.conf <<'EOF'
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

# Генерируем токен для Dashboard (действителен 24 часа).
echo ""
echo "========================================================"
echo "  ТОКЕН ДЛЯ KUBERNETES DASHBOARD:"
echo "========================================================"
kubectl -n kubernetes-dashboard create token admin-user \
  --duration=24h \
  --kubeconfig=/etc/kubernetes/admin.conf
echo "========================================================"
echo "  URL: https://localhost:30443"
echo "========================================================"

echo ""
echo ">>> [master.sh] Готово!"
kubectl get nodes -o wide --kubeconfig=/etc/kubernetes/admin.conf
