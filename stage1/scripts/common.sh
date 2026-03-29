#!/usr/bin/env bash
# =============================================================================
# common.sh — Общая подготовка всех нод кластера
# =============================================================================
#
# ЗАПУСКАЕТСЯ НА: master, worker1, worker2
# ЗАПУСКАЕТСЯ: автоматически через Vagrant (provisioner shell)
# ЗАПУСКАЕТСЯ КАК: root
#
# ЧТО ДЕЛАЕТ:
#   1. Отключает swap (подкачку)
#   2. Настраивает сетевые параметры ядра Linux
#   3. Устанавливает containerd (среду запуска контейнеров)
#   4. Устанавливает kubeadm, kubelet, kubectl
#   5. Прописывает адреса нод в /etc/hosts
#   6. Указывает kubelet использовать правильный IP-адрес
#
# ИДЕМПОТЕНТНОСТЬ: скрипт безопасно запускать несколько раз — повторный
# запуск не сломает уже настроенную систему.
#
# КНИГИ ДЛЯ ИЗУЧЕНИЯ ТЕМЫ:
#   EN: "Kubernetes in Action" — Marko Luksa, Manning (2nd ed.)
#   RU: «Kubernetes в действии» — Марко Лукша, ДМК Пресс
# =============================================================================

# Строгий режим bash:
#   -e: завершить при любой ошибке
#   -u: ошибка если переменная не определена
#   -o pipefail: ошибка если часть конвейера (pipe) упала
set -euo pipefail

# Переменная NODE_IP передаётся из Vagrantfile через env: { "NODE_IP" => "..." }
# Это IP-адрес ВТОРОГО сетевого адаптера (host-only сеть 192.168.56.x).
# Kubernetes использует этот IP для общения между нодами.
NODE_IP="${NODE_IP:?Переменная NODE_IP обязательна. Проверь Vagrantfile.}"

echo ">>> [common.sh] Начало настройки ноды. NODE_IP=${NODE_IP}"

# =============================================================================
# ШАГ 1: Обновление системы и установка утилит
# =============================================================================
# ЗАЧЕМ: Нужны свежие пакеты и утилиты для дальнейшей настройки.
# curl   — скачивать файлы (GPG-ключи, манифесты)
# gnupg  — проверять цифровые подписи репозиториев
# apt-transport-https — разрешает apt работать по HTTPS
echo ">>> [ШАГ 1] Обновление apt и установка базовых утилит..."
export DEBIAN_FRONTEND=noninteractive  # Отключаем интерактивные вопросы apt
apt-get update -qq
apt-get install -y -qq \
  curl \
  gnupg \
  apt-transport-https \
  ca-certificates \
  lsb-release \
  tree

# =============================================================================
# ШАГ 2: Отключение swap (подкачки)
# =============================================================================
# ЧТО ТАКОЕ SWAP: Когда RAM заканчивается, Linux записывает часть памяти
# на диск (swap). Это медленно, но позволяет системе не падать.
#
# ПОЧЕМУ KUBERNETES ТРЕБУЕТ ОТКЛЮЧИТЬ SWAP:
#   Планировщик K8s (kube-scheduler) точно знает, сколько RAM есть на ноде,
#   и распределяет Pod-ы исходя из этого. Если swap включён — реальное
#   потребление памяти непредсказуемо. Kubelet по умолчанию откажется
#   запускаться при включённом swap.
#
# ЧТО СЛОМАЕТСЯ ЕСЛИ НЕ СДЕЛАТЬ: kubelet не запустится, нода не войдёт
# в кластер.
#
# Документация: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
echo ">>> [ШАГ 2] Отключение swap..."
if swapon --show | grep -q .; then
  swapoff -a
  echo "  swap отключён"
else
  echo "  swap уже выключен"
fi

# Закомментируем строки swap в /etc/fstab — чтобы swap не вернулся после перезагрузки.
# fstab — файл автоматического монтирования дисков при старте системы.
# sed -i 's/...' — редактируем файл на месте (-i = in-place).
# Регулярное выражение: если строка содержит слово "swap" — поставить # в начало.
sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab
echo "  строки swap закомментированы в /etc/fstab"

# =============================================================================
# ШАГ 3: Загрузка модулей ядра Linux
# =============================================================================
# Kubernetes использует специальные возможности ядра Linux.
# Их нужно явно включить, загрузив модули.
#
# overlay — файловая система для слоёв контейнеров (OverlayFS).
#   Каждый контейнер имеет «слои»: базовый образ (read-only) +
#   слой изменений (read-write). overlay реализует это прозрачно.
#
# br_netfilter — мост + netfilter (iptables).
#   Позволяет iptables фильтровать трафик, проходящий через виртуальные
#   сетевые мосты. Без этого Kubernetes Service-ы не будут маршрутизировать
#   трафик между Pod-ами.
echo ">>> [ШАГ 3] Загрузка модулей ядра..."

