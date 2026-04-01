; =============================================================================
; russian.nsh — Строки интерфейса на русском языке
; =============================================================================
; Используется: stage2/installer/k8s-lab.nsi
; Язык: Русский (LangId 1049)
; =============================================================================

; --- Общие ---
LangString STR_WELCOME_TITLE     ${LANG_RUSSIAN} "Kubernetes Cluster Lab"
LangString STR_WELCOME_TEXT      ${LANG_RUSSIAN} "Этот мастер установки создаст локальный кластер Kubernetes на твоём компьютере.$\n$\nВ состав кластера войдут:$\n  • 1 управляющая нода (master)$\n  • Несколько рабочих нод (workers)$\n$\nДля работы нужно: VirtualBox 7.x и Vagrant 2.4+.$\n$\nНажми «Далее» чтобы начать."

; --- Проверка зависимостей ---
LangString STR_DEPS_TITLE        ${LANG_RUSSIAN} "Проверка требований"
LangString STR_DEPS_SUBTITLE     ${LANG_RUSSIAN} "Убедимся, что всё необходимое установлено"
LangString STR_DEPS_VAGRANT      ${LANG_RUSSIAN} "Vagrant"
LangString STR_DEPS_VBOX         ${LANG_RUSSIAN} "VirtualBox"
LangString STR_DEPS_OK           ${LANG_RUSSIAN} "✓ найден"
LangString STR_DEPS_MISSING      ${LANG_RUSSIAN} "✗ не найден"
LangString STR_DEPS_WARN_VAGRANT ${LANG_RUSSIAN} "Vagrant не найден!$\n$\nСкачай и установи с сайта:$\nhttps://developer.hashicorp.com/vagrant/downloads$\n$\nПродолжить без Vagrant?"
LangString STR_DEPS_WARN_VBOX    ${LANG_RUSSIAN} "VirtualBox не найден!$\n$\nСкачай и установи с сайта:$\nhttps://www.virtualbox.org/wiki/Downloads$\n$\nПродолжить без VirtualBox?"
LangString STR_DEPS_HINT         ${LANG_RUSSIAN} "Если что-то не найдено — установи недостающее и перезапусти этот мастер."

; --- Папка установки ---
LangString STR_DIR_TITLE         ${LANG_RUSSIAN} "Папка проекта"
LangString STR_DIR_SUBTITLE      ${LANG_RUSSIAN} "Куда распаковать файлы кластера?"
LangString STR_DIR_LABEL         ${LANG_RUSSIAN} "Папка:"
LangString STR_DIR_BROWSE        ${LANG_RUSSIAN} "Обзор..."

; --- Настройка Master-ноды ---
LangString STR_MASTER_TITLE      ${LANG_RUSSIAN} "Настройка Master-ноды"
LangString STR_MASTER_SUBTITLE   ${LANG_RUSSIAN} "Параметры управляющей ноды"
LangString STR_MASTER_PREFIX     ${LANG_RUSSIAN} "Префикс имён ВМ"
LangString STR_MASTER_CPU        ${LANG_RUSSIAN} "Процессоров (CPU)"
LangString STR_MASTER_RAM        ${LANG_RUSSIAN} "Оперативная память (МБ)"
LangString STR_MASTER_HDD        ${LANG_RUSSIAN} "Виртуальный диск (ГБ)"
LangString STR_MASTER_HINT       ${LANG_RUSSIAN} "Master-нода управляет кластером. Рекомендуется 2+ CPU и 2048+ МБ RAM."

; --- Настройка сети ---
LangString STR_NETWORK_TITLE     ${LANG_RUSSIAN} "Настройка сети"
LangString STR_NETWORK_SUBTITLE  ${LANG_RUSSIAN} "Параметры сетевого подключения"
LangString STR_NETWORK_SUBNET    ${LANG_RUSSIAN} "Подсеть (первые 3 октета)"
LangString STR_NETWORK_MASK      ${LANG_RUSSIAN} "Маска подсети"
LangString STR_NETWORK_BRIDGE    ${LANG_RUSSIAN} "Сетевой адаптер (мост)"
LangString STR_NETWORK_ADAPTER   ${LANG_RUSSIAN} "Второй адаптер"
LangString STR_NETWORK_ADAPTER_NONE ${LANG_RUSSIAN} "Нет"
LangString STR_NETWORK_ADAPTER_BRIDGE ${LANG_RUSSIAN} "Мост (Bridged)"
LangString STR_NETWORK_ADAPTER_NAT ${LANG_RUSSIAN} "NAT"
LangString STR_NETWORK_MASTER_PORT ${LANG_RUSSIAN} "SSH-порт Master"
LangString STR_NETWORK_API_PORT  ${LANG_RUSSIAN} "Порт API (kube-apiserver)"
LangString STR_NETWORK_DASH_PORT ${LANG_RUSSIAN} "Порт Dashboard"
LangString STR_NETWORK_HINT      ${LANG_RUSSIAN} "Мост даёт ВМ прямой доступ к физической сети. NAT изолирует ВМ внутри хоста."
LangString STR_NETWORK_PORT_WARN ${LANG_RUSSIAN} "Порт $0 уже занят другим процессом!$\n$\nВыбрать другой порт?"
LangString STR_NETWORK_PORT_CHECK ${LANG_RUSSIAN} "Проверка портов..."
LangString STR_NETWORK_PORT_OK   ${LANG_RUSSIAN} "Все порты свободны"
LangString STR_NETWORK_PORT_BUSY ${LANG_RUSSIAN} "Порт $0 занят"

