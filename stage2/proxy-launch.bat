@echo off
rem =============================================================================
rem proxy-launch.bat — Прокси-запускатор кластера (Stage 2)
rem =============================================================================
rem
rem ЧТО ДЕЛАЕТ:
rem   Принимает параметры командной строки (или переменные окружения),
rem   создаёт .env файл и запускает vagrant up.
rem   Это даёт возможность запускать кластер с разными конфигурациями
rem   без редактирования файлов.
rem
rem СИНТАКСИС:
rem   proxy-launch.bat [опции]
rem
rem ОПЦИИ:
rem   --prefix=НАЗВАНИЕ     Префикс имён ВМ (default: lab-k8s)
rem   --workers=N           Количество воркеров 1-4 (default: 2)
rem   --cpus=N              CPU на каждую ВМ 1-8 (default: 2)
rem   --memory=N            RAM в МБ на ВМ (default: 2048)
rem   --subnet=X.X.X        Первые три октета подсети (default: 192.168.56)
rem   --k8s-version=VER     Версия Kubernetes (default: 1.34)
rem   --help                Показать эту справку
rem
rem ПРИМЕРЫ:
rem   proxy-launch.bat
rem   proxy-launch.bat --workers=1 --cpus=2 --memory=2048
rem   proxy-launch.bat --prefix=mylab --workers=3 --cpus=4 --memory=4096
rem   proxy-launch.bat --subnet=10.0.0
rem
rem ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ (альтернатива флагам):
rem   Можно задать переменные до запуска:
rem   set CLUSTER_PREFIX=mylab
rem   set WORKER_COUNT=1
rem   proxy-launch.bat
rem
rem КАК ОСТАНОВИТЬ:
rem   proxy-launch.bat --halt
rem
rem КАК УДАЛИТЬ:
rem   proxy-launch.bat --destroy
rem =============================================================================

chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

rem --- Значения по умолчанию ---
set _PREFIX=lab-k8s
set _WORKERS=2
set _CPUS=2
set _MEMORY=2048
set _SUBNET=192.168.56
set _K8S_VER=1.34
set _ACTION=up

rem Если переменные окружения заданы — используем их как значения по умолчанию
if defined CLUSTER_PREFIX  set _PREFIX=%CLUSTER_PREFIX%
if defined WORKER_COUNT    set _WORKERS=%WORKER_COUNT%
if defined VM_CPUS         set _CPUS=%VM_CPUS%
if defined VM_MEMORY_MB    set _MEMORY=%VM_MEMORY_MB%
if defined PRIVATE_NETWORK_PREFIX set _SUBNET=%PRIVATE_NETWORK_PREFIX%
if defined KUBERNETES_VERSION     set _K8S_VER=%KUBERNETES_VERSION%

rem --- Парсинг аргументов командной строки ---
:parse_args
if "%~1"=="" goto :end_parse

if /i "%~1"=="--help"    goto :show_help
if /i "%~1"=="-h"        goto :show_help
if /i "%~1"=="--halt"    ( set _ACTION=halt && shift && goto :parse_args )
if /i "%~1"=="--destroy" ( set _ACTION=destroy && shift && goto :parse_args )
if /i "%~1"=="--status"  ( set _ACTION=status && shift && goto :parse_args )

rem Парсинг --key=value
for /f "tokens=1,2 delims==" %%a in ("%~1") do (
  set _KEY=%%a
  set _VAL=%%b

  if /i "!_KEY!"=="--prefix"      set _PREFIX=!_VAL!
  if /i "!_KEY!"=="--workers"     set _WORKERS=!_VAL!
  if /i "!_KEY!"=="--cpus"        set _CPUS=!_VAL!
  if /i "!_KEY!"=="--memory"      set _MEMORY=!_VAL!
  if /i "!_KEY!"=="--subnet"      set _SUBNET=!_VAL!
  if /i "!_KEY!"=="--k8s-version" set _K8S_VER=!_VAL!
)
shift
goto :parse_args
:end_parse

rem --- Обработка действий кроме up ---
if "%_ACTION%"=="halt" (
  echo  Останавливаем кластер...
  vagrant halt
  goto :eof
)
if "%_ACTION%"=="destroy" (
  echo  Уничтожаем кластер...
  set /p _CONFIRM=Удалить все ВМ? (y/N):
  if /i "!_CONFIRM!"=="y" (
    vagrant destroy -f
    powershell.exe -Command "Remove-Item -Recurse -Force .vagrant\node-keys -ErrorAction SilentlyContinue"
  )
  goto :eof
)
if "%_ACTION%"=="status" (
  vagrant status
  goto :eof
)

