; =============================================================================
; russian.nsh — Строки интерфейса на русском языке
; =============================================================================
; Используется: stage2/installer/k8s-lab.nsi
; Язык: Русский (LangId 1049)
;
; Как добавить новую строку:
;   1. Добавь LangString MY_STRING ${LANG_RUSSIAN} "Текст"
;   2. Добавь аналогичную строку в english.nsh с LANG_ENGLISH
;   3. Используй в .nsi: $(MY_STRING)
; =============================================================================

; --- Общие ---
LangString STR_WELCOME_TITLE     ${LANG_RUSSIAN} "Kubernetes Cluster Lab"
LangString STR_WELCOME_TEXT      ${LANG_RUSSIAN} "Этот мастер установки создаст локальный кластер Kubernetes на твоём компьютере.$\n$\nВ состав кластера войдут:$\n  • 1 управляющая нода (master)$\n  • Несколько рабочих нод (workers)$\n$\nДля работы нужно: VirtualBox 7.x и Vagrant 2.4+.$\n$\nНажми «Далее» чтобы начать."

LangString STR_LICENSE_TITLE     ${LANG_RUSSIAN} "Лицензионное соглашение"
LangString STR_LICENSE_TEXT      ${LANG_RUSSIAN} "Этот проект распространяется под лицензией MIT. Использование свободное, в том числе в образовательных целях."

; --- Проверка зависимостей ---
LangString STR_DEPS_TITLE        ${LANG_RUSSIAN} "Проверка требований"
LangString STR_DEPS_SUBTITLE     ${LANG_RUSSIAN} "Убедимся, что всё необходимое установлено"
LangString STR_DEPS_VAGRANT      ${LANG_RUSSIAN} "Vagrant"
LangString STR_DEPS_VBOX         ${LANG_RUSSIAN} "VirtualBox"
LangString STR_DEPS_OK           ${LANG_RUSSIAN} "✓ найден"
LangString STR_DEPS_MISSING      ${LANG_RUSSIAN} "✗ не найден"
LangString STR_DEPS_WARN_VAGRANT ${LANG_RUSSIAN} "Vagrant не найден!$\n$\nСкачай и установи с сайта:$\nhttps://developer.hashicorp.com/vagrant/downloads$\n$\nПосле установки запусти мастер заново."
LangString STR_DEPS_WARN_VBOX    ${LANG_RUSSIAN} "VirtualBox не найден!$\n$\nСкачай и установи с сайта:$\nhttps://www.virtualbox.org/wiki/Downloads$\n$\nПосле установки запусти мастер заново."
LangString STR_DEPS_HINT         ${LANG_RUSSIAN} "Если что-то не найдено — установи недостающее и перезапусти этот мастер."

; --- Конфигурация кластера ---
LangString STR_CONFIG_TITLE      ${LANG_RUSSIAN} "Настройка кластера"
LangString STR_CONFIG_SUBTITLE   ${LANG_RUSSIAN} "Укажи параметры своего кластера (или оставь по умолчанию)"
LangString STR_CONFIG_PREFIX     ${LANG_RUSSIAN} "Префикс имён ВМ (например: mylab-k8s)"
LangString STR_CONFIG_WORKERS    ${LANG_RUSSIAN} "Количество рабочих нод (воркеров)"
LangString STR_CONFIG_CPU        ${LANG_RUSSIAN} "Процессоров на каждую ВМ"
LangString STR_CONFIG_RAM        ${LANG_RUSSIAN} "Оперативная память на каждую ВМ (МБ)"
LangString STR_CONFIG_SUBNET     ${LANG_RUSSIAN} "Подсеть (первые три октета, например: 192.168.56)"
LangString STR_CONFIG_TIP        ${LANG_RUSSIAN} "Совет: оставь значения по умолчанию если не знаешь что менять"

; --- Каталог установки ---
LangString STR_DIR_TITLE         ${LANG_RUSSIAN} "Папка проекта"
LangString STR_DIR_SUBTITLE      ${LANG_RUSSIAN} "Куда распаковать файлы кластера?"
LangString STR_DIR_LABEL         ${LANG_RUSSIAN} "Папка:"
LangString STR_DIR_BROWSE        ${LANG_RUSSIAN} "Обзор..."

; --- Сводка ---
LangString STR_SUMMARY_TITLE     ${LANG_RUSSIAN} "Сводка настроек"
LangString STR_SUMMARY_SUBTITLE  ${LANG_RUSSIAN} "Проверь параметры перед запуском"
LangString STR_SUMMARY_HEADER    ${LANG_RUSSIAN} "Будет создан кластер:"
LangString STR_SUMMARY_PREFIX    ${LANG_RUSSIAN} "Префикс ВМ:"
LangString STR_SUMMARY_WORKERS   ${LANG_RUSSIAN} "Рабочих нод:"
LangString STR_SUMMARY_CPU       ${LANG_RUSSIAN} "CPU на ВМ:"
LangString STR_SUMMARY_RAM       ${LANG_RUSSIAN} "RAM на ВМ:"
LangString STR_SUMMARY_SUBNET    ${LANG_RUSSIAN} "Подсеть:"
LangString STR_SUMMARY_DIR       ${LANG_RUSSIAN} "Папка проекта:"
LangString STR_SUMMARY_NOTE      ${LANG_RUSSIAN} "Установка займёт 15–30 минут (скачивание образа Ubuntu + Kubernetes)."

; --- Установка ---
LangString STR_INSTALL_TITLE     ${LANG_RUSSIAN} "Запуск кластера"
LangString STR_INSTALL_SUBTITLE  ${LANG_RUSSIAN} "Подожди, идёт установка..."
LangString STR_INSTALL_COPY      ${LANG_RUSSIAN} "Копирование файлов..."
LangString STR_INSTALL_CONFIG    ${LANG_RUSSIAN} "Создание .env конфигурации..."
LangString STR_INSTALL_KEYS      ${LANG_RUSSIAN} "Генерация SSH-ключей..."
LangString STR_INSTALL_VAGRANT   ${LANG_RUSSIAN} "Запуск vagrant up (это займёт 15–30 минут)..."
LangString STR_INSTALL_DONE      ${LANG_RUSSIAN} "Кластер готов!"

; --- Завершение ---
LangString STR_FINISH_TITLE      ${LANG_RUSSIAN} "Установка завершена"
LangString STR_FINISH_TEXT       ${LANG_RUSSIAN} "Кластер Kubernetes успешно запущен!$\n$\nДашборд доступен по адресу:$\nhttps://localhost:30443$\n$\nТокен для входа — в файле dashboard-token.txt$\nв папке проекта."
LangString STR_FINISH_OPEN       ${LANG_RUSSIAN} "Открыть папку проекта"
LangString STR_FINISH_DOCS       ${LANG_RUSSIAN} "Открыть документацию"

; --- Ошибки ---
LangString STR_ERR_VAGRANT_FAIL  ${LANG_RUSSIAN} "vagrant up завершился с ошибкой.$\nПроверь логи в папке проекта.$\nДля диагностики: vagrant status"
LangString STR_ERR_NO_ADMIN      ${LANG_RUSSIAN} "Требуются права администратора.$\nЗапусти установщик от имени администратора."
