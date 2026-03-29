@echo off
rem ============================================================================
rem launch.bat - Полный учебный запуск stage1 одной командой
rem ============================================================================
rem
rem ЧТО ДЕЛАЕТ ЭТОТ ФАЙЛ:
rem   1. Проверяет, что Vagrant и VirtualBox установлены
rem   2. Проверяет, что файл запущен из папки stage1
rem   3. Выполняет базовый bootstrap через vagrant up
rem   4. Выполняет post-bootstrap сценарий:
rem      - проверка регистрации 3 нод
rem      - Calico
rem      - smoke-test
rem      - Dashboard
rem   5. В конце показывает, что именно открыть и что именно проверить
rem
rem ЗАЧЕМ ЭТО НУЖНО:
rem   Ученик может запустить весь stage1 одной командой и просто наблюдать,
rem   не вспоминая каждый раз вручную всю последовательность шагов.
rem
rem КАК ЗАПУСКАТЬ:
rem   1. Двойной клик по launch.bat
rem   2. Или из PowerShell:
rem      .\launch.bat
rem
rem ВАЖНО:
rem   launch.bat не заменяет учебные материалы, а упрощает повторяемый запуск.
rem   Логика проекта остаётся той же:
rem   сначала кластер, потом Calico, потом smoke-test, потом Dashboard.
rem ============================================================================

chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

echo.
echo ============================================================
echo   Stage 1: полный запуск учебного Kubernetes-кластера
echo ============================================================
echo.

rem --- Проверка 1: Vagrant установлен? ---
where vagrant >nul 2>&1
if errorlevel 1 (
    echo [ОШИБКА] Vagrant не найден.
    echo Установи Vagrant и повтори запуск:
    echo https://developer.hashicorp.com/vagrant/downloads
    echo.
    pause
    exit /b 1
)

echo [OK] Найден Vagrant:
vagrant --version
echo.

rem --- Проверка 2: VirtualBox установлен? ---
where VBoxManage >nul 2>&1
if errorlevel 1 (
    if exist "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" (
        set PATH=%PATH%;C:\Program Files\Oracle\VirtualBox
    ) else (
        echo [ОШИБКА] VirtualBox не найден.
        echo Установи VirtualBox и повтори запуск:
        echo https://www.virtualbox.org/wiki/Downloads
        echo.
        pause
        exit /b 1
    )
)

echo [OK] Найден VirtualBox:
VBoxManage --version
echo.

rem --- Проверка 3: мы в правильной папке? ---
if not exist "Vagrantfile" (
    echo [ОШИБКА] В текущей папке не найден Vagrantfile.
    echo Текущая папка: %CD%
    echo Запускай launch.bat именно из stage1.
    echo.
    pause
    exit /b 1
)

if not exist "scripts\run-post-bootstrap.ps1" (
    echo [ОШИБКА] Не найден scripts\run-post-bootstrap.ps1
    echo Сценарий stage1 выглядит неполным.
    echo.
    pause
    exit /b 1
)

echo [OK] Найдены Vagrantfile и post-bootstrap сценарий
echo.

rem --- Шаг 1: базовый bootstrap кластера ---
echo ------------------------------------------------------------
echo [ШАГ 1/2] Выполняем vagrant up
echo ------------------------------------------------------------
echo.
echo Это поднимет 3 ВМ и выполнит базовую сборку кластера.
echo Первый запуск может занять 15-30 минут.
echo.

vagrant up
if errorlevel 1 (
    echo.
    echo [ОШИБКА] Команда vagrant up завершилась с ошибкой.
    echo.
    echo Что можно сделать дальше:
    echo   1. vagrant status
    echo   2. vagrant destroy -f
    echo   3. .\launch.bat
    echo.
    echo Подсказки смотри в docs\troubleshooting.md
    echo.
    pause
    exit /b 1
)

echo.
echo ------------------------------------------------------------
echo [ШАГ 2/2] Выполняем post-bootstrap финализацию
echo ------------------------------------------------------------
echo.
echo Сейчас будут:
echo   - проверка 3 нод
echo   - Calico
echo   - smoke-test
echo   - Dashboard
echo.

powershell.exe -ExecutionPolicy Bypass -File ".\scripts\run-post-bootstrap.ps1"
if errorlevel 1 (
    echo.
    echo [ОШИБКА] Post-bootstrap сценарий завершился с ошибкой.
    echo.
    echo Кластер мог подняться частично, поэтому сначала проверь:
    echo   vagrant status
    echo   vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"
    echo.
    echo Подсказки смотри в docs\troubleshooting.md
    echo.
    pause
    exit /b 1
)

echo.
echo ------------------------------------------------------------
echo Финальная краткая проверка
echo ------------------------------------------------------------
echo.
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"
echo.

echo ============================================================
echo   Stage 1 успешно завершен
echo ============================================================
echo.
echo Что делать дальше:
echo   1. Открой в браузере: https://localhost:30443
echo   2. Если браузер предупредит о сертификате - это нормально
echo   3. Возьми токен из вывода выше
echo   4. В Dashboard проверь:
echo      - 3 ноды в разделе Nodes
echo      - namespace smoke-tests
echo      - nginx-smoke и nginx-smoke-check
echo.
echo Полезные команды:
echo   vagrant status
echo   vagrant ssh k8s-master
echo   vagrant destroy -f
echo.
pause
