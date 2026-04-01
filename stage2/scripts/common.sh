#!/usr/bin/env bash
# =============================================================================
# common.sh — Базовая подготовка всех нод кластера (Stage 2)
# =============================================================================
#
# ИСПОЛЬЗУЕТСЯ: root-level Vagrantfile (Stage 2, с .env и SSH-ключами)
# Для учебного Stage 1 (хардкодом) — смотри stage1/scripts/common.sh
#
# ЗАПУСКАЕТСЯ НА: master, worker1, worker2, ... (все ноды)
# ЗАПУСКАЕТСЯ КАК: root (через sudo внутри скрипта)
#
# АРГУМЕНТЫ (передаются из Vagrantfile через args: [...]):
#   $1 HOSTNAME_VALUE  — имя хоста (например, lab-k8s-master)
#   $2 NODE_IP         — IP второго сетевого адаптера (host-only, например 192.168.56.10)
#   $3 HOST_ENTRIES    — запятая-разделённые записи для /etc/hosts
#                        формат: "ip1 host1,ip2 host2,..."
#   $4 K8S_VERSION     — версия Kubernetes (например, 1.34)
#   $5 GATEWAY_IP      — IP шлюза по умолчанию (не используется напрямую,
#                        но передаётся для полноты конфигурации)
#   $6 NODE_NAME       — имя ВМ в Vagrant (например, lab-k8s-master),
#                        используется для поиска SSH-ключа
#
# ЧТО ДЕЛАЕТ (по порядку):
#   1. Устанавливает hostname ноды
#   2. Перезаписывает /etc/hosts с записями всех нод кластера
#   3. Отключает swap (подкачку) — требование Kubernetes
#   4. Загружает модули ядра: overlay, br_netfilter
#   5. Настраивает sysctl-параметры сети
#   6. Устанавливает базовые утилиты (curl, gpg, ca-certificates)
#   7. Устанавливает containerd (среда запуска контейнеров)
#   8. Добавляет репозиторий Kubernetes
#   9. Устанавливает kubeadm, kubelet, kubectl
#   10. Настраивает --node-ip для kubelet
#   11. Добавляет SSH-публичный ключ в authorized_keys
#
# ИДЕМПОТЕНТНОСТЬ: скрипт безопасно запускать несколько раз — повторный
# запуск не сломает уже настроенную систему. Каждый шаг либо проверяет
# текущее состояние, либо перезаписывает конфиг корректно.
#
# ОТЛИЧИЯ ОТ STAGE 1:
#   - Принимает параметры через аргументы, а не env-переменные
#   - Использует sudo вместо прямого запуска от root
#   - Добавлена инъекция SSH-ключа в authorized_keys
#   - Перезаписывает /etc/hosts целиком, а не добавляет строки
#   - Поддерживает динамическое число нод (через HOST_ENTRIES)
#
# ДОКУМЕНТАЦИЯ: kubernetes.io/docs/setup/production-environment/tools/kubeadm/
# =============================================================================

# Строгий режим bash:
#   -e: завершить при любой ошибке
#   -u: ошибка если переменная не определена
#   -o pipefail: ошибка если часть конвейера (pipe) упала
set -euo pipefail

# ---------------------------------------------------------------------------
# Чтение позиционных аргументов
# ---------------------------------------------------------------------------
# ${1:?message} — если аргумент не передан, скрипт завершится с ошибкой
# и выведет сообщение. Это защита от неправильного вызова из Vagrantfile.
HOSTNAME_VALUE="${1:?hostname is required}"
NODE_IP="${2:?node ip is required}"
HOST_ENTRIES="${3:?host entries are required}"
K8S_VERSION="${4:?kubernetes version is required}"
GATEWAY_IP="${5:?gateway ip is required}"
NODE_NAME="${6:?node name is required}"

# Путь к публичному SSH-ключу ноды (генерируется generate-node-key.ps1 на хосте).
# /vagrant/ — общая папка между хостом (Windows) и всеми ВМ.
# Ключ добавляется в authorized_keys, чтобы SSH работал без пароля.
NODE_PUBLIC_KEY="/vagrant/.vagrant/node-keys/${NODE_NAME}.ed25519.pub"

echo ">>> [common.sh] Нода: ${HOSTNAME_VALUE} | IP: ${NODE_IP} | K8s: ${K8S_VERSION}"

