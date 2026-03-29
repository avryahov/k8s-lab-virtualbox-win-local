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
kubectl apply -f \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" \
  --kubeconfig=/etc/kubernetes/admin.conf
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
echo "  Calico Installation создан"

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

# =============================================================================
# ШАГ 5: Kubernetes Dashboard
# =============================================================================
# Kubernetes Dashboard — официальный веб-интерфейс для визуального управления
# кластером. Школьнику удобнее смотреть на Pod-ы в браузере, чем в терминале.
#
# ЧТО ПОКАЗЫВАЕТ: Pods, Deployments, Services, Nodes, события кластера,
#   использование ресурсов (CPU/RAM), логи контейнеров.
#
# ДОСТУП ПОСЛЕ УСТАНОВКИ: https://localhost:30443
# (браузер откроется с предупреждением о самоподписанном сертификате —
#  нажми "Advanced" → "Proceed" — это безопасно в лабораторной сети)
#
# ОФИЦИАЛЬНЫЙ РЕПОЗИТОРИЙ: https://github.com/kubernetes/dashboard
DASHBOARD_VERSION="v3.0.0"

echo ">>> [ШАГ 5] Установка Kubernetes Dashboard ${DASHBOARD_VERSION}..."

# Проверяем, не установлен ли уже Dashboard.
if kubectl get namespace kubernetes-dashboard --kubeconfig=/etc/kubernetes/admin.conf > /dev/null 2>&1; then
  echo "  Dashboard уже установлен, пропускаем."
else
  kubectl apply -f \
    "https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/charts/kubernetes-dashboard.yaml" \
    --kubeconfig=/etc/kubernetes/admin.conf || \
  # Если манифест для версии не найден, используем актуальный
  kubectl apply -f \
    "https://raw.githubusercontent.com/kubernetes/dashboard/master/charts/kubernetes-dashboard.yaml" \
    --kubeconfig=/etc/kubernetes/admin.conf
  echo "  Dashboard применён"
fi

# =============================================================================
# ШАГ 6: NodePort-сервис для Dashboard
# =============================================================================
# По умолчанию Dashboard создаётся с типом ClusterIP — доступен только
# внутри кластера. Нам нужен NodePort — доступ с хоста Windows.
#
# ТИПЫ SERVICE в Kubernetes:
#   ClusterIP  — только внутри кластера (default)
#   NodePort   — порт на каждой ноде → пробрасывается в Service
#   LoadBalancer — облачный балансировщик нагрузки (не для нашего lab)
#
# NodePort 30443 → Dashboard Pod (HTTPS 8443)
echo ">>> [ШАГ 6] Создание NodePort сервиса для Dashboard..."
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
echo "  NodePort 30443 → Dashboard создан"

# =============================================================================
# ШАГ 7: Admin ServiceAccount и токен для входа в Dashboard
# =============================================================================
# По умолчанию Dashboard требует аутентификации.
# Мы создаём "admin-user" — ServiceAccount с правами cluster-admin.
#
# ВНИМАНИЕ (важно для реального production!):
#   cluster-admin = полный доступ ко всему кластеру.
#   В production нужно создавать ограниченные роли (RBAC).
#   В нашем учебном lab это допустимо.
#
# Подробнее о RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
echo ">>> [ШАГ 7] Создание admin-user для Dashboard..."

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

# Ждём запуска Dashboard Pod.
echo "  Ожидаем запуска Dashboard..."
kubectl -n kubernetes-dashboard wait \
  --for=condition=Available \
  deployment/kubernetes-dashboard \
  --timeout=120s \
  --kubeconfig=/etc/kubernetes/admin.conf 2>/dev/null || true

# Генерируем токен для входа (действителен 24 часа).
# Этот токен вставляется в поле "Enter token" на странице Dashboard.
echo ""
echo "========================================================"
echo "  ТОКЕН ДЛЯ ВХОДА В DASHBOARD (скопируй в браузер):"
echo "========================================================"
kubectl -n kubernetes-dashboard create token admin-user \
  --duration=24h \
  --kubeconfig=/etc/kubernetes/admin.conf
echo "========================================================"
echo "  URL: https://localhost:30443"
echo "  (при предупреждении браузера → Advanced → Proceed)"
echo "========================================================"

echo ""
echo ">>> [master.sh] Готово!"
echo ""
echo "=== СОСТОЯНИЕ КЛАСТЕРА ==="
kubectl get nodes -o wide --kubeconfig=/etc/kubernetes/admin.conf
echo ""
echo "=== POD-Ы СИСТЕМЫ ==="
kubectl get pods -n kube-system --kubeconfig=/etc/kubernetes/admin.conf
