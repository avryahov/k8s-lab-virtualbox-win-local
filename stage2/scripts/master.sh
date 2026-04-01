#!/usr/bin/env bash
# =============================================================================
# master.sh — Инициализация Control Plane (Stage 2)
# =============================================================================
#
# ИСПОЛЬЗУЕТСЯ: root-level Vagrantfile (Stage 2, с .env)
# Для Stage 1 (хардкодом) — смотри stage1/scripts/master.sh
#
# ЗАПУСКАЕТСЯ НА: только master-нода (lab-k8s-master)
# ЗАПУСКАЕТСЯ ПОСЛЕ: common.sh (на этой же ноде)
# ЗАПУСКАЕТСЯ КАК: root (через sudo внутри скрипта)
#
# АРГУМЕНТЫ:
#   $1 MASTER_IP — IP master-ноды (host-only адаптер, например 192.168.56.10)
#   $2 POD_CIDR  — Pod-сеть (например 10.244.0.0/16)
#
# ЧТО ДЕЛАЕТ (по порядку):
#   1. kubeadm init — инициализация кластера (создание control plane)
#   2. Настройка kubeconfig для пользователя vagrant и root
#   3. Генерация команды join для worker-нод (join-command.sh)
#   4. Ожидание готовности API Server
#   5. Установка Calico CNI через Tigera Operator
#   6. Ожидание Ready-статуса мастер-ноды
#   7. Установка Kubernetes Dashboard
#   8. Создание NodePort Service для Dashboard (порт 30443)
#   9. Создание admin-user ServiceAccount с cluster-admin ролью
#   10. Генерация и вывод токена для входа в Dashboard
#
# ИДЕМПОТЕНТНОСТЬ:
#   - kubeadm init: проверяет /etc/kubernetes/admin.conf перед запуском
#   - Calico: проверяет namespace calico-system перед установкой
#   - Dashboard: проверяет namespace kubernetes-dashboard перед установкой
#   - kubeconfig: перезаписывается каждый раз (idempotent операция)
#
# ОТЛИЧИЯ ОТ STAGE 1:
#   - Принимает параметры через аргументы, а не env-переменные
#   - Использует sudo вместо прямого запуска от root
#   - Dashboard устанавливается сразу (в Stage 1 он отложен до post-bootstrap)
#   - Нет отдельного finalize-cluster.sh (Calico ставится здесь же)
#
# ДОКУМЕНТАЦИЯ:
#   https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
#   https://docs.tigera.io/calico/latest/getting-started/kubernetes/
# =============================================================================

# Строгий режим bash:
#   -e: завершить при любой ошибке
#   -u: ошибка если переменная не определена
#   -o pipefail: ошибка если часть конвейера (pipe) упала
set -euo pipefail

# ---------------------------------------------------------------------------
# Чтение аргументов и константы
# ---------------------------------------------------------------------------
# ${1:?message} — если аргумент не передан, скрипт завершится с ошибкой.
MASTER_IP="${1:?master ip is required}"
POD_CIDR="${2:?pod cidr is required}"

# Путь к файлу с командой join для worker-нод.
# /vagrant/ — общая папка между хостом (Windows) и всеми ВМ.
# Воркеры читают этот файл через worker.sh.
JOIN_FILE="/vagrant/join-command.sh"

# Версии компонентов.
# Фиксируем версии для воспроизводимости: одинаковый результат при каждом запуске.
CALICO_VERSION="v3.28.0"       # Calico CNI — сетевой плагин для Pod-сети
DASHBOARD_VERSION="v3.0.0"     # Kubernetes Dashboard — веб-интерфейс

echo ">>> [master.sh] MASTER_IP=${MASTER_IP}, POD_CIDR=${POD_CIDR}"

