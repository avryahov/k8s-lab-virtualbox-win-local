#!/usr/bin/env bash
# =============================================================================
# finalize-cluster.sh — финальная сетевая настройка stage1 после kubeadm join
# =============================================================================
#
# КОГДА ЗАПУСКАЕТСЯ:
#   Только после того, как master уже инициализирован, а worker-ноды уже
#   выполнили kubeadm join и зарегистрировались в кластере.
#
# КЕМ ЗАПУСКАЕТСЯ:
#   Вызывается из run-post-bootstrap.ps1 (host-side скрипт на Windows)
#   через: vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/finalize-cluster.sh"
#
# ЗАЧЕМ НУЖЕН ОТДЕЛЬНЫЙ ШАГ:
#   В учебном сценарии полезно разделить:
#   1. создание самого кластера (vagrant up → kubeadm init/join);
#   2. подключение worker-нод;
#   3. включение Pod-сети (Calico);
#   4. проверку простого приложения (smoke-тест);
#   5. установку Dashboard как финального удобства.
#
#   Это разделение учит ученика, что кластер и дополнительные сервисы —
#   не одно и то же. Можно отдельно диагностировать проблемы bootstrap
#   и проблемы финальной настройки.
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
#
# КОНФИГУРИРУЕМЫЕ ПАРАМЕТРЫ (через env-переменные):
#   EXPECTED_NODE_COUNT  — сколько нод ожидаем (по умолчанию 3)
#   NODE_COUNT_RETRIES   — сколько раз проверить регистрацию (по умолчанию 30)
#   NODE_COUNT_INTERVAL  — пауза между проверками регистрации (по умолчанию 10 сек)
#   NODE_READY_RETRIES   — сколько раз проверить Ready (по умолчанию 36)
#   NODE_READY_INTERVAL  — пауза между проверками Ready (по умолчанию 10 сек)
#   CALICO_VERSION       — версия Calico CNI (по умолчанию v3.28.0)
#
# КНИГИ ДЛЯ ИЗУЧЕНИЯ ТЕМЫ:
#   EN: "Kubernetes in Action" — Marko Luksa, гл. 11 (Networking)
#   EN: "The Kubernetes Book" — Nigel Poulton, гл. 6 (Pod Network)
# =============================================================================

# Строгий режим bash:
#   -e: завершить при любой ошибке
#   -u: ошибка если переменная не определена
#   -o pipefail: ошибка если часть конвейера (pipe) упала
set -euo pipefail

# ---------------------------------------------------------------------------
# Конфигурация с значениями по умолчанию
# ---------------------------------------------------------------------------
# ${VAR:-default} — если переменная не установлена, использовать default.
# Это позволяет run-post-bootstrap.ps1 переопределять параметры через env.
EXPECTED_NODE_COUNT="${EXPECTED_NODE_COUNT:-3}"
NODE_COUNT_RETRIES="${NODE_COUNT_RETRIES:-30}"
NODE_COUNT_INTERVAL="${NODE_COUNT_INTERVAL:-10}"
NODE_READY_RETRIES="${NODE_READY_RETRIES:-36}"
NODE_READY_INTERVAL="${NODE_READY_INTERVAL:-10}"
CALICO_VERSION="${CALICO_VERSION:-v3.28.0}"

# KUBECONFIG — файл доступа к кластеру.
# Все kubectl-команды будут использовать этот файл.
export KUBECONFIG=/etc/kubernetes/admin.conf

# ---------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ---------------------------------------------------------------------------

# sleep_with_notice — пауза с пояснением в логе.
# Полезно, когда скрипт «зависает» на несколько минут — ученик видит,
# что происходит, а не думает, что всё сломалось.
sleep_with_notice() {
  local seconds="${1:?seconds are required}"
  local reason="${2:?reason is required}"
  echo "  Пауза ${seconds} сек: ${reason}"
  sleep "${seconds}"
}