rem --- Проверка зависимостей ---
echo.
echo  Проверка зависимостей...
where vagrant >nul 2>&1 || (
  echo  [ОШИБКА] Vagrant не найден. Установи: https://developer.hashicorp.com/vagrant/downloads
  exit /b 1
)
where VBoxManage >nul 2>&1 || if not exist "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" (
  echo  [ОШИБКА] VirtualBox не найден. Установи: https://www.virtualbox.org/wiki/Downloads
  exit /b 1
)
echo  [OK] Vagrant и VirtualBox найдены.
echo.

rem --- Генерация .env ---
echo  Конфигурация:
echo    Префикс:    %_PREFIX%
echo    Воркеры:    %_WORKERS%
echo    CPU:        %_CPUS%
echo    RAM:        %_MEMORY% MB
echo    Подсеть:    %_SUBNET%.0/24
echo    K8s:        v%_K8S_VER%
echo.

echo  Создаём .env...
(
  echo # Создано proxy-launch.bat %date% %time%
  echo CLUSTER_PREFIX=%_PREFIX%
  echo MASTER_VM_NAME=%_PREFIX%-master
  echo MASTER_HOSTNAME=%_PREFIX%-master
  echo.
  echo VM_BOX=bento/ubuntu-24.04
  echo VM_CPUS=%_CPUS%
  echo VM_MEMORY_MB=%_MEMORY%
  echo VM_BOOT_TIMEOUT=600
  echo WORKER_COUNT=%_WORKERS%
  echo.
  echo PRIVATE_NETWORK_PREFIX=%_SUBNET%
  echo PRIVATE_NETWORK_GATEWAY=%_SUBNET%.1
  echo MASTER_PRIVATE_IP=%_SUBNET%.10
  echo MASTER_SSH_PORT=2232
  echo MASTER_API_PORT=6443
  echo MASTER_DASHBOARD_PORT=30443
  echo.
  echo WORKER1_VM_NAME=%_PREFIX%-worker1
  echo WORKER1_HOSTNAME=%_PREFIX%-worker1
  echo WORKER1_PRIVATE_IP=%_SUBNET%.11
  echo WORKER1_SSH_PORT=2242
  echo.
  echo WORKER2_VM_NAME=%_PREFIX%-worker2
  echo WORKER2_HOSTNAME=%_PREFIX%-worker2
  echo WORKER2_PRIVATE_IP=%_SUBNET%.12
  echo WORKER2_SSH_PORT=2252
  echo.
  echo BRIDGE_ADAPTER=
  echo.
  echo KUBERNETES_VERSION=%_K8S_VER%
  echo POD_CIDR=10.244.0.0/16
) > .env

rem --- Запуск vagrant up ---
echo  Запуск vagrant up (15-30 минут)...
echo ════════════════════════════════════════
vagrant up

if errorlevel 1 (
  echo.
  echo  [ОШИБКА] vagrant up завершился с ошибкой.
  echo  Диагностика: vagrant status
  echo  Подробности: docs\troubleshooting.md
  exit /b 1
)

echo.
echo ════════════════════════════════════════
echo  Кластер запущен!
echo.
vagrant ssh %_PREFIX%-master --command "kubectl get nodes -o wide"
echo.
echo  Dashboard: https://localhost:30443
echo  Токен:     vagrant ssh %_PREFIX%-master -- kubectl -n kubernetes-dashboard create token admin-user
echo ════════════════════════════════════════
echo.
goto :eof

:show_help
echo.
echo  proxy-launch.bat — Прокси-запускатор кластера Stage 2
echo.
echo  Использование:
echo    proxy-launch.bat [опции]
echo.
echo  Опции:
echo    --prefix=NAME     Префикс имён ВМ          (default: lab-k8s^)
echo    --workers=N       Количество воркеров 1-4  (default: 2^)
echo    --cpus=N          CPU на каждую ВМ         (default: 2^)
echo    --memory=MB       RAM в МБ на ВМ           (default: 2048^)
echo    --subnet=X.X.X    Первые три октета        (default: 192.168.56^)
echo    --k8s-version=V   Версия Kubernetes        (default: 1.34^)
echo    --halt            Остановить кластер
echo    --destroy         Удалить кластер
echo    --status          Статус ВМ
echo    --help            Эта справка
echo.
echo  Примеры:
echo    proxy-launch.bat
echo    proxy-launch.bat --workers=1 --memory=2048
echo    proxy-launch.bat --prefix=mylab --workers=3 --cpus=4
echo.