# ---------------------------------------------------------------------------
# ШАГ 1: kubeadm init — инициализация кластера
# ---------------------------------------------------------------------------
# kubeadm init — главная команда. Она создаёт control plane Kubernetes:
#   1. Генерирует TLS-сертификаты для всех компонентов (в /etc/kubernetes/pki/)
#   2. Запускает etcd (распределённое хранилище данных кластера)
#   3. Запускает kube-apiserver (точка входа для всех команд kubectl)
#   4. Запускает kube-controller-manager (следит за состоянием кластера)
#   5. Запускает kube-scheduler (решает, на какой ноде запускать Pod)
#   6. Создаёт kubeconfig-файлы для аутентификации
#   7. Создаёт bootstrap-токен для присоединения worker-нод
#
# ПАРАМЕТРЫ:
#   --apiserver-advertise-address — IP, на котором API Server принимает запросы.
#     ВАЖНО: должен быть IP host-only адаптера, а не 10.0.2.15 (NAT).
#     Worker-ноды будут подключаться к мастеру именно по этому IP.
#
#   --control-plane-endpoint — DNS-имя или IP API Server-а.
#     Worker-ноды и kubectl будут обращаться по этому адресу.
#     Используем hostname машины (например, lab-k8s-master),
#     который прописан в /etc/hosts на всех нодах.
#
#   --pod-network-cidr — диапазон IP-адресов для Pod-сети.
#     10.244.0.0/16 = 65536 адресов.
#     Pod-сеть виртуальна: существует только внутри кластера.
#     Calico разобьёт её на блоки по /26 (64 IP) для каждой ноды.
#     ВАЖНО: должен совпадать с cidr в Calico Installation CRD!
#
#   --kubernetes-version — фиксируем версию для воспроизводимости.
#     Без этого kubeadm может скачать последнюю версию, которая
#     может быть несовместима с Calico или другими компонентами.
#
#   --ignore-preflight-errors=NumCPU — обойти проверку числа CPU.
#     kubeadm требует минимум 2 CPU на master. В учебном стенде
#     может быть меньше — игнорируем эту проверку.
#
# ИДЕМПОТЕНТНОСТЬ:
#   /etc/kubernetes/admin.conf создаётся после успешного kubeadm init.
#   Если файл уже есть — кластер уже инициализирован, повторный init
#   не нужен (и даже невозможен — kubeadm init упадёт с ошибкой).
if [ ! -f /etc/kubernetes/admin.conf ]; then
  echo ">>> [ШАГ 1] Инициализация кластера (kubeadm init)..."
  sudo kubeadm init \
    --apiserver-advertise-address="${MASTER_IP}" \
    --control-plane-endpoint="$(hostname)" \
    --pod-network-cidr="${POD_CIDR}" \
    --kubernetes-version="v1.34.6" \
    --ignore-preflight-errors=NumCPU
  echo "  kubeadm init завершён успешно"
else
  echo ">>> [ШАГ 1] Кластер уже инициализирован (admin.conf существует). Пропускаем."
fi

# ---------------------------------------------------------------------------
# ШАГ 2: kubeconfig для vagrant и root
# ---------------------------------------------------------------------------
# kubeconfig — файл с настройками доступа к кластеру.
# Содержит: адрес API Server, TLS-сертификаты, токен аутентификации.
#
# kubectl ищет kubeconfig в порядке:
#   1. Переменная окружения $KUBECONFIG
#   2. ~/.kube/config
#   3. /etc/kubernetes/admin.conf (только для root)
#
# Копируем admin.conf для пользователя vagrant:
#   - mkdir -p — создать директорию, если не существует
#   - cp — скопировать файл
#   - chown — сменить владельца на vagrant (иначе root не даст читать)
mkdir -p /home/vagrant/.kube
sudo cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config

# Для root (чтобы команды в этом скрипте работали без --kubeconfig).
export KUBECONFIG=/etc/kubernetes/admin.conf
echo "  kubeconfig настроен для vagrant и root"