# ---------------------------------------------------------------------------
# ШАГ 1: Имя хоста
# ---------------------------------------------------------------------------
# hostnamectl set-hostname — изменяет имя текущей машины.
#
# ЗАЧЕМ:
#   Kubernetes идентифицирует ноды по hostname (kubectl get nodes показывает их).
#   Без уникального hostname ноды будут конфликтовать друг с другом.
#
# ВАЖНО:
#   hostname должен совпадать с именем, которое прописано в /etc/hosts
#   и которое используют другие ноды для обращения к этой машине.
sudo hostnamectl set-hostname "${HOSTNAME_VALUE}"
echo "  hostname установлен: ${HOSTNAME_VALUE}"

# ---------------------------------------------------------------------------
# ШАГ 2: /etc/hosts — таблица локального DNS
# ---------------------------------------------------------------------------
# Все ноды кластера должны «знать» друг о друге по имени.
# Когда worker подключается к мастеру через kubeadm join,
# он использует имя хоста (например, lab-k8s-master), а не IP.
# Без записи в /etc/hosts имя не разрешится — join провалится.
#
# ФОРМАТ ЗАПИСИ: "192.168.56.10 lab-k8s-master"
#   IP-адрес + пробел + имя хоста
#
# ПОЧЕМУ ПЕРЕЗАПИСЫВАЕМ ЦЕЛИКОМ:
#   В Stage 2 количество нод динамическое. Мы не знаем заранее,
#   сколько worker-нод будет. Поэтому формируем /etc/hosts
#   из переданной строки HOST_ENTRIES, а не хардкодим строки.
#
# СТРУКТУРА ФАЙЛА:
#   127.0.0.1 localhost              — стандартная запись для IPv4
#   127.0.1.1 <hostname>             — запись для самой себя (Debian-конвенция)
#   ::1 localhost ip6-localhost      — стандартная запись для IPv6
#   ff02::1 ip6-allnodes             — IPv6 multicast (все узлы)
#   ff02::2 ip6-allrouters           — IPv6 multicast (все маршрутизаторы)
#   <ip1> <host1>                    — записи нод кластера
#   <ip2> <host2>
#   ...
{
  echo "127.0.0.1 localhost"
  echo "127.0.1.1 ${HOSTNAME_VALUE}"
  echo
  echo "::1 localhost ip6-localhost ip6-loopback"
  echo "ff02::1 ip6-allnodes"
  echo "ff02::2 ip6-allrouters"
  echo
  # HOST_ENTRIES приходит в формате "ip1 host1,ip2 host2,..."
  # IFS=',' разбивает строку по запятым в массив.
  IFS=',' read -ra ENTRIES <<< "${HOST_ENTRIES}"
  for entry in "${ENTRIES[@]}"; do
    echo "${entry}"
  done
} | sudo tee /etc/hosts >/dev/null
echo "  /etc/hosts перезаписан"

# ---------------------------------------------------------------------------
# ШАГ 3: Отключение swap (подкачки)
# ---------------------------------------------------------------------------
# ЧТО ТАКОЕ SWAP:
#   Когда оперативная память заканчивается, Linux записывает часть данных
#   на жёсткий диск (swap). Это позволяет системе не падать, но работает
#   в сотни раз медленнее, чем RAM.
#
# ПОЧЕМУ KUBERNETES ТРЕБУЕТ ОТКЛЮЧИТЬ SWAP:
#   Планировщик K8s (kube-scheduler) точно знает, сколько RAM есть на ноде,
#   и распределяет Pod-ы исходя из этого. Если swap включён — реальное
#   потребление памяти непредсказуемо. Pod, который «должен» уместиться
#   в RAM, может начать свопиться и работать крайне медленно.
#
#   Kubelet по умолчанию откажется запускаться при включённом swap.
#   Можно обойти через --fail-swap-on=false, но это НЕ РЕКОМЕНДУЕТСЯ.
#
# ЧТО СЛОМАЕТСЯ ЕСЛИ НЕ СДЕЛАТЬ:
#   kubelet не запустится, нода не войдёт в кластер.
#
# ДВА ДЕЙСТВИЯ:
#   1. swapoff -a — отключить swap прямо сейчас (до перезагрузки)
#   2. Закомментировать swap в /etc/fstab — чтобы не вернулся после reboot
sudo swapoff -a
# sed -i.bak — редактировать файл на месте, создать резервную копию .bak
# /\sswap\s/ — найти строки, содержащие слово "swap" (с пробелами вокруг)
# s/^/#/ — поставить # в начало строки (закомментировать)
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
echo "  swap отключён"

