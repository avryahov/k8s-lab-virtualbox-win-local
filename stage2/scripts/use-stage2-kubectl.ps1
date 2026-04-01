# =============================================================================
# use-stage2-kubectl.ps1 — Helper для быстрой установки KUBECONFIG
# =============================================================================
#
# ЗАЧЕМ НУЖЕН:
#   Чтобы не вводить каждый раз $env:KUBECONFIG = "..." вручную.
#
# КАК ИСПОЛЬЗОВАТЬ:
#   . .\scripts\use-stage2-kubectl.ps1
#
# После этого kubectl в текущей сессии будет работать с Stage 2 кластером.
# =============================================================================

$stage2Dir = Split-Path -Parent $PSScriptRoot
$kubeconfigPath = Join-Path $stage2Dir "kubeconfig-stage2.yaml"

if (Test-Path $kubeconfigPath) {
    $env:KUBECONFIG = $kubeconfigPath
    Write-Host "KUBECONFIG установлен для Stage 2:" -ForegroundColor Green
    Write-Host "  $kubeconfigPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Теперь можно использовать kubectl:" -ForegroundColor Yellow
    Write-Host "  kubectl get nodes" -ForegroundColor Gray
    Write-Host "  kubectl get pods -A" -ForegroundColor Gray
} else {
    Write-Host "kubeconfig-stage2.yaml не найден!" -ForegroundColor Red
    Write-Host "Сначала запустите:" -ForegroundColor Yellow
    Write-Host "  .\scripts\run-post-bootstrap.ps1" -ForegroundColor Cyan
}