# ---------------------------------------------------------------------------
# wait_for_node_registration — ожидание регистрации нод в API
# ---------------------------------------------------------------------------
# Ждёт, пока kubectl get nodes покажет ожидаемое количество нод.
#
# ЗАЧЕМ:
#   kubeadm join на worker-нодах возвращает управление сразу после
#   успешной аутентификации, но нода появляется в API не мгновенно.
#   Нужно подождать, пока control plane зарегистрирует ноду.
#
# КАК РАБОТАЕТ:
#   1. Выполняет kubectl get nodes --no-headers (без заголовков)
#   2. Считает количество строк (wc -l)
#   3. Если количество совпадает с ожидаемым — успех
#   4. Если нет — ждёт и повторяет
#   5. Если исчерпаны все попытки — ошибка с выводом текущего состояния
#
# ПАРАМЕТРЫ:
#   $1 expected_nodes — сколько нод ожидаем (например, 3)
#   $2 retries        — максимальное число попыток
#   $3 interval       — пауза между попытками (секунды)
wait_for_node_registration() {
  local expected_nodes="$1"
  local retries="$2"
  local interval="$3"

  echo ">>> [finalize-cluster] Ждём, пока в API появятся все ${expected_nodes} ноды..."

  for attempt in $(seq 1 "${retries}"); do
    local total_nodes
    # kubectl get nodes --no-headers — вывод без заголовка таблицы.
    # wc -l — количество строк (каждая строка = одна нода).
    # tr -d ' ' — убрать пробелы (wc иногда добавляет ведущие пробелы).
    total_nodes="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"

    if [ "${total_nodes}" = "${expected_nodes}" ]; then
      echo "  В кластере уже видно ${total_nodes}/${expected_nodes} ноды."
      return 0
    fi

    echo "  Попытка ${attempt}/${retries}: найдено ${total_nodes}/${expected_nodes} ноды. Ждём ${interval} сек..."
    sleep "${interval}"
  done

  # Если дошли сюда — все попытки исчерпаны, ноды не зарегистрировались.
  echo "ОШИБКА: в кластере не появились все ожидаемые ноды." >&2
  kubectl get nodes -o wide >&2 || true
  exit 1
}

# ---------------------------------------------------------------------------
# install_calico_if_needed — установка Calico CNI
# ---------------------------------------------------------------------------
# Устанавливает Calico через Tigera Operator, если он ещё не установлен.
#
# ЗАЧЕМ ПРОВЕРКА:
#   В Stage 1 master.sh уже устанавливает Calico. Но если по какой-то
#   причине Calico не был установлен (например, master.sh был прерван),
#   finalize-cluster.sh должен это исправить.
#
# КАК ОПРЕДЕЛЯЕМ, УСТАНОВЛЕН ЛИ CALICO:
#   Проверяем наличие namespace calico-system.
#   Tigera Operator создаёт этот namespace при установке.
#   Если namespace есть — Calico уже работает.
#
# ЧТО ДЕЛАЕТ:
#   1. Применяет Tigera Operator manifest (создаёт CRD и контроллер)
#   2. Применяет Installation CRD (описывает конфигурацию Calico)
#   3. Ждёт 180 секунд, пока оператор развернёт компоненты
install_calico_if_needed() {
  echo ">>> [finalize-cluster] Проверяем Pod-сеть Calico..."

  if kubectl get namespace calico-system >/dev/null 2>&1; then
    echo "  Calico уже установлен, повторно не применяем."
    return 0
  fi

  echo "  Устанавливаем Calico ${CALICO_VERSION}..."

  # Tigera Operator — менеджер для Calico.
  # --server-side --force-conflicts: применяем манифест в server-side режиме.
  # Это значит, что Kubernetes сам управляет полями объекта, а не клиент.
  # --force-conflicts: разрешить конфликты с уже существующими полями.
  kubectl apply --server-side --force-conflicts -f \
    "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

  # Installation CRD — конфигурация Calico.
  # <<'EOF' — heredoc с одинарными кавычками: переменные НЕ подставляются.
  # Это важно, потому что в CRD есть ${POD_CIDR}, но мы хотим жёстко
  # задать 10.244.0.0/16 (стандарт для Stage 1).
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
  # Обычно 2–3 минуты. Без этой паузы следующие проверки могут не найти Calico-поды.
  sleep_with_notice 180 "ждём первичную настройку Tigera Operator и Calico"
}

