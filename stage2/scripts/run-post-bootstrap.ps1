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
# run-post-bootstrap.ps1 — Host-side финализация Stage 2
# =============================================================================
#
# Этот PowerShell-скрипт запускается на Windows-хосте уже после того,
# как Vagrant поднял master и worker-ноды.
#
# ЛОГИКА СЦЕНАРИЯ (8 фаз):
#   Фаза 0: Проверка — кластер уже готов? (идемпотентность)
#   Фаза 1: Проверить, что в кластере зарегистрированы все ноды
#   Фаза 2: На master выполнить сетевую финализацию (Calico)
#   Фаза 3: Применить простой smoke-тест из корня проекта
#   Фаза 4: Убедиться, что smoke-тест реально прошёл
#   Фаза 5: Вывести сводку smoke-namespace
#   Фаза 6: Установить Dashboard и сгенерировать токен
#   Фаза 7: Экспортировать kubeconfig для Windows-хоста
#
# ИДЕМПОТЕНТНОСТЬ:
#   Перед выполнением проверяется, не находится ли кластер уже в готовом состоянии.
#   Если все ноды Ready, smoke-тест пройден, Dashboard установлен —
#   скрипт показывает токен и выходит мгновенно.
#
# ОТЛИЧИЯ ОТ STAGE 1:
#   - Использует переменные из .env (CLUSTER_PREFIX, MASTER_VM_NAME, etc.)
#   - Поддерживает динамическое количество worker-нод
#   - Экспортирует kubeconfig в stage2/kubeconfig-stage2.yaml
# =============================================================================

$ErrorActionPreference = "Stop"
$stage2Dir = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $stage2Dir
$smokeManifest = Join-Path $repoRoot "smoke-tests\nginx-smoke.yaml"
$hostKubeconfigScript = Join-Path $PSScriptRoot "export-host-kubeconfig.ps1"
$hostKubeconfigPath = Join-Path $stage2Dir "kubeconfig-stage2.yaml"
$hostKubectlHelper = Join-Path $PSScriptRoot "use-stage2-kubectl.ps1"
$hostDashboardTokenPath = Join-Path $stage2Dir "dashboard-token.txt"

# Загружаем .env файл для получения имён ВМ
$envFile = Join-Path $stage2Dir ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)\s*$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"').Trim("'")
            Set-Variable -Name $key -Value $value -Scope Script
        }
    }
}

# Устанавливаем значения по умолчанию, если не заданы в .env
if (-not $CLUSTER_PREFIX) { $CLUSTER_PREFIX = "lab-k8s" }
if (-not $MASTER_VM_NAME) { $MASTER_VM_NAME = "${CLUSTER_PREFIX}-master" }
if (-not $WORKER_COUNT) { $WORKER_COUNT = "2" }
if (-not $MASTER_DASHBOARD_PORT) { $MASTER_DASHBOARD_PORT = "30443" }
$ExpectedNodeCount = 1 + [int]$WORKER_COUNT

if (-not (Test-Path $smokeManifest)) {
    throw "Smoke manifest not found: $smokeManifest"
}

if (-not (Test-Path $hostKubeconfigScript)) {
    throw "Host kubeconfig export script not found: $hostKubeconfigScript"
}

if (-not (Test-Path $hostKubectlHelper)) {
    throw "Host kubectl helper script not found: $hostKubectlHelper"
}

Push-Location $stage2Dir

function Invoke-VagrantCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    & vagrant ssh $MASTER_VM_NAME -c $Command 2>$null
}

function Invoke-MasterKubectl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$KubectlCommand
    )

    Invoke-VagrantCapture "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl $KubectlCommand"
}

