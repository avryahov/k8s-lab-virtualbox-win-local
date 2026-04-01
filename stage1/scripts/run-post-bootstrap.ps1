param(
    [int]$ExpectedNodeCount = 3,
    [int]$NodeCountRetries = 30,
    [int]$NodeCountIntervalSeconds = 10,
    [int]$NodeReadyRetries = 36,
    [int]$NodeReadyIntervalSeconds = 10,
    [int]$SmokeWaitRetries = 30,
    [int]$SmokeWaitIntervalSeconds = 10
)

# =============================================================================
# run-post-bootstrap.ps1 — host-side финализация stage1
# =============================================================================
#
# ЧТО ЭТО:
#   PowerShell-скрипт, который запускается на Windows-хосте уже после того,
#   как Vagrant поднял master и worker-ноды (после vagrant up).
#
# ЗАЧЕМ ОТДЕЛЬНЫЙ СКРИПТ:
#   vagrant up создаёт ВМ и запускает provisioning (common.sh, master.sh,
#   worker.sh). Но после этого кластер ещё не полностью готов:
#     - Ноды могут ещё не зарегистрироваться в API
#     - Calico может ещё не развернуться
#     - Smoke-тест не запущен
#     - Dashboard не установлен
#     - kubeconfig не экспортирован на хост
#
#   Этот скрипт завершает настройку и подтверждает, что кластер работает.
#
# ЛОГИКА СЦЕНАРИЯ (7 фаз):
#   Фаза 0: Проверка — кластер уже готов? (идемпотентность)
#   Фаза 1: Проверить, что в кластере зарегистрированы все ноды
#   Фаза 2: На master выполнить сетевую финализацию (Calico)
#   Фаза 3: Применить smoke-тест из корня проекта
#   Фаза 4: Убедиться, что smoke-тест реально прошёл
#   Фаза 5: Вывести сводку smoke-namespace
#   Фаза 6: Установить Dashboard и сгенерировать токен
#   Фаза 7: Экспортировать kubeconfig для Windows-хоста
#
# ИДЕМПОТЕНТНОСТЬ:
#   Перед выполнением каждой фазы проверяется, не выполнена ли она уже.
#   Если кластер полностью готов — скрипт показывает токен и выходит.
#   Это позволяет безопасно запускать скрипт повторно без лишних операций.
#
# ПОЧЕМУ ИМЕННО ТАКОЙ ПОРЯДОК:
#   Сначала нужно доказать, что кластер способен исполнять обычную нагрузку
#   (smoke-тест), и лишь потом добавлять веб-интерфейс как последнее удобство.
#   Это учит правильному подходу: инфраструктура → приложение → UI.
#
# КАК ЗАПУСТИТЬ:
#   powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
#
#   Или через launch.bat (который запускает vagrant up, а потом этот скрипт).
#
# КОНФИГУРИРУЕМЫЕ ПАРАМЕТРЫ:
#   ExpectedNodeCount           — сколько нод ожидаем (по умолчанию 3)
#   NodeCountRetries            — retries для проверки регистрации
#   NodeCountIntervalSeconds    — пауза между проверками регистрации
#   NodeReadyRetries            — retries для проверки Ready
#   NodeReadyIntervalSeconds    — пауза между проверками Ready
#   SmokeWaitRetries            — retries для ожидания smoke-теста
#   SmokeWaitIntervalSeconds    — пауза между проверками smoke-теста
# =============================================================================

# Stop — любая ошибка прерывает выполнение скрипта.
# Это важно: если одна фаза провалилась, нет смысла продолжать.
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Определение путей
# ---------------------------------------------------------------------------
# $PSScriptRoot — директория, в которой лежит этот скрипт (stage1/scripts/).
# Split-Path -Parent — подняться на уровень вверх.
$stage1Dir = Split-Path -Parent $PSScriptRoot           # stage1/
$repoRoot = Split-Path -Parent $stage1Dir                # корень проекта (crm/)
$smokeManifest = Join-Path $repoRoot "smoke-tests\nginx-smoke.yaml"
$hostKubeconfigScript = Join-Path $PSScriptRoot "export-host-kubeconfig.ps1"
$hostKubeconfigPath = Join-Path $stage1Dir "kubeconfig-stage1.yaml"
$hostKubectlHelper = Join-Path $PSScriptRoot "use-stage1-kubectl.ps1"
$hostDashboardTokenPath = Join-Path $stage1Dir "dashboard-token.txt"