# ---------------------------------------------------------------------------
# ШАГ 4: Модули ядра — overlay + br_netfilter
# ---------------------------------------------------------------------------
# Kubernetes использует специальные возможности ядра Linux.
# Их нужно явно включить.
#
# overlay — файловая система для слоёв контейнеров (OverlayFS).
#   Каждый контейнер имеет «слои»:
#     - Базовый образ (read-only) — например, ubuntu:24.04
#     - Слой изменений (read-write) — то, что контейнер меняет при работе
#   overlay реализует это прозрачно: контейнер видит единую файловую систему.
#   Без overlay контейнеры не смогут запускаться.
#
# br_netfilter — мост + netfilter (iptables).
#   Позволяет iptables фильтровать трафик, проходящий через виртуальные
#   сетевые мосты. Kubernetes использует мосты для Pod-сети.
#   Без br_netfilter Service-ы не будут маршрутизировать трафик между Pod-ами.
#
# ДВА ФАЙЛА:
#   /etc/modules-load.d/k8s.conf — список модулей для автозагрузки при старте
#   modprobe — загрузить модуль прямо сейчас (без перезагрузки)
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
echo "  модули overlay и br_netfilter загружены"

# ---------------------------------------------------------------------------
# ШАГ 5: sysctl — параметры сети ядра
# ---------------------------------------------------------------------------
# sysctl — механизм настройки параметров работающего ядра Linux.
# Параметры хранятся в /proc/sys/ и применяются через файлы в /etc/sysctl.d/
#
# net.bridge.bridge-nf-call-iptables = 1
#   Заставить iptables обрабатывать трафик, проходящий через сетевые мосты.
#   Без этого: Pod A не может достучаться до Service B через kube-proxy.
#   Kubernetes Service-ы используют iptables для маршрутизации трафика.
#
# net.bridge.bridge-nf-call-ip6tables = 1
#   То же для IPv6 (для совместимости, даже если не используем IPv6).
#
# net.ipv4.ip_forward = 1
#   Разрешить ядру перенаправлять IP-пакеты между сетевыми интерфейсами.
#   Без этого: пакеты из Pod-сети (10.244.x.x) не дойдут до внешней сети.
#   По умолчанию в Linux эта функция выключена (Linux — не маршрутизатор).
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
# sysctl --system — применить все файлы из /etc/sysctl.d/ прямо сейчас.
# > /dev/null — подавить вывод (нам не нужно видеть каждый параметр).
sudo sysctl --system > /dev/null
echo "  параметры ядра (sysctl) применены"

# ---------------------------------------------------------------------------
# ШАГ 6: Базовые утилиты
# ---------------------------------------------------------------------------
# DEBIAN_FRONTEND=noninteractive — отключает интерактивные вопросы apt
# (например, «перезапустить сервисы автоматически?»).
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq

# curl      — скачивать файлы (GPG-ключи, манифесты из интернета)
# gpg       — проверять цифровые подписи репозиториев
# apt-transport-https — разрешает apt работать по HTTPS (безопасность)
# ca-certificates — корневые SSL-сертификаты для проверки HTTPS-соединений
sudo apt-get install -y -qq apt-transport-https ca-certificates curl gpg
echo "  базовые утилиты установлены"

# ---------------------------------------------------------------------------
# ШАГ 7: containerd — среда запуска контейнеров
# ---------------------------------------------------------------------------
# ЧТО ТАКОЕ CONTAINERD:
#   Это программа, которая реально скачивает образы и запускает контейнеры.
#   Kubernetes не работает с контейнерами напрямую — он делегирует это
#   containerd через CRI (Container Runtime Interface).
#
#   Цепочка: kubectl → API Server → kubelet → CRI → containerd → контейнер
#
# ПОЧЕМУ НЕ DOCKER:
#   Docker = containerd + утилиты для разработчика (docker build, docker run...).
#   Kubernetes нужен только containerd. Docker как среда запуска устарел
#   с K8s 1.24 (Dockershim удалён).
#
# ОТКУДА БЕРЁМ:
#   Из стандартного репозитория Ubuntu 24.04.
#   Это надёжнее, чем Docker Hub: обновления синхронизированы с Ubuntu LTS.
#   Не нужно добавлять сторонний репозиторий.
sudo apt-get install -y -qq containerd

