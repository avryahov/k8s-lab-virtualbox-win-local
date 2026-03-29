#!/usr/bin/env bash
# =============================================================================
# install-dashboard.sh — самый последний шаг stage1
# =============================================================================
#
# ЗАПУСКАТЬ ТОЛЬКО ПОСЛЕ:
#   1. kubeadm init;
#   2. kubeadm join всех worker-нод;
#   3. настройки Calico;
#   4. успешного smoke-теста простого приложения.
#
# ПОЧЕМУ DASHBOARD ЗДЕСЬ:
#   Dashboard — это удобный веб-интерфейс, а не основа жизнеспособности
#   кластера. Поэтому он должен ставиться только тогда, когда кластер уже
#   доказал, что реально работает.
#
# ПОЧЕМУ CHART СКАЧИВАЕТСЯ ИЗ RELEASE, А НЕ ЧЕРЕЗ "helm repo add":
#   Исторический GitHub Pages URL для chart-репозитория Dashboard может
#   переставать работать или отдавать 404. Для учебного стенда важнее
#   воспроизводимость, поэтому здесь используется прямой официальный
#   chart-архив из релиза проекта.
# =============================================================================

set -euo pipefail

HELM_WAIT_TIMEOUT="${HELM_WAIT_TIMEOUT:-10m}"
DASHBOARD_NODEPORT="${DASHBOARD_NODEPORT:-30443}"
DASHBOARD_CHART_VERSION="${DASHBOARD_CHART_VERSION:-7.14.0}"
DASHBOARD_CHART_URL="${DASHBOARD_CHART_URL:-https://github.com/kubernetes/dashboard/releases/download/kubernetes-dashboard-${DASHBOARD_CHART_VERSION}/kubernetes-dashboard-${DASHBOARD_CHART_VERSION}.tgz}"

export KUBECONFIG=/etc/kubernetes/admin.conf

ensure_helm() {
  if command -v helm >/dev/null 2>&1; then
    echo ">>> [dashboard] Helm уже установлен."
    return 0
  fi

  echo ">>> [dashboard] Устанавливаем Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

install_dashboard() {
  local dashboard_proxy_service
  local dashboard_chart_archive

  echo ">>> [dashboard] Скачиваем chart Kubernetes Dashboard ${DASHBOARD_CHART_VERSION} из официального релиза..."
  dashboard_chart_archive="/tmp/kubernetes-dashboard-${DASHBOARD_CHART_VERSION}.tgz"
  rm -f "${dashboard_chart_archive}"
  curl -fsSL -o "${dashboard_chart_archive}" "${DASHBOARD_CHART_URL}"

  echo ">>> [dashboard] Устанавливаем Kubernetes Dashboard через Helm из локального chart-архива..."
  helm upgrade --install kubernetes-dashboard "${dashboard_chart_archive}" \
    --create-namespace \
    --namespace kubernetes-dashboard \
    --wait \
    --timeout "${HELM_WAIT_TIMEOUT}"

  dashboard_proxy_service="$(kubectl get svc -n kubernetes-dashboard --no-headers | awk '/kong-proxy/ {print $1; exit}')"
  if [ -z "${dashboard_proxy_service}" ]; then
    echo "ОШИБКА: не нашли proxy-service Dashboard." >&2
    kubectl get svc -n kubernetes-dashboard >&2 || true
    exit 1
  fi

  echo ">>> [dashboard] Переводим сервис ${dashboard_proxy_service} в NodePort ${DASHBOARD_NODEPORT}..."
  kubectl patch svc "${dashboard_proxy_service}" \
    -n kubernetes-dashboard \
    -p '{"spec":{"type":"NodePort"}}' >/dev/null

  kubectl patch svc "${dashboard_proxy_service}" \
    -n kubernetes-dashboard \
    --type='json' \
    -p="[{\"op\":\"add\",\"path\":\"/spec/ports/0/nodePort\",\"value\":${DASHBOARD_NODEPORT}}]" >/dev/null 2>&1 || \
  kubectl patch svc "${dashboard_proxy_service}" \
    -n kubernetes-dashboard \
    --type='json' \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/ports/0/nodePort\",\"value\":${DASHBOARD_NODEPORT}}]" >/dev/null

  kubectl apply -f - <<'EOF' >/dev/null
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

  echo ">>> [dashboard] Ждём доступность всех deployment Dashboard..."
  kubectl wait --for=condition=Available deployment --all -n kubernetes-dashboard --timeout="${HELM_WAIT_TIMEOUT}"

  echo ""
  echo "========================================================"
  echo "  ТОКЕН ДЛЯ ВХОДА В DASHBOARD:"
  echo "========================================================"
  kubectl -n kubernetes-dashboard create token admin-user --duration=24h
  echo "========================================================"
  echo "  URL: https://localhost:${DASHBOARD_NODEPORT}"
  echo "========================================================"
}

ensure_helm
install_dashboard