# Файл /etc/modules-load.d/k8s.conf — список модулей для автозагрузки при старте.
# Без этого после перезагрузки ВМ модули не загрузятся.
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# modprobe — загрузить модуль прямо сейчас (без перезагрузки).
modprobe overlay
modprobe br_netfilter
echo "  модули overlay и br_netfilter загружены"

# =============================================================================
# ШАГ 4: Настройка параметров сети ядра (sysctl)
# =============================================================================
# sysctl — механизм настройки параметров работающего ядра Linux.
# Параметры хранятся в /proc/sys/ и применяются через файлы в /etc/sysctl.d/
#
# net.bridge.bridge-nf-call-iptables = 1
#   Заставить iptables обрабатывать трафик, проходящий через сетевые мосты.
#   Без этого: Pod A не может достучаться до Service B через kube-proxy.
#
# net.bridge.bridge-nf-call-ip6tables = 1
#   То же для IPv6 (для совместимости, даже если не используем IPv6).
#
# net.ipv4.ip_forward = 1
#   Разрешить ядру перенаправлять IP-пакеты между сетевыми интерфейсами.
#   Без этого: пакеты из Pod-сети (10.244.x.x) не дойдут до внешней сети.
#   По умолчанию в Linux эта функция выключена (Linux — не маршрутизатор).
echo ">>> [ШАГ 4] Настройка параметров ядра (sysctl)..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Применить все файлы из /etc/sysctl.d/ прямо сейчас (без перезагрузки).
sysctl --system > /dev/null
echo "  параметры ядра применены"

# =============================================================================
# ШАГ 5: Установка containerd
# =============================================================================
# ЧТО ТАКОЕ CONTAINERD:
#   Среда запуска контейнеров (Container Runtime). Это программа, которая
#   реально скачивает образы и запускает контейнеры. Kubernetes не работает
#   напрямую с контейнерами — он делегирует это containerd через CRI
#   (Container Runtime Interface).
#
#   Цепочка: kubectl → API Server → kubelet → CRI → containerd → контейнер
#
# ПОЧЕМУ НЕ DOCKER:
#   Docker = containerd + утилиты для разработчика (docker build, docker run...).
#   Kubernetes нужен только containerd (или другая CRI-совместимая среда).
#   Docker как среда запуска устарел с K8s 1.24 (Dockershim удалён).
#
# ОТКУДА БЕРЁМ: из стандартного репозитория Ubuntu (apt.ubuntu.com).
# Версия: та, которую Ubuntu 24.04 считает стабильной.
echo ">>> [ШАГ 5] Установка containerd..."
apt-get install -y -qq containerd

# =============================================================================
# ШАГ 6: Конфигурация containerd
# =============================================================================
# containerd работает с конфигурационным файлом /etc/containerd/config.toml.
# Формат TOML (Tom's Obvious Minimal Language) — простой язык конфигурации.
#
# ПРОБЛЕМА: По умолчанию containerd использует cgroupfs для управления
# ресурсами контейнеров. Но Ubuntu 24.04 (и большинство современных дистрибутивов)
# используют systemd как систему инициализации, и systemd сам управляет cgroups.
# Если и containerd, и systemd пытаются управлять cgroups по-разному — конфликт.
#
# РЕШЕНИЕ: Включить SystemdCgroup = true.
# Тогда containerd передаёт управление cgroups системному systemd.
# Это рекомендовано для всех систем с systemd.
#
# ДОКУМЕНТАЦИЯ: https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
echo ">>> [ШАГ 6] Настройка containerd (SystemdCgroup)..."
mkdir -p /etc/containerd

# Генерируем конфиг по умолчанию.
# containerd config default выводит полный конфиг, tee записывает в файл и
# дублирует вывод в консоль.
containerd config default | tee /etc/containerd/config.toml > /dev/null

# Меняем SystemdCgroup = false → SystemdCgroup = true.
# sed -i — редактировать файл на месте.
# Ищем точную строку с "SystemdCgroup = false" и заменяем.
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Проверим, что замена сработала.
if grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
  echo "  SystemdCgroup = true — OK"
else
  echo "  ОШИБКА: SystemdCgroup не был изменён!" >&2
  exit 1
fi

# Перезапускаем containerd, чтобы новый конфиг применился.
systemctl restart containerd
systemctl enable containerd
echo "  containerd запущен и включён в автозагрузку"