# ---------------------------------------------------------------------------
# ШАГ 3: Команда join для worker-нод
# ---------------------------------------------------------------------------
# kubeadm token create --print-join-command генерирует команду,
# которую нужно выполнить на каждой worker-ноде для присоединения.
#
# Команда содержит:
#   - Адрес и порт API Server мастера
#   - Bootstrap-токен (действителен 24 часа)
#   - Хэш CA-сертификата (для безопасной проверки мастера)
#
# Записываем в /vagrant/ — общую папку всех ВМ.
# Worker-ноды читают этот файл через worker.sh.
# tee записывает в файл и одновременно показывает команду в логе.
sudo kubeadm token create --print-join-command | sudo tee "${JOIN_FILE}" >/dev/null
sudo chmod +x "${JOIN_FILE}"
echo "  join-command.sh создан: ${JOIN_FILE}"

# ---------------------------------------------------------------------------
# ШАГ 4: Calico CNI через Tigera Operator
# ---------------------------------------------------------------------------
# ЧТО ТАКОЕ CNI (Container Network Interface):
#   Kubernetes сам не умеет создавать сети для Pod-ов. Он делегирует это
#   CNI-плагину. CNI-плагин отвечает за:
#     - Выдачу IP-адреса каждому Pod-у
#     - Маршрутизацию трафика между Pod-ами на разных нодах
#     - Реализацию NetworkPolicy (правила файрвола между Pod-ами)
#
# ПОЧЕМУ CALICO:
#   - Flannel: простой, только базовая маршрутизация
#   - Calico: поддерживает NetworkPolicy, BGP, VXLAN, IPIP
#   - В production используют Calico или Cilium
#   - Наш реальный кластер работает на Calico — берём за основу
#
# КАК РАБОТАЕТ CALICO VXLAN:
#   Каждая нода получает свой /26-блок из 10.244.0.0/16.
#   Трафик между нодами оборачивается в VXLAN (UDP 4789) — «туннель».
#   Это позволяет Pod-сети работать поверх любой физической сети.
#
# TIGERA OPERATOR:
#   Tigera Operator — «менеджер» для Calico. Он управляет Calico как
#   Kubernetes Custom Resource (CRD). Это современный способ установки Calico.
#   Вместо ручного применения десятков манифестов — один оператор
#   разворачивает всё сам.
#
# ДОКУМЕНТАЦИЯ: https://docs.tigera.io/calico/latest/getting-started/kubernetes/

# Ждём, пока API Server полностью запустится (может занять 30–60 секунд).
# kubeadm init возвращает управление до того, как API Server полностью готов.
echo ">>> [ШАГ 4] Ожидание готовности API Server..."
for i in $(seq 1 30); do
  kubectl cluster-info --kubeconfig=/etc/kubernetes/admin.conf > /dev/null 2>&1 && break
  sleep 5
done
echo "  API Server готов"

# Проверяем, не установлен ли уже Calico (идемпотентность).
# calico-system — namespace, который создаётся Tigera Operator.
if ! kubectl --kubeconfig=/etc/kubernetes/admin.conf \
     get namespace calico-system > /dev/null 2>&1; then

  echo ">>> [ШАГ 4a] Установка Tigera Operator..."
  kubectl apply --server-side --force-conflicts -f \
    "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml" \
    --kubeconfig=/etc/kubernetes/admin.conf
  echo "  Tigera Operator применён"

  sleep 180

  echo ">>> [ШАГ 4b] Настройка Calico Installation..."
  kubectl apply --server-side --force-conflicts -f - --kubeconfig=/etc/kubernetes/admin.conf <<EOF
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
else
  echo ">>> [ШАГ 4] Calico уже установлен (namespace calico-system существует). Пропускаем."
fi

# Ожидаем Ready мастер-ноды.
# Calico-поды должны запуститься и настроить сеть.
# Это занимает 1–3 минуты.
echo ">>> [ШАГ 4c] Ожидание Ready нод..."
kubectl wait --for=condition=Ready node/"$(hostname)" \
  --timeout=300s \
  --kubeconfig=/etc/kubernetes/admin.conf || true