# ---------------------------------------------------------------------------
# ШАГ 8: Конфигурация containerd
# ---------------------------------------------------------------------------
# containerd работает с конфигурационным файлом /etc/containerd/config.toml.
# Формат TOML (Tom's Obvious Minimal Language) — простой язык конфигурации.
#
# ПРОБЛЕМА:
#   По умолчанию containerd использует cgroupfs для управления ресурсами
#   контейнеров (CPU, RAM). Но Ubuntu 24.04 (и большинство современных
#   дистрибутивов) используют systemd как систему инициализации, и systemd
#   сам управляет cgroups.
#
#   Если и containerd, и systemd пытаются управлять cgroups по-разному —
#   возникает конфликт. kubelet не может корректно управлять ресурсами Pod-ов.
#   Результат: ноды остаются в состоянии NotReady.
#
# РЕШЕНИЕ:
#   Включить SystemdCgroup = true.
#   Тогда containerd передаёт управление cgroups системному systemd.
#   Это рекомендовано для всех систем с systemd.
#
# ДОКУМЕНТАЦИЯ:
#   https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
sudo mkdir -p /etc/containerd

# containerd config default — генерирует полный конфиг с параметрами по умолчанию.
# tee записывает в файл и дублирует вывод в консоль.
# >/dev/null — подавляем вывод (конфиг огромный, ~200 строк, нам не нужен в консоли).
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# Меняем SystemdCgroup = false → SystemdCgroup = true.
# sed -i — редактировать файл на месте.
# Ищем точную строку с "SystemdCgroup = false" и заменяем.
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Проверяем, что замена сработала.
# Это защита от «тихой» ошибки: если строка не найдена, sed молча ничего не делает.
# Без проверки containerd запустится с неправильным конфигом, и ноды будут NotReady.
if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
  echo "[ОШИБКА] SystemdCgroup не изменён в containerd/config.toml" >&2
  echo "[ОШИБКА] Ноды останутся в состоянии NotReady!" >&2
  exit 1
fi

# Перезапускаем containerd, чтобы новый конфиг применился.
# enable — добавить в автозагрузку (чтобы containerd стартовал при boot ВМ).
sudo systemctl enable containerd
sudo systemctl restart containerd
echo "  containerd настроен (SystemdCgroup = true) и запущен"

# ---------------------------------------------------------------------------
# ШАГ 9: Репозиторий Kubernetes
# ---------------------------------------------------------------------------
# Kubernetes не входит в стандартный репозиторий Ubuntu.
# Его нужно добавить вручную из официального источника.
#
# GPG-ключ — цифровая подпись. apt проверяет, что скачанные пакеты
# действительно подписаны разработчиками Kubernetes (защита от подмены).
#
# Репозиторий: pkgs.k8s.io — официальный репозиторий Kubernetes.
# Разделён по версиям: v1.34, v1.33, и т.д.
sudo mkdir -p /etc/apt/keyrings

# Скачиваем GPG-ключ и конвертируем в бинарный формат.
# curl -fsSL:
#   -f: не показывать HTTP-ошибки (fail silently)
#   -s: тихий режим (без прогресс-бара)
#   -S: показывать ошибки даже в тихом режиме
#   -L: следовать за редиректами
#
# gpg --dearmor: конвертирует ASCII-armored PGP-ключ в бинарный формат.
# --yes: разрешает перезаписать уже существующий keyring без интерактивного вопроса.
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Добавляем строку репозитория в sources.list.d/.
# signed-by= указывает, какой GPG-ключ использовать для проверки пакетов.
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

sudo apt-get update -qq
echo "  репозиторий Kubernetes v${K8S_VERSION} добавлен"

# ---------------------------------------------------------------------------
# ШАГ 10: Установка kubeadm, kubelet, kubectl
# ---------------------------------------------------------------------------
# kubeadm  — инструмент для инициализации и управления кластером.
#            Используем для: kubeadm init (master), kubeadm join (workers).
#
# kubelet  — агент Kubernetes, работает на каждой ноде.
#            Отвечает за: запуск Pod-ов, мониторинг их здоровья,
#            выполнение команд control plane.
#            kubelet — это ЕДИНСТВЕННЫЙ компонент K8s, который должен
#            работать на КАЖДОЙ ноде (и master, и worker).
#
# kubectl  — CLI-утилита для управления кластером (для пользователя).
#            Примеры: kubectl get pods, kubectl apply -f ..., kubectl logs ...
#            На worker-нодах kubectl обычно не используется, но устанавливается
#            для удобства отладки.
sudo apt-get install -y -qq kubelet kubeadm kubectl