# ---------------------------------------------------------------------------
# Проверка наличия необходимых файлов
# ---------------------------------------------------------------------------
if (-not (Test-Path $smokeManifest)) {
    throw "Smoke manifest not found: $smokeManifest"
}

if (-not (Test-Path $hostKubeconfigScript)) {
    throw "Host kubeconfig export script not found: $hostKubeconfigScript"
}

if (-not (Test-Path $hostKubectlHelper)) {
    throw "Host kubectl helper script not found: $hostKubectlHelper"
}

# Переходим в директорию stage1 — это нужно для корректной работы
# vagrant-команд (Vagrant ищет Vagrantfile в текущей директории).
Push-Location $stage1Dir

# ---------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ---------------------------------------------------------------------------

function Invoke-VagrantCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    & vagrant ssh k8s-master -c $Command 2>$null
}

function Invoke-MasterKubectl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$KubectlCommand
    )

    Invoke-VagrantCapture "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl $KubectlCommand"
}

# Show-DashboardToken — показать токен Dashboard из сохранённого файла.
#
# ЗАЧЕМ:
#   install-dashboard.sh сохраняет токен в /vagrant/dashboard-token.txt,
#   который синхронизируется как stage1/dashboard-token.txt на хосте.
#   Эта функция читает файл и выводит токен в красивом формате.
#
# Если файл не найден — пытается сгенерировать токен напрямую.
function Show-DashboardToken {
    Write-Host ""
    Write-Host "========================================================"
    Write-Host "  DASHBOARD ACCESS"
    Write-Host "========================================================"
    Write-Host ""
    Write-Host "  URL: https://localhost:30443"
    Write-Host ""

    if (Test-Path $hostDashboardTokenPath) {
        $token = Get-Content -Path $hostDashboardTokenPath -Raw
        if ($token -and $token.Trim()) {
            Write-Host "  Токен (из dashboard-token.txt):"
            Write-Host "  $token"
            return
        }
    }

    # Файл не найден или пустой — генерируем токен напрямую.
    Write-Host "  Генерация нового токена..."
    $tokenOutput = Invoke-VagrantCapture "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
    if ($tokenOutput -and $tokenOutput.Trim()) {
        Write-Host "  Токен:"
        Write-Host "  $tokenOutput"
        # Сохраняем для будущих запусков.
        $tokenOutput.Trim() | Set-Content -Path $hostDashboardTokenPath -Encoding ascii
    }
    else {
        Write-Host "  Не удалось получить токен. Запусти вручную:"
        Write-Host '  vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kubernetes-dashboard create token admin-user --duration=24h"'
    }

    Write-Host ""
    Write-Host "  Инструкция:"
    Write-Host "  1. Открой https://localhost:30443 в браузере"
    Write-Host "  2. Подтверди переход через предупреждение о самоподписанном сертификате"
    Write-Host "  3. Выбери 'Token' и вставь токен выше"
    Write-Host "  4. Нажми 'Sign in'"
    Write-Host ""
    Write-Host "  Токен также доступен в файле: stage1\dashboard-token.txt"
    Write-Host "========================================================"
}

# =============================================================================
# ФАЗА 0: Проверка — кластер уже готов? (идемпотентность)
# =============================================================================
# Перед выполнением любых операций проверяем, не находится ли кластер
# уже в полностью готовом состоянии. Это позволяет:
#   1. Пропустить все фазы при повторном запуске
#   2. Показать токен Dashboard без ожидания
#   3. Избежать ненужной нагрузки на систему
#
# КРИТЕРИИ ГОТОВНОСТИ:
#   - Все ноды в Ready
#   - Smoke-тест прошёл (Job nginx-smoke-check Complete)
#   - Dashboard установлен (namespace kubernetes-dashboard существует)
Write-Host ">>> [post-bootstrap] Фаза 0/7: Проверка текущего состояния кластера..."

