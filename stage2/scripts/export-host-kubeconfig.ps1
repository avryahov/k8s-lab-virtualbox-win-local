param(
    [string]$OutputPath
)

# =============================================================================
# export-host-kubeconfig.ps1 — Подготовка kubeconfig для Windows-хоста (Stage 2)
# =============================================================================
#
# ЗАЧЕМ НУЖЕН ЭТОТ СКРИПТ:
#   Kubernetes внутри master-ноды уже имеет рабочий admin.conf.
#   Но Windows-хост не может использовать его "как есть", потому что внутри
#   файла сервер обычно указан как внутренний IP master-ноды.
#
# ЧТО ДЕЛАЕТ СКРИПТ:
#   1. Забирает /etc/kubernetes/admin.conf с master-ноды через vagrant ssh.
#   2. Сохраняет копию в папке stage2.
#   3. Меняет адрес API server на https://127.0.0.1:6443, потому что именно
#      этот порт проброшен Vagrant с master-ноды на Windows-хост.
#
# РЕЗУЛЬТАТ:
#   После этого обычный kubectl на Windows может работать без vagrant ssh:
#     kubectl get nodes
#     kubectl get pods -A
#
# ОТЛИЧИЯ ОТ STAGE 1:
#   - Использует MASTER_DASHBOARD_PORT из .env (по умолчанию 30443)
#   - Сохраняет в stage2/kubeconfig-stage2.yaml
# =============================================================================

$ErrorActionPreference = "Stop"
$stage2Dir = Split-Path -Parent $PSScriptRoot

# Загружаем .env файл для получения имён ВМ и порта Dashboard
$envFile = Join-Path $stage2Dir ".env"
$MASTER_VM_NAME = "lab-k8s-master"
$MASTER_DASHBOARD_PORT = "30443"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*MASTER_VM_NAME=(.*)\s*$') {
            $MASTER_VM_NAME = $matches[1].Trim().Trim('"').Trim("'")
        }
        if ($_ -match '^\s*MASTER_DASHBOARD_PORT=(.*)\s*$') {
            $MASTER_DASHBOARD_PORT = $matches[1].Trim().Trim('"').Trim("'")
        }
    }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $stage2Dir "kubeconfig-stage2.yaml"
}

Push-Location $stage2Dir

try {
    Write-Host ">>> [host-kubeconfig] Exporting admin.conf from $MASTER_VM_NAME..."
    $rawConfig = & vagrant ssh $MASTER_VM_NAME -c "sudo cat /etc/kubernetes/admin.conf"

    if (-not $rawConfig) {
        throw "Master returned empty kubeconfig content."
    }

    $configText = ($rawConfig -join "`r`n")
    
    # Заменяем все возможные варианты адреса API server на localhost
    $configText = $configText -replace 'https://lab-k8s-master:6443', 'https://127.0.0.1:6443'
    $configText = $configText -replace 'https://k8s-master:6443', 'https://127.0.0.1:6443'
    $configText = $configText -replace 'https://192\.168\.56\.10:6443', 'https://127.0.0.1:6443'
    $configText = $configText -replace 'https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:6443', 'https://127.0.0.1:6443'

    # Для Windows-хоста это локальный учебный kubeconfig.
    # Нам важнее стабильный доступ через localhost, чем строгая TLS-проверка SAN.
    # Поэтому убираем certificate-authority-data и включаем insecure-skip-tls-verify.
    $configText = $configText -replace '(?m)^\s*certificate-authority-data: .*\r?\n', ''

    if ($configText -notmatch 'insecure-skip-tls-verify: true') {
        $configText = $configText -replace "    server: https://127\.0\.0\.1:6443", "    server: https://127.0.0.1:6443`r`n    insecure-skip-tls-verify: true"
    }

    Set-Content -Path $OutputPath -Value $configText -Encoding ascii

    Write-Host ">>> [host-kubeconfig] Host kubeconfig saved to: $OutputPath"
    Write-Host ">>> [host-kubeconfig] To use kubectl directly from Windows run:"
    Write-Host ('$env:KUBECONFIG = "{0}"' -f $OutputPath)
    Write-Host ">>> [host-kubeconfig] Dashboard available at: https://localhost:$MASTER_DASHBOARD_PORT"
}
finally {
    Pop-Location
}
