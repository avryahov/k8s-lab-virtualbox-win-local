#!/usr/bin/env bash
# =============================================================================
# install-dashboard.sh — самый последний шаг stage1
# =============================================================================
#
# ЗАПУСКАТЬ ТОЛЬКО ПОСЛЕ:
#   1. kubeadm init (master инициализирован);
#   2. kubeadm join всех worker-нод (воркеры в кластере);
#   3. настройки Calico (Pod-сеть работает, все ноды в Ready);
#   4. успешного smoke-теста простого приложения (nginx-smoke).
#
# КЕМ ЗАПУСКАЕТСЯ:
#   Вызывается из run-post-bootstrap.ps1 (host-side скрипт на Windows)
#   через: vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/install-dashboard.sh"
#
# ПОЧЕМУ DASHBOARD ЗДЕСЬ:
#   Dashboard — это удобный веб-интерфейс, а не основа жизнеспособности
#   кластера. Поэтому он должен ставиться только тогда, когда кластер уже
#   доказал, что реально работает.
#
#   Учебный приоритет:
#     1. ноды → 2. кластер → 3. сеть → 4. приложение → 5. веб-интерфейс
#
#   Если Dashboard поставить раньше, ученик может увидеть «красивую
#   картинку» с неработающим кластером и не понять, что проблема
#   не в Dashboard, а в базовой инфраструктуре.
#
# ПОЧЕМУ CHART СКАЧИВАЕТСЯ ИЗ RELEASE, А НЕ ЧЕРЕЗ "helm repo add":
#   Исторический GitHub Pages URL для chart-репозитория Dashboard может
#   переставать работать или отдавать 404. Для учебного стенда важнее
#   воспроизводимость, поэтому здесь используется прямой официальный
#   chart-архив из релиза проекта.
#
#   Прямая ссылка на .tgz-файл гарантирует, что мы получим именно
#   ту версию chart, которую указали, без зависимости от репозитория.
#
# КОНФИГУРИРУЕМЫЕ ПАРАМЕТРЫ (через env-переменные):
#   HELM_WAIT_TIMEOUT       — таймаут ожидания Helm (по умолчанию 10m)
#   DASHBOARD_NODEPORT      — порт Dashboard на ноде (по умолчанию 30443)
#   DASHBOARD_CHART_VERSION — версия Helm chart (по умолчанию 7.14.0)
#
# КНИГИ ДЛЯ ИЗУЧЕНИЯ ТЕМЫ:
#   EN: "Kubernetes in Action" — Marko Luksa, гл. 13 (Dashboard и UI)
#   DOCS: https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
# =============================================================================

# Строгий режим bash:
#   -e: завершить при любой ошибке
#   -u: ошибка если переменная не определена
#   -o pipefail: ошибка если часть конвейера (pipe) упала
set -euo pipefail

# ---------------------------------------------------------------------------
# Конфигурация с значениями по умолчанию
# ---------------------------------------------------------------------------
HELM_WAIT_TIMEOUT="${HELM_WAIT_TIMEOUT:-10m}"
DASHBOARD_NODEPORT="${DASHBOARD_NODEPORT:-30443}"
DASHBOARD_CHART_VERSION="${DASHBOARD_CHART_VERSION:-7.14.0}"

# Прямая ссылка на .tgz-архив Helm chart из GitHub Releases.
# Формат: https://github.com/kubernetes/dashboard/releases/download/<тег>/<имя>-<версия>.tgz
DASHBOARD_CHART_URL="${DASHBOARD_CHART_URL:-https://github.com/kubernetes/dashboard/releases/download/kubernetes-dashboard-${DASHBOARD_CHART_VERSION}/kubernetes-dashboard-${DASHBOARD_CHART_VERSION}.tgz}"

# KUBECONFIG — файл доступа к кластеру.
export KUBECONFIG=/etc/kubernetes/admin.conf

# ---------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ---------------------------------------------------------------------------