$clusterAlreadyReady = $false
try {
    $nodesOutput = Invoke-MasterKubectl "get nodes --no-headers"
    $nodeLines = @($nodesOutput | Where-Object { $_.Trim() -ne "" })
    $readyNodes = @($nodeLines | Where-Object { $_ -match "\sReady\s" }).Count

    $smokeJobOutput = Invoke-MasterKubectl "get job nginx-smoke-check -n smoke-tests -o jsonpath='{.status.succeeded}' 2>/dev/null"
    $smokePassed = ($smokeJobOutput -eq "1")

    $dashboardNsOutput = Invoke-MasterKubectl "get namespace kubernetes-dashboard 2>/dev/null"
    $dashboardInstalled = ($LASTEXITCODE -eq 0 -and $dashboardNsOutput -and $dashboardNsOutput.Trim() -ne "")

    if ($readyNodes -eq $ExpectedNodeCount -and $smokePassed -and $dashboardInstalled) {
        Write-Host "  Кластер уже полностью готов!"
        Write-Host "    Ноды Ready: $readyNodes/$ExpectedNodeCount"
        Write-Host "    Smoke-тест: пройден"
        Write-Host "    Dashboard: установлен"
        Write-Host ""
        Write-Host "  Пропускаем все фазы — показываю только токен Dashboard."
        $clusterAlreadyReady = $true
    }
    else {
        Write-Host "  Кластер не полностью готов:"
        Write-Host ("    Ноды Ready: {0}/{1}" -f $readyNodes, $ExpectedNodeCount)
        Write-Host "    Smoke-тест: $(if ($smokePassed) { 'пройден' } else { 'не пройден' })"
        Write-Host "    Dashboard: $(if ($dashboardInstalled) { 'установлен' } else { 'не установлен' })"
    }
}
catch {
    Write-Host "  Не удалось проверить состояние кластера — выполняю полный цикл."
}

if ($clusterAlreadyReady) {
    Show-DashboardToken
    Pop-Location
    exit 0
}

# =============================================================================
# ФАЗА 1: Проверка регистрации нод в кластере
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 1/7: Проверка регистрации нод..."

for ($attempt = 1; $attempt -le $NodeCountRetries; $attempt++) {
    $nodesOutput = Invoke-MasterKubectl "get nodes --no-headers"
    $nodeLines = @($nodesOutput | Where-Object { $_.Trim() -ne "" })
    $totalCount = $nodeLines.Count

    if ($totalCount -eq $ExpectedNodeCount) {
        Write-Host "  Cluster API уже видит все $ExpectedNodeCount ноды."
        break
    }

    if ($attempt -eq $NodeCountRetries) {
        Write-Host $nodesOutput
        throw "Stage1 nodes did not all register in the cluster in time."
    }

    Write-Host ("  Найдено {0}/{1} нод. Ждём {2}с (попытка {3}/{4})..." -f $totalCount, $ExpectedNodeCount, $NodeCountIntervalSeconds, $attempt, $NodeCountRetries)
    Start-Sleep -Seconds $NodeCountIntervalSeconds
}

# =============================================================================
# ФАЗА 2: Финализация сетевой настройки (Calico)
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 2/7: Финализация сети (Calico)..."
& vagrant ssh k8s-master -c "sudo EXPECTED_NODE_COUNT=$ExpectedNodeCount NODE_COUNT_RETRIES=$NodeCountRetries NODE_COUNT_INTERVAL=$NodeCountIntervalSeconds NODE_READY_RETRIES=$NodeReadyRetries NODE_READY_INTERVAL=$NodeReadyIntervalSeconds bash /vagrant/scripts/finalize-cluster.sh"

