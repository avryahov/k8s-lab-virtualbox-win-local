param(
    [Parameter(Mandatory = $true)]
    [string]$VmName,

    [string]$Stage1Dir,

    [string]$VmPrefix
)

# =============================================================================
# cleanup-vbox-tail.ps1 — точечная очистка orphan-VM после destroy
# =============================================================================
#
# ВАЖНО ПРО POWERSHELL:
# 1. В host-side сценариях нельзя полагаться на то, что внешняя утилита
#    с кодом возврата != 0 будет вести себя "тихо".
# 2. PowerShell может превратить stderr внешней программы в ошибку пайплайна.
# 3. Поэтому VBoxManage здесь запускается через Process API:
#    - мы отдельно забираем stdout/stderr;
#    - отдельно читаем ExitCode;
#    - отдельно принимаем решение, ошибка это или ожидаемая ситуация.
#
# Такой подход нужен, чтобы destroy не падал на нормальном случае:
# "машина уже отсутствует, хвостов нет".
# =============================================================================

$ErrorActionPreference = "Stop"
$vboxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

if (-not (Test-Path $vboxManage)) {
    Write-Host "VBoxManage not found, skipping orphan cleanup for $VmName"
    exit 0
}

function Invoke-VBoxManage {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $vboxManage
    $process.StartInfo.Arguments = ($Arguments -join " ")
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true

    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return @{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Remove-Stage1RuntimeArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceDir
    )

    $vagrantDir = Join-Path $WorkspaceDir ".vagrant"
    $runtimePaths = @(
        (Join-Path $WorkspaceDir "join-command.sh"),
        (Join-Path $WorkspaceDir "dashboard-token.txt"),
        (Join-Path $WorkspaceDir "kubeconfig-stage1.yaml"),
        (Join-Path $vagrantDir "stage1-cluster-token"),
        (Join-Path $vagrantDir "stage1-host-port-pool.json"),
        (Join-Path $vagrantDir "stage1-ready"),
        (Join-Path $vagrantDir "machines"),
        (Join-Path $vagrantDir "rgloader")
    )

    foreach ($path in $runtimePaths) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force
            Write-Host "Removed stage1 runtime artifact: $path"
        }
    }

    if (Test-Path $vagrantDir) {
        $remainingItems = Get-ChildItem -Force $vagrantDir
        if ($remainingItems.Count -eq 0) {
            Remove-Item -Path $vagrantDir -Force
            Write-Host "Removed empty stage1 .vagrant directory"
        }
    }
}

$showInfoResult = Invoke-VBoxManage -Arguments @("showvminfo", """$VmName""", "--machinereadable")
if ($showInfoResult.ExitCode -ne 0) {
    Write-Host "No orphan VirtualBox VM found for $VmName"
}
else {
    $showInfo = $showInfoResult.StdOut
    $isRunning = $showInfo | Select-String '^VMState="running"$'
    if ($isRunning) {
        [void](Invoke-VBoxManage -Arguments @("controlvm", """$VmName""", "poweroff"))
    }

    $removeResult = Invoke-VBoxManage -Arguments @("unregistervm", """$VmName""", "--delete")
    if ($removeResult.ExitCode -ne 0) {
        throw "Failed to remove orphan VirtualBox VM tail '$VmName': $($removeResult.StdErr.Trim())"
    }

    Write-Host "Removed orphan VirtualBox VM tail: $VmName"
}

if (-not [string]::IsNullOrWhiteSpace($VmPrefix) -and -not [string]::IsNullOrWhiteSpace($Stage1Dir)) {
    $allVmsResult = Invoke-VBoxManage -Arguments @("list", "vms")
    if ($allVmsResult.ExitCode -ne 0) {
        throw "Failed to list VirtualBox VMs after cleanup: $($allVmsResult.StdErr.Trim())"
    }

    $prefixPattern = '^"' + [Regex]::Escape($VmPrefix) + '-'
    $clusterVmLines = @($allVmsResult.StdOut -split "`r?`n" | Where-Object { $_ -match $prefixPattern })

    if ($clusterVmLines.Count -eq 0) {
        Write-Host "No VirtualBox VMs remain for prefix $VmPrefix, cleaning local stage1 runtime state"
        Remove-Stage1RuntimeArtifacts -WorkspaceDir $Stage1Dir
    }
    else {
        Write-Host "Stage1 VMs with prefix $VmPrefix still exist, local runtime files are kept for the remaining nodes"
    }
}