# ---------------------------------------------------------------------------
# wait_for_all_nodes_ready — ожидание Ready-статуса всех нод
# ---------------------------------------------------------------------------
# Ждёт, пока ВСЕ ноды перейдут в состояние Ready.
#
# ЧТО ТАКОЕ Ready:
#   Ready — это condition ноды, который означает, что нода готова
#   принимать Pod-ы. Он становится true, когда:
#     - kubelet работает и отвечает
#     - сеть настроена (Calico поды запущены)
#     - нет критических проблем (диск, память)
#
# КАК РАБОТАЕТ:
#   1. Выполняет kubectl get nodes --no-headers
#   2. С помощью awk подсчитывает:
#      - total: общее количество нод
#      - ready: количество нод со статусом Ready
#   3. Если total == expected И ready == expected — успех
#   4. Иначе — ждёт и повторяет
#
# ПАРАМЕТРЫ:
#   $1 expected_nodes — сколько нод ожидаем
#   $2 retries        — максимальное число попыток
#   $3 interval       — пауза между попытками (секунды)
wait_for_all_nodes_ready() {
  local expected_nodes="$1"
  local retries="$2"
  local interval="$3"

  echo ">>> [finalize-cluster] Ждём, пока все ${expected_nodes} ноды станут Ready..."

  for attempt in $(seq 1 "${retries}"); do
    local summary
    local total_nodes
    local ready_nodes

    # awk-скрипт:
    #   BEGIN { total = 0; ready = 0 } — начальная инициализация
    #   { total++; if ($2 == "Ready") ready++ } — для каждой строки:
    #     total++ — считаем ноду
    #     если второй столбец (статус) == "Ready" — считаем готовую
    #   END { print total ":" ready } — выводим результат "total:ready"
    summary="$(kubectl get nodes --no-headers 2>/dev/null | awk 'BEGIN { total = 0; ready = 0 } { total++; if ($2 == "Ready") ready++ } END { print total ":" ready }')"
    total_nodes="${summary%%:*}"    # Всё до двоеточия = total
    ready_nodes="${summary##*:}"    # Всё после двоеточия = ready

    if [ "${total_nodes}" = "${expected_nodes}" ] && [ "${ready_nodes}" = "${expected_nodes}" ]; then
      echo "  Все ${ready_nodes}/${expected_nodes} ноды готовы."
      return 0
    fi

    echo "  Попытка ${attempt}/${retries}: Ready ${ready_nodes}/${expected_nodes}, всего нод ${total_nodes}. Ждём ${interval} сек..."
    sleep "${interval}"
  done

  # Если дошли сюда — ноды не стали Ready за отведённое время.
  # Выводим диагностическую информацию.
  echo "ОШИБКА: не дождались Ready для всех нод после настройки Calico." >&2
  kubectl get nodes -o wide >&2 || true
  kubectl get pods -n calico-system -o wide >&2 || true
  exit 1
}

# ---------------------------------------------------------------------------
# wait_for_calico_pods — проверка готовности Calico-подов
# ---------------------------------------------------------------------------
# Ждёт, пока все системные Pod-ы Calico станут Available/Ready.
#
# ЧТО ПРОВЕРЯЕМ:
#   1. calico-kube-controllers — deployment, управляет IPAM и политиками
#   2. calico-node — daemonset, работает на каждой ноде, реализует сеть
#
# ПОЧЕМУ ДВЕ ПРОВЕРКИ:
#   kube-controllers — это deployment (один под), проверяем Available.
#   calico-node — это daemonset (под на каждой ноде), проверяем Ready.
wait_for_calico_pods() {
  echo ">>> [finalize-cluster] Проверяем системные Pod-ы Calico..."

  # calico-kube-controllers — контроллер Calico.
  # Управляет IP Address Management (IPAM) и NetworkPolicy.
  # --for=condition=Available — deployment считается доступным,
  #   когда минимум одна реплика готова и обслуживает трафик.
  kubectl wait --for=condition=Available deployment/calico-kube-controllers \
    -n calico-system \
    --timeout=300s

  # calico-node — агент Calico на каждой ноде.
  # Реализует VXLAN-туннели, IPAM, NetworkPolicy на уровне ноды.
  # -l k8s-app=calico-node — выбрать все поды с этим лейблом.
  # --for=condition=Ready — под готов, все контейнеры запустились.
  kubectl wait --for=condition=Ready pod \
    -l k8s-app=calico-node \
    -n calico-system \
    --timeout=300s

  echo "  Calico Pod-ы готовы."
}

# =============================================================================
# ОСНОВНОЙ ПОТОК ВЫПОЛНЕНИЯ
# =============================================================================
# Порядок критически важен:
#   1. Ноды должны зарегистрироваться в API
#   2. Calico должен быть установлен (если ещё не стоит)
#   3. Ноды должны стать Ready (после настройки сети)
#   4. Calico-поды должны быть готовы
#
# Нарушение порядка приведёт к ошибкам:
#   - Проверка Calico до регистрации нод — бессмысленна
#   - Проверка Ready до установки Calico — ноды не станут Ready без сети
#   - Проверка Calico-подов до установки — поды не найдены

wait_for_node_registration "${EXPECTED_NODE_COUNT}" "${NODE_COUNT_RETRIES}" "${NODE_COUNT_INTERVAL}"
install_calico_if_needed
wait_for_all_nodes_ready "${EXPECTED_NODE_COUNT}" "${NODE_READY_RETRIES}" "${NODE_READY_INTERVAL}"
wait_for_calico_pods

echo ""
echo ">>> [finalize-cluster] Готово: cluster networking настроен."
echo "    Следующий шаг: smoke-тест (nginx-smoke)"
