@echo off
rem ============================================================
rem launch.bat — Запуск Kubernetes-кластера (Stage 1)
rem ============================================================
rem
rem ЧТО ДЕЛАЕТ ЭТОТ ФАЙЛ:
rem   1. Проверяет, установлены ли Vagrant и VirtualBox
rem   2. Проверяет, что ты запустил его в нужной папке
rem   3. Запускает vagrant up (создаёт и настраивает 3 ВМ)
rem   4. После успешного запуска показывает статус нод
rem
rem КАК ЗАПУСТИТЬ:
rem   Дважды кликни по launch.bat в папке stage1\
rem   ИЛИ открой PowerShell в папке stage1\ и набери: .\launch.bat
rem
rem СКОЛЬКО ЖДАТЬ:
rem   Первый раз: 15–30 минут (скачивается образ Ubuntu ~1.5 ГБ + K8s)
rem   Повторный:  5–10 минут (образ уже есть)
rem
rem ЕСЛИ УПАЛО С ОШИБКОЙ:
rem   Смотри docs\troubleshooting.md
rem   Или набери: vagrant ssh k8s-master -- journalctl -u kubelet -n 50
rem ============================================================

chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

echo.
echo  ╔══════════════════════════════════════════════════════╗
echo  ║     Kubernetes Cluster Stage 1 — Запуск             ║
echo  ╚══════════════════════════════════════════════════════╝
echo.

rem --- ПРОВЕРКА 1: Vagrant установлен? ---
where vagrant >nul 2>&1
if errorlevel 1 (
    echo  [ОШИБКА] Vagrant не найден!
    echo.
    echo  Скачай и установи Vagrant:
    echo    https://developer.hashicorp.com/vagrant/downloads
    echo.
    echo  После установки ПЕРЕЗАПУСТИ это окно командной строки.
    pause
    exit /b 1
)
echo  [OK] Vagrant найден:
vagrant --version
echo.

rem --- ПРОВЕРКА 2: VirtualBox установлен? ---
where VBoxManage >nul 2>&1
if errorlevel 1 (
    rem Попробуем стандартный путь установки
    if exist "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" (
        set PATH=%PATH%;C:\Program Files\Oracle\VirtualBox
    ) else (
        echo  [ОШИБКА] VirtualBox не найден!
        echo.
        echo  Скачай и установи VirtualBox 7.x:
        echo    https://www.virtualbox.org/wiki/Downloads
        echo.
        pause
        exit /b 1
    )
)
echo  [OK] VirtualBox найден:
VBoxManage --version
echo.

rem --- ПРОВЕРКА 3: Мы в правильной папке? ---
if not exist "Vagrantfile" (
    echo  [ОШИБКА] Vagrantfile не найден в текущей папке!
    echo.
    echo  Убедись, что launch.bat запускается из папки stage1\
    echo  Текущая папка: %CD%
    echo.
    pause
    exit /b 1
)
echo  [OK] Vagrantfile найден в %CD%
echo.

rem --- ЗАПУСК КЛАСТЕРА ---
echo  Запускаем vagrant up...
echo  (Ctrl+C для отмены в любой момент)
echo.
echo ════════════════════════════════════════════════════════
echo.

vagrant up

rem --- ПРОВЕРКА РЕЗУЛЬТАТА ---
if errorlevel 1 (
    echo.
    echo ════════════════════════════════════════════════════════
    echo  [ОШИБКА] vagrant up завершился с ошибкой.
    echo.
    echo  Попробуй:
    echo    1. vagrant status          — проверь состояние ВМ
    echo    2. vagrant destroy -f      — удали все ВМ
    echo    3. .\launch.bat            — запусти снова
    echo.
    echo  Подробная диагностика: docs\troubleshooting.md
    echo ════════════════════════════════════════════════════════
    pause
    exit /b 1
)

echo.
echo ════════════════════════════════════════════════════════
echo  Кластер запущен! Проверяем ноды...
echo ════════════════════════════════════════════════════════
echo.

rem --- СТАТУС НОД ---
vagrant ssh k8s-master --command "kubectl get nodes -o wide"
echo.

rem --- ИТОГ ---
echo ════════════════════════════════════════════════════════
echo.
echo  Кластер готов!
echo.
echo  Полезные команды:
echo    vagrant ssh k8s-master        — войти на мастер
echo    vagrant status                — проверить ВМ
echo    vagrant halt                  — выключить ВМ (сохраняет данные)
echo    vagrant destroy -f            — удалить всё
echo.
echo  Kubernetes Dashboard:
echo    https://localhost:30443
echo    (токен выведен в логах выше — ищи строку "ТОКЕН ДЛЯ ВХОДА")
echo.
echo ════════════════════════════════════════════════════════
echo.
pause