# apt-mark hold — «заморозить» версию пакета.
# Запрещает apt автоматически обновлять эти пакеты.
# ЗАЧЕМ: Случайное обновление K8s может сломать работающий кластер.
# Обновление K8s — отдельный плановый процесс (kubeadm upgrade).
sudo apt-mark hold kubelet kubeadm kubectl
echo "  kubeadm, kubelet, kubectl установлены и заморожены"

# ---------------------------------------------------------------------------
# ШАГ 11: NODE_IP для kubelet
# ---------------------------------------------------------------------------
# ПРОБЛЕМА:
#   У каждой ВМ два сетевых интерфейса:
#     - enp0s3 (NAT, 10.0.2.15) — у всех трёх нод ОДИНАКОВЫЙ!
#     - enp0s8 (host-only, 192.168.56.x) — уникальный для каждой ноды
#
#   По умолчанию kubelet выбирает первый найденный IP (10.0.2.15).
#   Тогда все три ноды будут говорить мастеру: "я на IP 10.0.2.15" —
#   конфликт! Мастер не сможет различить ноды.
#
# РЕШЕНИЕ:
#   Указать kubelet явно, какой IP использовать (--node-ip).
#   Этот IP должен совпадать с host-only адресом ноды.
#
# ФАЙЛ /etc/default/kubelet — конфигурация systemd-сервиса kubelet.
# KUBELET_EXTRA_ARGS — переменная, которую systemd добавляет к команде запуска.
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}
EOF
# enable — убедиться, что kubelet запустится при загрузке ВМ.
# restart не нужен здесь — kubelet ещё не запущен (он стартует после reboot
# или при первом kubeadm init/join).
sudo systemctl enable kubelet
echo "  kubelet настроен на --node-ip=${NODE_IP}"

# ---------------------------------------------------------------------------
# ШАГ 12: SSH-ключ ноды (только Stage 2)
# ---------------------------------------------------------------------------
# В Stage 2 вместо пароля vagrant/vagrant используются SSH-ключи.
# Это безопаснее и ближе к production-практике.
#
# Публичный ключ генерируется на Windows через generate-node-key.ps1
# ДО запуска ВМ. Он лежит в /vagrant/.vagrant/node-keys/<NODE_NAME>.ed25519.pub.
#
# Добавляем его в authorized_keys пользователя vagrant:
#   - install -d -m 700 — создать .ssh с правами 700 (только владелец)
#   - touch — создать authorized_keys, если не существует
#   - grep -qxF — проверить, нет ли уже такого ключа (идемпотентность)
#   - chmod 600 — права на authorized_keys (только владелец читает)
#   - chown -R vagrant:vagrant — владелец — пользователь vagrant
if [ -f "${NODE_PUBLIC_KEY}" ]; then
  install -d -m 700 /home/vagrant/.ssh
  touch /home/vagrant/.ssh/authorized_keys
  # grep -qxF:
  #   -q: тихий режим (не выводить совпадения)
  #   -x: точное совпадение всей строки
  #   -F: фиксированная строка (не regex)
  # Если ключ уже есть — не добавляем дубликат.
  grep -qxF "$(cat "${NODE_PUBLIC_KEY}")" /home/vagrant/.ssh/authorized_keys \
    || cat "${NODE_PUBLIC_KEY}" >> /home/vagrant/.ssh/authorized_keys
  chmod 600 /home/vagrant/.ssh/authorized_keys
  chown -R vagrant:vagrant /home/vagrant/.ssh
  echo "  SSH-ключ для ${NODE_NAME} добавлен в authorized_keys"
else
  echo "  SSH-ключ не найден (${NODE_PUBLIC_KEY}), пропускаем"
fi

echo ""
echo ">>> [common.sh] Нода ${HOSTNAME_VALUE} (IP: ${NODE_IP}) готова."
echo "    Следующий шаг: master.sh (на мастере) или worker.sh (на воркерах)"
