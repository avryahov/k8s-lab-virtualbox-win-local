#!/usr/bin/env bash
# =============================================================================
# finalize-cluster.sh — финальная сетевая настройка stage1 после kubeadm join
# =============================================================================
#
# КОГДА ЗАПУСКАЕТСЯ:
#   Только после того, как master уже инициализирован, а worker-ноды уже
#   выполнили kubeadm join и зарегистрировались в кластере.
#
# ЗАЧЕМ НУЖЕН ОТДЕЛЬНЫЙ ШАГ:
#   В учебном сценарии полезно разделить:
#   1. создание самого кластера;
#   2. подключение worker-нод;
#   3. включение Pod-сети;
#   4. проверку простого приложения;
#   5. установку Dashboard как финального удобства.
#
# ЧТО ДЕЛАЕТ:
#   1. Проверяет, что в API уже видны все ожидаемые ноды.
#   2. Устанавливает Calico CNI, если он ещё не установлен.
#   3. Ждёт, пока ноды перейдут в Ready после включения Pod-сети.
#   4. Проверяет, что системные Pod-ы Calico стали Running/Ready.
#
# ЧЕГО СПЕЦИАЛЬНО НЕ ДЕЛАЕТ:
#   - не ставит Dashboard;
#   - не запускает smoke-test;
#   - не меняет bootstrap-логику master/worker.
#   Эти шаги идут позже и отдельно.
# =============================================================================

set -euo pipefail

EXPECTED_NODE_COUNT="${EXPECTED_NODE_COUNT:-3}"
NODE_COUNT_RETRIES="${NODE_COUNT_RETRIES:-30}"
NODE_COUNT_INTERVAL="${NODE_COUNT_INTERVAL:-10}"
NODE_READY_RETRIES="${NODE_READY_RETRIES:-36}"
NODE_READY_INTERVAL="${NODE_READY_INTERVAL:-10}"
CALICO_VERSION="${CALICO_VERSION:-v3.28.0}"

export KUBECONFIG=/etc/kubernetes/admin.conf

sleep_with_notice() {
  local seconds="${1:?seconds are required}"
  local reason="${2:?reason is required}"
  echo "  Пауза ${seconds} сек: ${reason}"
  sleep "${seconds}"
}

wait_for_node_registration() {
  local expected_nodes="$1"
  local retries="$2"
  local interval="$3"

  echo ">>> [finalize-cluster] Ждём, пока в API появятся все ${expected_nodes} ноды..."

  for attempt in $(seq 1 "${retries}"); do
    local total_nodes
    total_nodes="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"

    if [ "${total_nodes}" = "${expected_nodes}" ]; then
      echo "  В кластере уже видно ${total_nodes}/${expected_nodes} ноды."
      return 0
    fi

    echo "  Попытка ${attempt}/${retries}: найдено ${total_nodes}/${expected_nodes} ноды. Ждём ${interval} сек..."
    sleep "${interval}"
  done

  echo "ОШИБКА: в кластере не появились все ожидаемые ноды." >&2
  kubectl get nodes -o wide >&2 || true
  exit 1
}

install_calico_if_needed() {
  echo ">>> [finalize-cluster] Проверяем Pod-сеть Calico..."

  if kubectl get namespace calico-system >/dev/null 2>&1; then
    echo "  Calico уже установлен, повторно не применяем."
    return 0
  fi

  echo "  Устанавливаем Calico ${CALICO_VERSION}..."
  kubectl apply --server-side --force-conflicts -f \
    "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

  kubectl apply --server-side --force-conflicts -f - <<'EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    bgp: Disabled
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

  # Оператору Calico нужно время на создание CRD, deployment и daemonset-ресурсов.
  sleep_with_notice 180 "ждём первичную настройку Tigera Operator и Calico"
}

wait_for_all_nodes_ready() {
  local expected_nodes="$1"
  local retries="$2"
  local interval="$3"

  echo ">>> [finalize-cluster] Ждём, пока все ${expected_nodes} ноды станут Ready..."

  for attempt in $(seq 1 "${retries}"); do
    local summary
    local total_nodes
    local ready_nodes

    summary="$(kubectl get nodes --no-headers 2>/dev/null | awk 'BEGIN { total = 0; ready = 0 } { total++; if ($2 == "Ready") ready++ } END { print total ":" ready }')"
    total_nodes="${summary%%:*}"
    ready_nodes="${summary##*:}"

    if [ "${total_nodes}" = "${expected_nodes}" ] && [ "${ready_nodes}" = "${expected_nodes}" ]; then
      echo "  Все ${ready_nodes}/${expected_nodes} ноды готовы."
      return 0
    fi

    echo "  Попытка ${attempt}/${retries}: Ready ${ready_nodes}/${expected_nodes}, всего нод ${total_nodes}. Ждём ${interval} сек..."
    sleep "${interval}"
  done

  echo "ОШИБКА: не дождались Ready для всех нод после настройки Calico." >&2
  kubectl get nodes -o wide >&2 || true
  kubectl get pods -n calico-system -o wide >&2 || true
  exit 1
}

wait_for_calico_pods() {
  echo ">>> [finalize-cluster] Проверяем системные Pod-ы Calico..."

  kubectl wait --for=condition=Available deployment/calico-kube-controllers \
    -n calico-system \
    --timeout=300s

  kubectl wait --for=condition=Ready pod \
    -l k8s-app=calico-node \
    -n calico-system \
    --timeout=300s

  echo "  Calico Pod-ы готовы."
}

wait_for_node_registration "${EXPECTED_NODE_COUNT}" "${NODE_COUNT_RETRIES}" "${NODE_COUNT_INTERVAL}"
install_calico_if_needed
wait_for_all_nodes_ready "${EXPECTED_NODE_COUNT}" "${NODE_READY_RETRIES}" "${NODE_READY_INTERVAL}"
wait_for_calico_pods

echo ">>> [finalize-cluster] Готово: cluster networking настроен."