# =============================================================================
# ШАГ 7: Добавление репозитория Kubernetes
# =============================================================================
# Kubernetes не входит в стандартный репозиторий Ubuntu. Его нужно добавить
# вручную из официального источника.
#
# GPG-ключ — цифровая подпись. apt проверяет, что скачанные пакеты
# действительно подписаны разработчиками Kubernetes (защита от подмены).
#
# Репозиторий: pkgs.k8s.io — официальный репозиторий Kubernetes.
# v1.34 — версия, которую мы устанавливаем.
echo ">>> [ШАГ 7] Добавление репозитория Kubernetes..."
mkdir -p /etc/apt/keyrings

# Скачиваем GPG-ключ и сохраняем в двоичном формате (.gpg).
# --dearmor: конвертирует ASCII-armored PGP-ключ в бинарный формат.
# --yes: разрешает перезаписать уже существующий keyring при повторном provision без интерактивного вопроса.
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Добавляем строку репозитория в sources.list.d/.
# signed-by= указывает какой GPG-ключ используется для проверки пакетов.
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
echo "  репозиторий Kubernetes добавлен"

# =============================================================================
# ШАГ 8: Установка Kubernetes-компонентов
# =============================================================================
# kubeadm  — инструмент для инициализации и управления кластером.
#            Используем для: kubeadm init (master), kubeadm join (workers).
#
# kubelet  — агент Kubernetes, работает на каждой ноде.
#            Отвечает за: запуск Pod-ов, мониторинг их здоровья,
#            выполнение команд control plane.
#
# kubectl  — CLI-утилита для управления кластером (для пользователя).
#            Примеры: kubectl get pods, kubectl apply -f ..., kubectl logs ...
echo ">>> [ШАГ 8] Установка kubeadm, kubelet, kubectl..."
apt-get install -y -qq kubelet kubeadm kubectl

# apt-mark hold — «заморозить» версию пакета.
# Запрещает apt автоматически обновлять эти пакеты.
# ЗАЧЕМ: Случайное обновление K8s может сломать работающий кластер.
# Обновление K8s — отдельный плановый процесс (kubeadm upgrade).
apt-mark hold kubelet kubeadm kubectl
echo "  kubeadm, kubelet, kubectl установлены и заморожены на версии $(kubeadm version -o short)"

# =============================================================================
# ШАГ 9: Настройка /etc/hosts
# =============================================================================
# /etc/hosts — локальная таблица DNS. Позволяет разрешать имена хостов
# без внешнего DNS-сервера.
#
# ЗАЧЕМ: Kubernetes использует hostname нод (k8s-master, k8s-worker1, ...)
# для коммуникации. Воркеры должны уметь найти мастер по имени.
# Без этого kubeadm join провалится с ошибкой "connection refused".
echo ">>> [ШАГ 9] Настройка /etc/hosts..."

# Добавляем записи только если их ещё нет (идемпотентность).
grep -qF "192.168.56.10 k8s-master"  /etc/hosts || \
  echo "192.168.56.10 k8s-master"  >> /etc/hosts

grep -qF "192.168.56.11 k8s-worker1" /etc/hosts || \
  echo "192.168.56.11 k8s-worker1" >> /etc/hosts

grep -qF "192.168.56.12 k8s-worker2" /etc/hosts || \
  echo "192.168.56.12 k8s-worker2" >> /etc/hosts

echo "  /etc/hosts обновлён"

# =============================================================================
# ШАГ 10: Настройка NODE_IP для kubelet
# =============================================================================
# ПРОБЛЕМА: У каждой ВМ два сетевых интерфейса:
#   - enp0s3 (NAT, 10.0.2.15) — у всех трёх нод одинаковый!
#   - enp0s8 (host-only, 192.168.56.x) — уникальный для каждой ноды
#
# По умолчанию kubelet выбирает первый найденный IP (10.0.2.15).
# Тогда все три ноды будут говорить мастеру: "я на IP 10.0.2.15" — конфликт!
#
# РЕШЕНИЕ: Указать kubelet явно, какой IP использовать (--node-ip).
# Этот IP должен совпадать с тем, что передан в NODE_IP из Vagrantfile.
#
# ФАЙЛ /etc/default/kubelet — конфигурация systemd-сервиса kubelet.
# После изменения нужно: systemctl daemon-reload && systemctl restart kubelet.
echo ">>> [ШАГ 10] Настройка NODE_IP для kubelet (${NODE_IP})..."
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" | tee /etc/default/kubelet
systemctl daemon-reload
echo "  kubelet получит --node-ip=${NODE_IP} при следующем запуске"

echo ""
echo ">>> [common.sh] Готово! Нода ${HOSTNAME} (IP: ${NODE_IP}) подготовлена."
echo "    Следующий шаг: master.sh (на мастере) или worker.sh (на воркерах)"
