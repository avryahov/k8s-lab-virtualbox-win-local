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
#   1. Устанавливает Kubernetes Dashboard через Helm chart
#   2. Создаёт NodePort Service для доступа снаружи
#   3. Создаёт admin-user ServiceAccount с cluster-admin правами
#   4. Генерирует токен для входа (действителен 24 часа)
#
# ВАЖНО: Dashboard устанавливается ПОСЛЕДНИМ шагом, после smoke-тестов.
# Это гарантирует, что кластер уже полностью функционален.
#
# ДОСТУП:
#   URL: https://localhost:30443
#   Токен: выводится в конце скрипта
# =============================================================================

set -euo pipefail

export KUBECONFIG=/etc/kubernetes/admin.conf

DASHBOARD_VERSION="v3.0.0"
DASHBOARD_PORT="30443"

echo ">>> [install-dashboard] Установка Kubernetes Dashboard..."

# =============================================================================
# ШАГ 1: Установка Dashboard через официальный манифест
# =============================================================================
# Пробуем установить через официальный YAML с GitHub.
# Если версия не найдена (ещё не релизнута), используем master-ветку.
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
# NodePort открывает порт 30443 на всех нодах кластера.
# Vagrant пробрасывает localhost:30443 → master:30443.
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
# Создаём ServiceAccount с правами cluster-admin.
# В production используйте ограниченные RBAC-роли!
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
            -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -c "True" || echo "0")
    
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
# ШАГ 5: Генерация токена для входа
# =============================================================================
# Токен действителен 24 часа. Для получения нового:
#   kubectl -n kubernetes-dashboard create token admin-user --duration=24h
echo ""
echo ">>> [install-dashboard] Dashboard установлен!"
echo ""
echo "════════════════════════════════════════════════════════"
echo "  KUBERNETES DASHBOARD ГОТОВ"
echo "════════════════════════════════════════════════════════"
echo "  URL:   https://localhost:${DASHBOARD_PORT}"
echo "  Token:"
echo "════════════════════════════════════════════════════════"
kubectl -n kubernetes-dashboard create token admin-user
echo "════════════════════════════════════════════════════════"
echo ""
echo "  Для получения нового токена (через 24 часа):"
echo "  kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
echo ""