# =============================================================================
# ФАЗА 3: Применение smoke-теста
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 3/7: Применение smoke-манифеста..."
Get-Content -Raw $smokeManifest | & vagrant ssh k8s-master -c "cat > /tmp/nginx-smoke.yaml; sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/nginx-smoke.yaml"

# =============================================================================
# ФАЗА 4: Ожидание rollout smoke-Deployment
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 4/7: Ожидание rollout nginx-smoke..."
& vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/nginx-smoke -n smoke-tests --timeout=300s"

# =============================================================================
# ФАЗА 5: Ожидание успешного завершения smoke-Job
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 5/7: Ожидание smoke-Job..."
for ($attempt = 1; $attempt -le $SmokeWaitRetries; $attempt++) {
    $jobOutput = Invoke-MasterKubectl "get job nginx-smoke-check -n smoke-tests -o jsonpath='{.status.succeeded}'"
    if ($jobOutput -eq "1") {
        Write-Host "  Smoke-Job успешно завершён."
        break
    }

    if ($attempt -eq $SmokeWaitRetries) {
        & vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n smoke-tests -o wide"
        & vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs job/nginx-smoke-check -n smoke-tests"
        throw "Smoke-Job не завершился успешно за отведённое время."
    }

    Write-Host ("  Smoke-Job выполняется. Ждём {0}с (попытка {1}/{2})..." -f $SmokeWaitIntervalSeconds, $attempt, $SmokeWaitRetries)
    Start-Sleep -Seconds $SmokeWaitIntervalSeconds
}

# =============================================================================
# ФАЗА 5b: Сводка smoke-namespace
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 5b/7: Сводка smoke-namespace..."
& vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get all -n smoke-tests -o wide"

# =============================================================================
# ФАЗА 6: Установка Dashboard
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 6/7: Установка Dashboard..."
& vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/install-dashboard.sh"

# =============================================================================
# ФАЗА 7: Экспорт kubeconfig для Windows-хоста
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 7/7: Экспорт kubeconfig для Windows..."
& powershell.exe -ExecutionPolicy Bypass -File $hostKubeconfigScript -OutputPath $hostKubeconfigPath

# =============================================================================
# ФАЗА 8: Создание маркера готовности кластера
# =============================================================================
# Записываем файл-маркер, который сигнализирует, что post-bootstrap
# успешно выполнен. Это позволяет:
#   1. launch.bat быстро определить, что кластер готов
#   2. Пропустить полный цикл при повторном запуске
#   3. Отличить «первый запуск» от «повторный запуск»
$readyMarkerPath = Join-Path $stage1Dir ".vagrant\stage1-ready"
$readyTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
New-Item -Path $readyMarkerPath -ItemType File -Force | Out-Null
Set-Content -Path $readyMarkerPath -Value "ready=$readyTimestamp" -Encoding ascii
Write-Host ">>> [post-bootstrap] Маркер готовности создан: $readyMarkerPath"

# =============================================================================
# ФИНАЛЬНЫЕ ПОДСКАЗКИ
# =============================================================================
Write-Host ""
Write-Host "========================================================"
Write-Host "  STAGE 1 ГОТОВ!"
Write-Host "========================================================"
Write-Host ""

# Показываем токен из сохранённого файла.
# install-dashboard.sh записал его в /vagrant/dashboard-token.txt,
# который синхронизирован как stage1/dashboard-token.txt.
Show-DashboardToken

Write-Host ""
Write-Host "  kubectl из Windows PowerShell:"
Write-Host ('    $env:KUBECONFIG = "{0}"' -f $hostKubeconfigPath)
Write-Host ""
Write-Host "  Или используй helper в текущей сессии:"
Write-Host "    . .\scripts\use-stage1-kubectl.ps1"
Write-Host ""
Write-Host "  Проверка:"
Write-Host "    kubectl get nodes -o wide"
Write-Host "    kubectl get pods -A -o wide"
Write-Host "========================================================"

Pop-Location