function Show-DashboardToken {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  DASHBOARD ACCESS" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "  URL: https://localhost:$MASTER_DASHBOARD_PORT" -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $hostDashboardTokenPath) {
        $token = Get-Content -Path $hostDashboardTokenPath -Raw
        if ($token -and $token.Trim()) {
            Write-Host "  Токен (из dashboard-token.txt):"
            Write-Host "  $token" -ForegroundColor Yellow
            return
        }
    }

    Write-Host "  Генерация нового токена..."
    $tokenOutput = Invoke-VagrantCapture "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
    if ($tokenOutput -and $tokenOutput.Trim()) {
        Write-Host "  Токен:"
        Write-Host "  $tokenOutput" -ForegroundColor Yellow
        $tokenOutput.Trim() | Set-Content -Path $hostDashboardTokenPath -Encoding ascii
    }
    else {
        Write-Host "  Не удалось получить токен. Запусти вручную:" -ForegroundColor Red
        Write-Host "  vagrant ssh $MASTER_VM_NAME -c `"sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kubernetes-dashboard create token admin-user --duration=24h`""
    }

    Write-Host ""
    Write-Host "  Токен также доступен в файле: stage2\dashboard-token.txt"
    Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
}

# =============================================================================
# ФАЗА 0: Проверка — кластер уже готов? (идемпотентность)
# =============================================================================
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
Write-Host "    Ожидаем нод: $ExpectedNodeCount (1 master + $WORKER_COUNT workers)"

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
        throw "Stage 2 nodes did not all register in the cluster in time."
    }

    Write-Host ("  Найдено {0}/{1} нод. Ждём {2}с (попытка {3}/{4})..." -f $totalCount, $ExpectedNodeCount, $NodeCountIntervalSeconds, $attempt, $NodeCountRetries)
    Start-Sleep -Seconds $NodeCountIntervalSeconds
}

# =============================================================================
# ФАЗА 2: Финализация сетевой настройки (Calico)
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 2/7: Финализация сети (Calico)..."
& vagrant ssh $MASTER_VM_NAME -c "sudo EXPECTED_NODE_COUNT=$ExpectedNodeCount NODE_COUNT_RETRIES=$NodeCountRetries NODE_COUNT_INTERVAL=$NodeCountIntervalSeconds NODE_READY_RETRIES=$NodeReadyRetries NODE_READY_INTERVAL=$NodeReadyIntervalSeconds bash /vagrant/scripts/finalize-cluster.sh"

# =============================================================================
# ФАЗА 3: Применение smoke-теста
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 3/7: Применение smoke-манифеста..."
Get-Content -Raw $smokeManifest | & vagrant ssh $MASTER_VM_NAME -c "cat > /tmp/nginx-smoke.yaml; sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/nginx-smoke.yaml"

# =============================================================================
# ФАЗА 4: Ожидание rollout smoke-Deployment
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 4/7: Ожидание rollout nginx-smoke..."
& vagrant ssh $MASTER_VM_NAME -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/nginx-smoke -n smoke-tests --timeout=300s"

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
        & vagrant ssh $MASTER_VM_NAME -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n smoke-tests -o wide"
        & vagrant ssh $MASTER_VM_NAME -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs job/nginx-smoke-check -n smoke-tests"
        throw "Smoke-Job не завершился успешно за отведённое время."
    }

    Write-Host ("  Smoke-Job выполняется. Ждём {0}с (попытка {1}/{2})..." -f $SmokeWaitIntervalSeconds, $attempt, $SmokeWaitRetries)
    Start-Sleep -Seconds $SmokeWaitIntervalSeconds
}

# =============================================================================
# ФАЗА 5b: Сводка smoke-namespace
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 5b/7: Сводка smoke-namespace..."
& vagrant ssh $MASTER_VM_NAME -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get all -n smoke-tests -o wide"

# =============================================================================
# ФАЗА 6: Установка Dashboard
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 6/7: Установка Dashboard..."
& vagrant ssh $MASTER_VM_NAME -c "sudo bash /vagrant/scripts/install-dashboard.sh"

# =============================================================================
# ФАЗА 7: Экспорт kubeconfig для Windows-хоста
# =============================================================================
Write-Host ">>> [post-bootstrap] Фаза 7/7: Экспорт kubeconfig для Windows..."
& powershell.exe -ExecutionPolicy Bypass -File $hostKubeconfigScript -OutputPath $hostKubeconfigPath

# =============================================================================
# ФАЗА 8: Создание маркера готовности кластера
# =============================================================================
$readyMarkerPath = Join-Path $stage2Dir ".vagrant\stage2-ready"
$readyTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
New-Item -Path $readyMarkerPath -ItemType File -Force | Out-Null
Set-Content -Path $readyMarkerPath -Value "ready=$readyTimestamp" -Encoding ascii
Write-Host ">>> [post-bootstrap] Маркер готовности создан: $readyMarkerPath"

# =============================================================================
# ФИНАЛЬНЫЕ ПОДСКАЗКИ
# =============================================================================
Pop-Location

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  STAGE 2 ГОТОВ!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

Show-DashboardToken

Write-Host ""
Write-Host "  kubectl из Windows PowerShell:"
Write-Host ('    $env:KUBECONFIG = "{0}"' -f $hostKubeconfigPath)
Write-Host ""
Write-Host "  Или используй helper в текущей сессии:"
Write-Host "    . .\scripts\use-stage2-kubectl.ps1"
Write-Host ""
Write-Host "  Проверка:"
Write-Host "    kubectl get nodes -o wide"
Write-Host "    kubectl get pods -A -o wide"
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