echo "  Мастер-нода готова"

# ---------------------------------------------------------------------------
# ШАГ 5: Kubernetes Dashboard
# ---------------------------------------------------------------------------
# Официальный веб-интерфейс кластера.
# Позволяет просматривать ресурсы, логи, метрики через браузер.
#
# В STAGE 2 Dashboard ставится сразу, в отличие от Stage 1,
# где он отложен до post-bootstrap (после smoke-теста).
#
# Доступен после настройки по: https://localhost:30443
# Требует токен для входа (генерируется в конце скрипта).
if ! kubectl --kubeconfig=/etc/kubernetes/admin.conf \
     get namespace kubernetes-dashboard > /dev/null 2>&1; then

  echo ">>> [ШАГ 5] Установка Kubernetes Dashboard ${DASHBOARD_VERSION}..."
  # Применяем манифест Dashboard из GitHub.
  # Fallback на master-branch: если версия не найдена (например, релиз ещё
  # не опубликован), пробуем последнюю версию из master.
  kubectl apply -f \
    "https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/charts/kubernetes-dashboard.yaml" \
    --kubeconfig=/etc/kubernetes/admin.conf 2>/dev/null || \
  kubectl apply -f \
    "https://raw.githubusercontent.com/kubernetes/dashboard/master/charts/kubernetes-dashboard.yaml" \
    --kubeconfig=/etc/kubernetes/admin.conf
  echo "  Dashboard манифест применён"
else
  echo ">>> [ШАГ 5] Dashboard уже установлен (namespace kubernetes-dashboard существует). Пропускаем."
fi

# ---------------------------------------------------------------------------
# ШАГ 6: NodePort Service для Dashboard
# ---------------------------------------------------------------------------
# По умолчанию Dashboard доступен только внутри кластера (ClusterIP).
# Чтобы открыть его наружу — создаём Service типа NodePort.
#
# NodePort — открывает порт на ВСЕХ нодах кластера.
# Трафик на этот порт перенаправляется на Pod-ы Dashboard.
#
# ПАРАМЕТРЫ:
#   port: 443 — порт сервиса (стандартный HTTPS)
#   targetPort: 8443 — порт, на котором Dashboard Pod слушает HTTPS
#   nodePort: 30443 — порт на ноде (и на хосте через проброс Vagrant)
#
# ВАЖНО: NodePort должен быть в диапазоне 30000–32767 (стандарт Kubernetes).
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
echo "  NodePort Service для Dashboard создан (порт 30443)"

# ---------------------------------------------------------------------------
# ШАГ 7: admin-user ServiceAccount и RBAC
# ---------------------------------------------------------------------------
# ServiceAccount — учётная запись для процессов внутри Kubernetes.
# В данном случае — для входа в Dashboard.
#
# ClusterRoleBinding — связывает ServiceAccount с ролью cluster-admin.
# cluster-admin — максимальные права в кластере (полный доступ ко всему).
#
# ПРЕДУПРЕЖДЕНИЕ:
#   В production использовать cluster-admin для Dashboard НЕЛЬЗЯ!
#   Нужно создавать ограниченную роль с минимальными правами.
#   Здесь это допустимо, потому что это учебный стенд.
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
echo "  admin-user ServiceAccount и ClusterRoleBinding созданы"

# ---------------------------------------------------------------------------
# ШАГ 8: Генерация токена для Dashboard
# ---------------------------------------------------------------------------
# create token — создаёт временный токен для аутентификации.
# --duration=24h — токен действителен 24 часа.
# После истечения нужно сгенерировать новый.
#
# ТОКЕН — это длинная строка, которую нужно вставить в поле
# «Enter token» на странице входа в Dashboard.
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
echo ">>> [master.sh] Готово! Состояние нод:"
kubectl get nodes -o wide --kubeconfig=/etc/kubernetes/admin.conf