# ensure_helm — установка Helm, если ещё не установлен.
#
# ЧТО ТАКОЕ HELM:
#   Helm — пакетный менеджер для Kubernetes (как apt для Ubuntu).
#   Устанавливает приложения через «chart» — набор YAML-манифестов
#   с параметрами. Вместо десятков kubectl apply -f ... — одна команда.
#
# ПОЧЕМУ НЕ KUBECTL APPLY:
#   Dashboard через Helm chart включает:
#     - Настройку параметров (NodePort, ресурсы, tolerations)
#     - Зависимости (например, kong-proxy для маршрутизации)
#     - Helm hooks для правильной последовательности установки
#   Прямое применение манифестов не даст этой гибкости.
#
# УСТАНОВКА:
#   Скачиваем официальный скрипт get-helm-3 с GitHub.
#   Скрипт определяет ОС, скачивает бинарник и кладёт в /usr/local/bin.
ensure_helm() {
  if command -v helm >/dev/null 2>&1; then
    echo ">>> [dashboard] Helm уже установлен."
    return 0
  fi

  echo ">>> [dashboard] Устанавливаем Helm..."
  # curl -fsSL:
  #   -f: fail silently на HTTP-ошибки
  #   -s: тихий режим
  #   -S: показывать ошибки
  #   -L: следовать за редиректами
  # | bash — выполнить скачанный скрипт
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  echo "  Helm установлен"
}

