param(
    [string]$ConfigPath
)

# =============================================================================
# use-stage1-kubectl.ps1 — подключение kubeconfig stage1 к текущей PowerShell-сессии
# =============================================================================
#
# ЗАЧЕМ НУЖЕН ЭТОТ СКРИПТ:
#   После post-bootstrap stage1 создаёт локальный kubeconfig для Windows-хоста.
#   Чтобы обычный kubectl в PowerShell начал работать с этим учебным кластером,
#   нужно установить переменную окружения KUBECONFIG.
#
# КАК ИСПОЛЬЗОВАТЬ:
#   1. Открой PowerShell.
#   2. Перейди в папку stage1.
#   3. Выполни команду с точкой в начале:
#        . .\scripts\use-stage1-kubectl.ps1
#
# ПОЧЕМУ ЕСТЬ ТОЧКА И ПРОБЕЛ ПЕРЕД ПУТЁМ:
#   Это dot-sourcing. Такой запуск выполняет скрипт в текущей сессии PowerShell,
#   поэтому переменная KUBECONFIG остаётся доступной и после завершения скрипта.
#
# ЧТО ПОЛУЧАЕМ ПОСЛЕ ЭТОГО:
#   kubectl get nodes -o wide
#   kubectl get pods -A -o wide
#   kubectl get all -n smoke-tests -o wide
# =============================================================================

$ErrorActionPreference = "Stop"
$stage1Dir = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $stage1Dir "kubeconfig-stage1.yaml"
}

if (-not (Test-Path $ConfigPath)) {
    throw "Host kubeconfig not found: $ConfigPath"
}

$env:KUBECONFIG = $ConfigPath

Write-Host ">>> [stage1-kubectl] KUBECONFIG is set for the current PowerShell session:"
Write-Host ('$env:KUBECONFIG = "{0}"' -f $env:KUBECONFIG)
Write-Host ">>> [stage1-kubectl] Example commands:"
Write-Host "kubectl get nodes -o wide"
Write-Host "kubectl get pods -A -o wide"
Write-Host "kubectl get all -n smoke-tests -o wide"
