param(
    [string]$OutputPath
)

# =============================================================================
# export-host-kubeconfig.ps1 — подготовка kubeconfig для Windows-хоста
# =============================================================================
#
# ЗАЧЕМ НУЖЕН ЭТОТ СКРИПТ:
#   Kubernetes внутри master-ноды уже имеет рабочий admin.conf.
#   Но Windows-хост не может использовать его "как есть", потому что внутри
#   файла сервер обычно указан как внутренний IP master-ноды.
#
# ЧТО ДЕЛАЕТ СКРИПТ:
#   1. Забирает /etc/kubernetes/admin.conf с master-ноды через vagrant ssh.
#   2. Сохраняет копию в папке stage1.
#   3. Меняет адрес API server на https://127.0.0.1:6443, потому что именно
#      этот порт проброшен Vagrant с master-ноды на Windows-хост.
#
# РЕЗУЛЬТАТ:
#   После этого обычный kubectl на Windows может работать без vagrant ssh:
#     kubectl get nodes
#     kubectl get pods -A
# =============================================================================

$ErrorActionPreference = "Stop"
$stage1Dir = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $stage1Dir "kubeconfig-stage1.yaml"
}

Push-Location $stage1Dir

try {
    Write-Host ">>> [host-kubeconfig] Exporting admin.conf from master..."
    $rawConfig = & vagrant ssh k8s-master -c "sudo cat /etc/kubernetes/admin.conf"

    if (-not $rawConfig) {
        throw "Master returned empty kubeconfig content."
    }

    $configText = ($rawConfig -join "`r`n")
    $configText = $configText -replace 'https://k8s-master:6443', 'https://127.0.0.1:6443'
    $configText = $configText -replace 'https://192\.168\.56\.10:6443', 'https://127.0.0.1:6443'

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
}
finally {
    Pop-Location
}
