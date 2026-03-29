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
# Этот PowerShell-скрипт запускается на Windows-хосте уже после того,
# как Vagrant поднял master и worker-ноды.
#
# ЛОГИКА СЦЕНАРИЯ:
#   1. Проверить, что в кластере зарегистрированы все ноды.
#   2. На master выполнить сетевую финализацию (Calico).
#   3. Применить простой smoke-тест из корня проекта.
#   4. Убедиться, что smoke-тест реально прошёл.
#   5. И только затем установить Dashboard.
#
# ПОЧЕМУ ИМЕННО ТАК:
#   Сначала нужно доказать, что кластер способен исполнять обычную нагрузку,
#   и лишь потом добавлять веб-интерфейс как последнее удобство.
# =============================================================================

$ErrorActionPreference = "Stop"
$stage1Dir = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $stage1Dir
$smokeManifest = Join-Path $repoRoot "smoke-tests\nginx-smoke.yaml"

if (-not (Test-Path $smokeManifest)) {
    throw "Smoke manifest not found: $smokeManifest"
}

Push-Location $stage1Dir

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

Write-Host ">>> [post-bootstrap] Checking that all stage1 nodes are registered..."

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
        throw "Stage1 nodes did not all register in the cluster in time."
    }

    Write-Host ("  Found {0}/{1} nodes. Waiting {2}s (attempt {3}/{4})..." -f $totalCount, $ExpectedNodeCount, $NodeCountIntervalSeconds, $attempt, $NodeCountRetries)
    Start-Sleep -Seconds $NodeCountIntervalSeconds
}

Write-Host ">>> [post-bootstrap] Finalizing cluster networking on master..."
& vagrant ssh k8s-master -c "sudo EXPECTED_NODE_COUNT=$ExpectedNodeCount NODE_COUNT_RETRIES=$NodeCountRetries NODE_COUNT_INTERVAL=$NodeCountIntervalSeconds NODE_READY_RETRIES=$NodeReadyRetries NODE_READY_INTERVAL=$NodeReadyIntervalSeconds bash /vagrant/scripts/finalize-cluster.sh"

Write-Host ">>> [post-bootstrap] Applying smoke manifest from repo root..."
Get-Content -Raw $smokeManifest | & vagrant ssh k8s-master -c "cat > /tmp/nginx-smoke.yaml; sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/nginx-smoke.yaml"

Write-Host ">>> [post-bootstrap] Waiting for nginx-smoke rollout..."
& vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/nginx-smoke -n smoke-tests --timeout=300s"

Write-Host ">>> [post-bootstrap] Waiting for nginx-smoke-check Job..."
for ($attempt = 1; $attempt -le $SmokeWaitRetries; $attempt++) {
    $jobOutput = Invoke-MasterKubectl "get job nginx-smoke-check -n smoke-tests -o jsonpath='{.status.succeeded}'"
    if ($jobOutput -eq "1") {
        Write-Host "  Smoke Job finished successfully."
        break
    }

    if ($attempt -eq $SmokeWaitRetries) {
        & vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n smoke-tests -o wide"
        & vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs job/nginx-smoke-check -n smoke-tests"
        throw "Smoke Job did not finish successfully in time."
    }

    Write-Host ("  Smoke job is still running. Waiting {0}s (attempt {1}/{2})..." -f $SmokeWaitIntervalSeconds, $attempt, $SmokeWaitRetries)
    Start-Sleep -Seconds $SmokeWaitIntervalSeconds
}

Write-Host ">>> [post-bootstrap] Final smoke namespace summary..."
& vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get all -n smoke-tests -o wide"

Write-Host ">>> [post-bootstrap] Smoke-test passed. Installing Dashboard as the final stage..."
& vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/install-dashboard.sh"

Pop-Location
