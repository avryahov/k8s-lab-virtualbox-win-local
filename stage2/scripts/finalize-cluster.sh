#!/usr/bin/env bash
# =============================================================================
# finalize-cluster.sh — Финализация кластера после присоединения всех нод
# =============================================================================
#
# ЗАПУСКАЕТСЯ НА: master-ноде
# ЗАПУСКАЕТСЯ ПОСЛЕ: того как все worker-ноды присоединились через kubeadm join
# ЗАПУСКАЕТСЯ КАК: root
#
# ЧТО ДЕЛАЕТ:
#   1. Ждёт регистрации всех нод в кластере
#   2. Проверяет готовность нод (Ready)
#   3. Проверяет готовность Pod-ов Calico
#   4. Сообщает об успехе или ошибке
#
# АРГУМЕНТЫ (передаются из run-post-bootstrap.ps1):
#   EXPECTED_NODE_COUNT — ожидаемое количество нод
#   NODE_COUNT_RETRIES — макс. число попыток проверки нод
#   NODE_COUNT_INTERVAL — пауза между попытками (сек)
#   NODE_READY_RETRIES — макс. число попыток проверки Ready
#   NODE_READY_INTERVAL — пауза между попытками (сек)
#
# ИДЕМПОТЕНТНОСТЬ: безопасно запускать несколько раз.
# =============================================================================

set -euo pipefail

EXPECTED_NODE_COUNT="${EXPECTED_NODE_COUNT:-3}"
NODE_COUNT_RETRIES="${NODE_COUNT_RETRIES:-30}"
NODE_COUNT_INTERVAL="${NODE_COUNT_INTERVAL:-10}"
NODE_READY_RETRIES="${NODE_READY_RETRIES:-36}"
NODE_READY_INTERVAL="${NODE_READY_INTERVAL:-10}"

export KUBECONFIG=/etc/kubernetes/admin.conf

echo ">>> [finalize-cluster] Начало финализации кластера"
echo "    Ожидаемое количество нод: ${EXPECTED_NODE_COUNT}"

# =============================================================================
# ШАГ 1: Ожидание регистрации всех нод
# =============================================================================
echo ">>> [ШАГ 1] Ожидание регистрации всех нод..."

for ((attempt=1; attempt<=NODE_COUNT_RETRIES; attempt++)); do
    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    
    if [ "$node_count" -eq "$EXPECTED_NODE_COUNT" ]; then
        echo "  Все ноды зарегистрированы: ${node_count}/${EXPECTED_NODE_COUNT}"
        break
    fi
    
    if [ "$attempt" -eq "$NODE_COUNT_RETRIES" ]; then
        echo "  ОШИБКА: Таймаут ожидания нод (${NODE_COUNT_RETRIES} попыток по ${NODE_COUNT_INTERVAL} сек)" >&2
        kubectl get nodes -o wide
        exit 1
    fi
    
    echo "  Найдено ${node_count}/${EXPECTED_NODE_COUNT} нод. Попытка ${attempt}/${NODE_COUNT_RETRIES}..."
    sleep "$NODE_COUNT_INTERVAL"
done

# =============================================================================
# ШАГ 2: Ожидание готовности нод (Ready)
# =============================================================================
echo ">>> [ШАГ 2] Ожидание готовности нод (Ready)..."

for ((attempt=1; attempt<=NODE_READY_RETRIES; attempt++)); do
    ready_count=$(kubectl get nodes --no-headers -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
    
    if [ "$ready_count" -eq "$EXPECTED_NODE_COUNT" ]; then
        echo "  Все ноды готовы: ${ready_count}/${EXPECTED_NODE_COUNT}"
        break
    fi
    
    if [ "$attempt" -eq "$NODE_READY_RETRIES" ]; then
        echo "  ОШИБКА: Таймаут ожидания готовности нод (${NODE_READY_RETRIES} попыток)" >&2
        kubectl get nodes -o wide
        exit 1
    fi
    
    echo "  Готовы ${ready_count}/${EXPECTED_NODE_COUNT} нод. Попытка ${attempt}/${NODE_READY_RETRIES}..."
    sleep "$NODE_READY_INTERVAL"
done

# =============================================================================
# ШАГ 3: Проверка Pod-ов Calico
# =============================================================================
echo ">>> [ШАГ 3] Проверка Pod-ов Calico в namespace calico-system..."

# Ждём до 5 минут, пока Pod-ы Calico запустятся
for ((attempt=1; attempt<=30; attempt++)); do
    # Проверяем, есть ли deployment/calico-typha или daemonset/calico-node
    if kubectl get daemonset calico-node -n calico-system >/dev/null 2>&1; then
        # Проверяем количество готовых Pod-ов
        desired=$(kubectl get daemonset calico-node -n calico-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        ready=$(kubectl get daemonset calico-node -n calico-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        
        if [ "$ready" -eq "$desired" ] && [ "$desired" -gt "0" ]; then
            echo "  Calico daemonset готов: ${ready}/${desired}"
            break
        fi
        
        echo "  Calico: ${ready}/${desired} нод готовы. Попытка ${attempt}/30..."
    else
        echo "  Calico daemonset ещё не создан. Попытка ${attempt}/30..."
    fi
    
    if [ "$attempt" -eq "30" ]; then
        echo "  ПРЕДУПРЕЖДЕНИЕ: Calico не вышел на полный готовность за 5 минут"
        kubectl get pods -n calico-system -o wide 2>/dev/null || echo "  calico-system namespace не найден"
        break
    fi
    
    sleep 10
done

# =============================================================================
# ФИНАЛ: Вывод состояния кластера
# =============================================================================
echo ""
echo ">>> [finalize-cluster] Кластер готов!"
echo ""
echo "=== НОДЫ ==="
kubectl get nodes -o wide
echo ""
echo "=== SYSTEM POD-Ы ==="
kubectl get pods -n kube-system -o wide
echo ""
echo "=== CALICO POD-Ы ==="
kubectl get pods -n calico-system -o wide 2>/dev/null || echo "calico-system не найден"