# install_dashboard — установка и настройка Kubernetes Dashboard.
#
# ЭТАПЫ:
#   1. Скачать Helm chart из GitHub Releases
#   2. Установить Dashboard через helm upgrade --install
#   3. Найти kong-proxy service (прокси для Dashboard)
#   4. Перевести сервис в NodePort с нужным портом
#   5. Создать admin-user ServiceAccount и ClusterRoleBinding
#   6. Подождать, пока все deployment станут Available
#   7. Вывести токен и URL для входа
install_dashboard() {
  local dashboard_proxy_service
  local dashboard_chart_archive

  # -----------------------------------------------------------------------
  # Этап 1: Скачивание Helm chart
  # -----------------------------------------------------------------------
  echo ">>> [dashboard] Скачиваем chart Kubernetes Dashboard ${DASHBOARD_CHART_VERSION} из официального релиза..."
  dashboard_chart_archive="/tmp/kubernetes-dashboard-${DASHBOARD_CHART_VERSION}.tgz"
  rm -f "${dashboard_chart_archive}"  # Удаляем старый файл, если остался
  curl -fsSL -o "${dashboard_chart_archive}" "${DASHBOARD_CHART_URL}"
  echo "  Chart скачан: ${dashboard_chart_archive}"

  # -----------------------------------------------------------------------
  # Этап 2: Установка Dashboard через Helm
  # -----------------------------------------------------------------------
  # helm upgrade --install — «upsert»-операция:
  #   - Если релиз не существует — создаёт (install)
  #   - Если существует — обновляет (upgrade)
  #
  # ПАРАМЕТРЫ:
  #   kubernetes-dashboard — имя релиза (произвольное, для helm list)
  #   --create-namespace — создать namespace, если не существует
  #   --namespace — установить в этот namespace
  #   --wait — ждать, пока все ресурсы станут Ready
  #   --timeout — максимальное время ожидания
  echo ">>> [dashboard] Устанавливаем Kubernetes Dashboard через Helm..."
  helm upgrade --install kubernetes-dashboard "${dashboard_chart_archive}" \
    --create-namespace \
    --namespace kubernetes-dashboard \
    --wait \
    --timeout "${HELM_WAIT_TIMEOUT}"
  echo "  Dashboard установлен через Helm"

  # -----------------------------------------------------------------------
  # Этап 3: Поиск kong-proxy service
  # -----------------------------------------------------------------------
  # Dashboard chart создаёт несколько сервисов. Нам нужен kong-proxy —
  # это прокси, через который идёт трафик к Dashboard UI.
  #
  # awk '/kong-proxy/ {print $1; exit}' — найти строку с "kong-proxy"
  # и вывести первое поле (имя сервиса), затем выйти.
  dashboard_proxy_service="$(kubectl get svc -n kubernetes-dashboard --no-headers | awk '/kong-proxy/ {print $1; exit}')"
  if [ -z "${dashboard_proxy_service}" ]; then
    echo "ОШИБКА: не нашли proxy-service Dashboard." >&2
    kubectl get svc -n kubernetes-dashboard >&2 || true
    exit 1
  fi
  echo "  kong-proxy service найден: ${dashboard_proxy_service}"

  # -----------------------------------------------------------------------
  # Этап 4: Перевод сервиса в NodePort
  # -----------------------------------------------------------------------
  # По умолчанию kong-proxy может быть ClusterIP или LoadBalancer.
  # Нам нужен NodePort — чтобы пробросить порт через Vagrant на хост.
  #
  # kubectl patch — изменить существующий ресурс без полного пересоздания.
  # -p '{"spec":{"type":"NodePort"}}' — изменить тип сервиса на NodePort.
  echo ">>> [dashboard] Переводим сервис ${dashboard_proxy_service} в NodePort ${DASHBOARD_NODEPORT}..."
  kubectl patch svc "${dashboard_proxy_service}" \
    -n kubernetes-dashboard \
    -p '{"spec":{"type":"NodePort"}}' >/dev/null

  # Устанавливаем конкретный номер порта (30443).
  # NodePort по умолчанию выбирает случайный порт из диапазона 30000–32767.
  # Нам нужен фиксированный порт для проброса через Vagrant.
  #
  # --type='json' — JSON Patch (RFC 6902).
  # [{"op":"add",...}] — попытка добавить поле nodePort.
  # Если уже есть — fallback на "replace".
  kubectl patch svc "${dashboard_proxy_service}" \
    -n kubernetes-dashboard \
    --type='json' \
    -p="[{\"op\":\"add\",\"path\":\"/spec/ports/0/nodePort\",\"value\":${DASHBOARD_NODEPORT}}]" >/dev/null 2>&1 || \
  kubectl patch svc "${dashboard_proxy_service}" \
    -n kubernetes-dashboard \
    --type='json' \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/ports/0/nodePort\",\"value\":${DASHBOARD_NODEPORT}}]" >/dev/null
  echo "  NodePort установлен: ${DASHBOARD_NODEPORT}"

  # -----------------------------------------------------------------------
  # Этап 5: Создание admin-user и RBAC
  # -----------------------------------------------------------------------
  # ServiceAccount — учётная запись для процессов внутри Kubernetes.
  # ClusterRoleBinding — связывает ServiceAccount с ролью cluster-admin.
  #
  # --- (три дефиса) — разделитель YAML-документов.
  # Позволяет создать несколько ресурсов в одном kubectl apply.
  #
  # ПРЕДУПРЕЖДЕНИЕ:
  #   cluster-admin даёт ПОЛНЫЙ доступ ко всему кластеру.
  #   В production использовать НЕЛЬЗЯ! Нужно создавать ограниченную роль.
  #   Здесь это допустимо, потому что это учебный стенд.
  kubectl apply -f - <<'EOF'
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

  # -----------------------------------------------------------------------
  # Этап 6: Ожидание доступности Dashboard
  # -----------------------------------------------------------------------
  # Ждём, пока все deployment в namespace kubernetes-dashboard станут Available.
  # --for=condition=Available — deployment доступен и обслуживает трафик.
  # deployment --all — все deployment в namespace.
  echo ">>> [dashboard] Ждём доступность всех deployment Dashboard..."
  kubectl wait --for=condition=Available deployment --all -n kubernetes-dashboard --timeout="${HELM_WAIT_TIMEOUT}"
  echo "  Все deployment Dashboard доступны"

  # -----------------------------------------------------------------------
  # Этап 7: Вывод токена и URL
  # -----------------------------------------------------------------------
  # create token — создаёт временный токен для аутентификации.
  # --duration=24h — токен действителен 24 часа.
  # После истечения нужно сгенерировать новый.
  #
  # ТОКЕН — это длинная строка, которую нужно вставить в поле
  # «Enter token» на странице входа в Dashboard.
  echo ""
  echo "========================================================"
  echo "  ТОКЕН ДЛЯ ВХОДА В DASHBOARD:"
  echo "========================================================"
  kubectl -n kubernetes-dashboard create token admin-user --duration=24h
  echo "========================================================"
  echo "  URL: https://localhost:${DASHBOARD_NODEPORT}"
  echo "========================================================"
  echo ""
  echo "  Инструкция:"
  echo "  1. Открой https://localhost:${DASHBOARD_NODEPORT} в браузере"
  echo "  2. Подтверди переход через предупреждение о самоподписанном сертификате"
  echo "  3. Выбери 'Token' и вставь токен выше"
  echo "  4. Нажми 'Sign in'"
}

# =============================================================================
# ОСНОВНОЙ ПОТОК ВЫПОЛНЕНИЯ
# =============================================================================
ensure_helm
install_dashboard

echo ""
echo ">>> [install-dashboard.sh] Готово! Dashboard доступен по адресу:"
echo "    https://localhost:${DASHBOARD_NODEPORT}"
