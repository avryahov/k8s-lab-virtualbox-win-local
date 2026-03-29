param(
    [Parameter(Mandatory = $true)]
    [string]$VmName
)

$ErrorActionPreference = "Stop"
$vboxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

if (-not (Test-Path $vboxManage)) {
    Write-Host "VBoxManage not found, skipping orphan cleanup for $VmName"
    exit 0
}

$showInfo = & $vboxManage showvminfo $VmName --machinereadable 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "No orphan VirtualBox VM found for $VmName"
    exit 0
}

$isRunning = $showInfo | Select-String '^VMState="running"$'
if ($isRunning) {
    & $vboxManage controlvm $VmName poweroff 2>$null | Out-Null
}

& $vboxManage unregistervm $VmName --delete 2>$null | Out-Null
Write-Host "Removed orphan VirtualBox VM tail: $VmName"
