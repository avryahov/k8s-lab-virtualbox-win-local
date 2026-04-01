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
# ЛОГИКА СЦЕНАРИЯ:
#   1. Проверить, что в кластере зарегистрированы все ноды.
#   2. На master выполнить сетевую финализацию (Calico).
#   3. Применить простой smoke-тест из корня проекта.
#   4. Убедиться, что smoke-тест реально прошёл.
#   5. И только затем установить Dashboard.
#   6. Экспортировать kubeconfig для Windows-хоста.
#
# ПОЧЕМУ ИМЕННО ТАК:
#   Сначала нужно доказать, что кластер способен исполнять обычную нагрузку,
#   и лишь потом добавлять веб-интерфейс как последнее удобство.
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

Write-Host ">>> [post-bootstrap] Checking that all Stage 2 nodes are registered..."
Write-Host "    Expected nodes: $ExpectedNodeCount (1 master + $WORKER_COUNT workers)"

for ($attempt = 1; $attempt -le $NodeCountRetries; $attempt++) {
    $nodesOutput = Invoke-MasterKubectl "get nodes --no-headers"
    $nodeLines = @($nodesOutput | Where-Object { $_.Trim() -ne "" })
    $totalCount = $nodeLines.Count

    if ($totalCount -eq $ExpectedNodeCount) {
        Write-Host "  Cluster API already sees all $ExpectedNodeCount nodes."
        break
    }

    if ($attempt -eq $NodeCountRetries) {
        Write-Host $nodesOutput
        throw "Stage 2 nodes did not all register in the cluster in time."
    }

    Write-Host ("  Found {0}/{1} nodes. Waiting {2}s (attempt {3}/{4})..." -f $totalCount, $ExpectedNodeCount, $NodeCountIntervalSeconds, $attempt, $NodeCountRetries)
    Start-Sleep -Seconds $NodeCountIntervalSeconds
}

Write-Host ">>> [post-bootstrap] Finalizing cluster networking on master..."
& vagrant ssh $MASTER_VM_NAME -c "sudo EXPECTED_NODE_COUNT=$ExpectedNodeCount NODE_COUNT_RETRIES=$NodeCountRetries NODE_COUNT_INTERVAL=$NodeCountIntervalSeconds NODE_READY_RETRIES=$NodeReadyRetries NODE_READY_INTERVAL=$NodeReadyIntervalSeconds bash /vagrant/scripts/finalize-cluster.sh"

Write-Host ">>> [post-bootstrap] Applying smoke manifest from repo root..."
Get-Content -Raw $smokeManifest | & vagrant ssh $MASTER_VM_NAME -c "cat > /tmp/nginx-smoke.yaml; sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/nginx-smoke.yaml"

Write-Host ">>> [post-bootstrap] Waiting for nginx-smoke rollout..."
& vagrant ssh $MASTER_VM_NAME -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/nginx-smoke -n smoke-tests --timeout=300s"

Write-Host ">>> [post-bootstrap] Waiting for nginx-smoke-check Job..."
for ($attempt = 1; $attempt -le $SmokeWaitRetries; $attempt++) {
    $jobOutput = Invoke-MasterKubectl "get job nginx-smoke-check -n smoke-tests -o jsonpath='{.status.succeeded}'"
    if ($jobOutput -eq "1") {
        Write-Host "  Smoke Job finished successfully."
        break
    }

    if ($attempt -eq $SmokeWaitRetries) {
        & vagrant ssh $MASTER_VM_NAME -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n smoke-tests -o wide"
        & vagrant ssh $MASTER_VM_NAME -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs job/nginx-smoke-check -n smoke-tests"
        throw "Smoke Job did not finish successfully in time."
    }

    Write-Host ("  Smoke job is still running. Waiting {0}s (attempt {1}/{2})..." -f $SmokeWaitIntervalSeconds, $attempt, $SmokeWaitRetries)
    Start-Sleep -Seconds $SmokeWaitIntervalSeconds
}

Write-Host ">>> [post-bootstrap] Final smoke namespace summary..."
& vagrant ssh $MASTER_VM_NAME -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get all -n smoke-tests -o wide"

Write-Host ">>> [post-bootstrap] Smoke-test passed. Installing Dashboard as the final stage..."
& vagrant ssh $MASTER_VM_NAME -c "sudo bash /vagrant/scripts/install-dashboard.sh"

Write-Host ">>> [post-bootstrap] Exporting kubeconfig for Windows host kubectl..."
& powershell.exe -ExecutionPolicy Bypass -File $hostKubeconfigScript -OutputPath $hostKubeconfigPath

Write-Host ">>> [post-bootstrap] Windows host can now use kubectl directly after:"
Write-Host ('$env:KUBECONFIG = "{0}"' -f $hostKubeconfigPath)
Write-Host ">>> [post-bootstrap] Or run this helper in the current PowerShell session:"
Write-Host ". .\scripts\use-stage2-kubectl.ps1"

Pop-Location

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Stage 2 cluster is READY!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Dashboard: https://localhost:$MASTER_DASHBOARD_PORT" -ForegroundColor Cyan
Write-Host "  Token:     vagrant ssh $MASTER_VM_NAME -- kubectl -n kubernetes-dashboard create token admin-user" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