; --- Настройка Worker-нод ---
LangString STR_WORKER_TITLE      ${LANG_RUSSIAN} "Настройка Worker-нод"
LangString STR_WORKER_SUBTITLE   ${LANG_RUSSIAN} "Параметры рабочих нод"
LangString STR_WORKER_COUNT      ${LANG_RUSSIAN} "Количество рабочих нод"
LangString STR_WORKER_CPU        ${LANG_RUSSIAN} "Процессоров (CPU) на ноду"
LangString STR_WORKER_RAM        ${LANG_RUSSIAN} "Оперативная память (МБ) на ноду"
LangString STR_WORKER_HDD        ${LANG_RUSSIAN} "Виртуальный диск (ГБ) на ноду"
LangString STR_WORKER_HINT       ${LANG_RUSSIAN} "Рабочие ноды запускают контейнеры. Рекомендуется 2+ CPU и 2048+ МБ RAM на ноду."

; --- Сводка ---
LangString STR_SUMMARY_TITLE     ${LANG_RUSSIAN} "Сводка настроек"
LangString STR_SUMMARY_SUBTITLE  ${LANG_RUSSIAN} "Проверь параметры перед запуском"
LangString STR_SUMMARY_HEADER    ${LANG_RUSSIAN} "Будет создан кластер:"
LangString STR_SUMMARY_PREFIX    ${LANG_RUSSIAN} "Префикс ВМ:"
LangString STR_SUMMARY_MASTER    ${LANG_RUSSIAN} "Master:"
LangString STR_SUMMARY_WORKERS   ${LANG_RUSSIAN} "Worker-нод:"
LangString STR_SUMMARY_WORKER    ${LANG_RUSSIAN} "Каждый Worker:"
LangString STR_SUMMARY_NETWORK   ${LANG_RUSSIAN} "Сеть:"
LangString STR_SUMMARY_SUBNET    ${LANG_RUSSIAN} "Подсеть:"
LangString STR_SUMMARY_BRIDGE    ${LANG_RUSSIAN} "Мост:"
LangString STR_SUMMARY_PORTS     ${LANG_RUSSIAN} "Порты:"
LangString STR_SUMMARY_DIR       ${LANG_RUSSIAN} "Папка проекта:"
LangString STR_SUMMARY_NOTE      ${LANG_RUSSIAN} "Установка займёт 15–30 минут (скачивание образа Ubuntu + Kubernetes)."

; --- Установка ---
LangString STR_INSTALL_TITLE     ${LANG_RUSSIAN} "Запуск кластера"
LangString STR_INSTALL_SUBTITLE  ${LANG_RUSSIAN} "Подожди, идёт установка..."
LangString STR_INSTALL_COPY      ${LANG_RUSSIAN} "Копирование файлов проекта..."
LangString STR_INSTALL_CONFIG    ${LANG_RUSSIAN} "Создание .env конфигурации..."
LangString STR_INSTALL_KEYS      ${LANG_RUSSIAN} "Генерация SSH-ключей..."
LangString STR_INSTALL_VAGRANT_INIT ${LANG_RUSSIAN} "Инициализация Vagrant..."
LangString STR_INSTALL_VAGRANT_UP ${LANG_RUSSIAN} "Запуск виртуальных машин (vagrant up)..."
LangString STR_INSTALL_BOOTSTRAP ${LANG_RUSSIAN} "Настройка Kubernetes (bootstrap)..."
LangString STR_INSTALL_NETWORK   ${LANG_RUSSIAN} "Настройка сети (CNI)..."
LangString STR_INSTALL_DASHBOARD ${LANG_RUSSIAN} "Установка Dashboard..."
LangString STR_INSTALL_TOKEN     ${LANG_RUSSIAN} "Генерация токена доступа..."
LangString STR_INSTALL_DONE      ${LANG_RUSSIAN} "Кластер готов!"

; --- Финиш ---
LangString STR_FINISH_TITLE      ${LANG_RUSSIAN} "Установка завершена"
LangString STR_FINISH_SUBTITLE   ${LANG_RUSSIAN} "Кластер Kubernetes успешно запущен"
LangString STR_FINISH_TEXT       ${LANG_RUSSIAN} "Кластер Kubernetes успешно запущен!"
LangString STR_FINISH_DASHBOARD  ${LANG_RUSSIAN} "Dashboard:"
LangString STR_FINISH_DASHBOARD_URL ${LANG_RUSSIAN} "https://localhost:30443"
LangString STR_FINISH_TOKEN      ${LANG_RUSSIAN} "Токен для входа:"
LangString STR_FINISH_TOKEN_FILE ${LANG_RUSSIAN} "dashboard-token.txt"
LangString STR_FINISH_KUBECONFIG ${LANG_RUSSIAN} "kubeconfig:"
LangString STR_FINISH_KUBECONFIG_FILE ${LANG_RUSSIAN} "kubeconfig-stage1.yaml"
LangString STR_FINISH_NODES      ${LANG_RUSSIAN} "Ноды:"
LangString STR_FINISH_OPEN       ${LANG_RUSSIAN} "Открыть папку проекта"
LangString STR_FINISH_DOCS       ${LANG_RUSSIAN} "Открыть документацию"

; --- Ошибки ---
LangString STR_ERR_VAGRANT_FAIL  ${LANG_RUSSIAN} "vagrant up завершился с ошибкой.$\nПроверь логи в папке проекта.$\nДля диагностики: vagrant status"
LangString STR_ERR_NO_ADMIN      ${LANG_RUSSIAN} "Требуются права администратора.$\nЗапусти установщик от имени администратора."
LangString STR_ERR_INVALID_SUBNET ${LANG_RUSSIAN} "Неверный формат подсети.$\nУкажи первые 3 октета, например: 192.168.56"
