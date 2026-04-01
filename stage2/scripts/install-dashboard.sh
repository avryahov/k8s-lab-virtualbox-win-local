#!/usr/bin/env bash
# =============================================================================
# install-dashboard.sh — Установка Kubernetes Dashboard (Stage 2)
# =============================================================================
#
# ЗАПУСКАЕТСЯ НА: master-ноде
# ЗАПУСКАЕТСЯ ПОСЛЕ: того как все ноды готовы и smoke-тест пройден
# ЗАПУСКАЕТСЯ КАК: root
#
# ЧТО ДЕЛАЕТ:
#   1. Устанавливает Kubernetes Dashboard через официальный манифест
#   2. Создаёт NodePort Service для доступа снаружи
#   3. Создаёт admin-user ServiceAccount с cluster-admin правами
#   4. Ждёт готовности Dashboard Pod-ов
#   5. ВСЕГДА генерирует и сохраняет токен в /vagrant/dashboard-token.txt
#
# ВАЖНО: Dashboard устанавливается ПОСЛЕДНИМ шагом, после smoke-тестов.
# Это гарантирует, что кластер уже полностью функционален.
#
# ИДЕМПОТЕНТНОСТЬ:
#   - Если namespace kubernetes-dashboard уже существует — установка пропускается
#   - Токен генерируется ВСЕГДА (даже если Dashboard уже установлен)
#   - Токен сохраняется в /vagrant/dashboard-token.txt (общая папка → видно на хосте)
#
# ДОСТУП:
#   URL: https://localhost:30443
#   Токен: сохраняется в /vagrant/dashboard-token.txt и выводится в консоль
# =============================================================================

set -euo pipefail

export KUBECONFIG=/etc/kubernetes/admin.conf

DASHBOARD_VERSION="v3.0.0"
DASHBOARD_PORT="30443"
TOKEN_FILE="/vagrant/dashboard-token.txt"

echo ">>> [install-dashboard] Установка Kubernetes Dashboard..."

# =============================================================================
# ШАГ 1: Установка Dashboard через официальный манифест
# =============================================================================
if kubectl get namespace kubernetes-dashboard >/dev/null 2>&1; then
    echo "  Dashboard уже установлен, пропускаем установку."
else
    echo "  Установка Dashboard ${DASHBOARD_VERSION}..."

    if ! kubectl apply -f \
        "https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/charts/kubernetes-dashboard.yaml" \
        2>/dev/null; then
        echo "  Версия ${DASHBOARD_VERSION} не найдена, используем master..."
        kubectl apply -f \
            "https://raw.githubusercontent.com/kubernetes/dashboard/master/charts/kubernetes-dashboard.yaml" \
            2>/dev/null || {
            echo "  ОШИБКА: Не удалось установить Dashboard" >&2
            exit 1
        }
    fi
    echo "  Dashboard манифест применён"
fi

# =============================================================================
# ШАГ 2: NodePort Service для доступа снаружи
# =============================================================================
echo "  Создание NodePort Service..."

kubectl apply -f - <<EOF
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
    nodePort: ${DASHBOARD_PORT}
EOF

# =============================================================================
# ШАГ 3: admin-user ServiceAccount для входа
# =============================================================================
echo "  Создание admin-user ServiceAccount..."

kubectl apply -f - <<EOF
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

# =============================================================================
# ШАГ 4: Ожидание готовности Dashboard Pod-ов
# =============================================================================
echo "  Ожидание готовности Dashboard Pod-ов..."

for ((attempt=1; attempt<=30; attempt++)); do
    ready=$(kubectl get pods -n kubernetes-dashboard -l app=kubernetes-dashboard \
            -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -c "True" || true)

    if [ "$ready" -gt "0" ]; then
        echo "  Dashboard Pod готов"
        break
    fi

    if [ "$attempt" -eq "30" ]; then
        echo "  ПРЕДУПРЕЖДЕНИЕ: Dashboard Pod не вышел на готовность за 5 минут"
        break
    fi

    echo "  Ожидание... попытка ${attempt}/30"
    sleep 5
done

# =============================================================================
# ШАГ 5: Генерация и сохранение токена
# =============================================================================
# Токен генерируется ВСЕГДА — даже если Dashboard уже установлен.
# Это решает проблему повторного запуска: ученик всегда получает свежий токен.
#
# КУДА СОХРАНЯЕМ:
#   /vagrant/dashboard-token.txt — общая папка между хостом и ВМ.
#   На Windows-хосте доступен как stage2/dashboard-token.txt.
echo ""
echo ">>> [install-dashboard] Генерация токена admin-user..."

token="$(kubectl -n kubernetes-dashboard create token admin-user --duration=24h)"

if [ -z "${token}" ]; then
    echo "ОШИБКА: не удалось сгенерировать токен." >&2
    exit 1
fi

# Сохраняем токен в файл на общей папке.
echo "${token}" > "${TOKEN_FILE}"
chmod 644 "${TOKEN_FILE}"

echo "  Токен сохранён в /vagrant/dashboard-token.txt"
echo ""
echo "════════════════════════════════════════════════════════"
echo "  KUBERNETES DASHBOARD ГОТОВ"
echo "════════════════════════════════════════════════════════"
echo "  URL:   https://localhost:${DASHBOARD_PORT}"
echo "  Token: ${token}"
echo "════════════════════════════════════════════════════════"
echo ""
echo "  Токен также доступен на хосте: stage2/dashboard-token.txt"
echo "  Для получения нового токена (через 24 часа):"
echo "  kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
echo ""
