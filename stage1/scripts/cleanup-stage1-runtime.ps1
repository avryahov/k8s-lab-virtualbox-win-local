param(
    [Parameter(Mandatory = $true)]
    [string]$Stage1Dir,

    [Parameter(Mandatory = $true)]
    [string]$VmPrefix
)

# =============================================================================
# cleanup-stage1-runtime.ps1 — финальная host-side очистка после destroy
# =============================================================================
#
# ЗАДАЧА СКРИПТА:
#   После полного `vagrant destroy` вернуть stage1 в чистое локальное состояние.
#
# ЧТО ИМЕННО ЧИСТИМ:
#   - join-command.sh
#   - .vagrant\stage1-cluster-token
#   - .vagrant\stage1-host-port-pool.json
#   - .vagrant\machines
#   - .vagrant\rgloader
#
# ПОЧЕМУ ЭТО НУЖНО:
#   Следующий `vagrant up` не должен опираться на старые токены, старый пул портов,
#   старые private_key-файлы или старые machine-state каталоги.
#
# ВАЖНО:
#   Перед удалением локального runtime скрипт проверяет, что VirtualBox-машины
#   текущего stage1-префикса действительно исчезли. Чужие кластеры не трогаются.
# =============================================================================

$ErrorActionPreference = "Stop"
$vboxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

function Get-VBoxVmList {
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $vboxManage
    $process.StartInfo.Arguments = "list vms"
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true

    [void]$process.Start()

    if (-not $process.WaitForExit(5000)) {
        try {
            $process.Kill()
        }
        catch {
        }

        return @{
            ExitCode = 124
            StdOut = ""
            StdErr = "VBoxManage list vms timed out"
        }
    }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()

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
        (Join-Path $vagrantDir "stage1-cluster-token"),
        (Join-Path $vagrantDir "stage1-host-port-pool.json"),
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

if (-not (Test-Path $vboxManage)) {
    Write-Host "VBoxManage not found, cleaning only local stage1 runtime artifacts"
    Remove-Stage1RuntimeArtifacts -WorkspaceDir $Stage1Dir
    exit 0
}

for ($attempt = 1; $attempt -le 5; $attempt++) {
    $listResult = Get-VBoxVmList
    if ($listResult.ExitCode -eq 0) {
        $prefixPattern = '^"' + [Regex]::Escape($VmPrefix) + '-'
        $clusterVmLines = @($listResult.StdOut -split "`r?`n" | Where-Object { $_ -match $prefixPattern })

        if ($clusterVmLines.Count -eq 0) {
            Remove-Stage1RuntimeArtifacts -WorkspaceDir $Stage1Dir
            exit 0
        }

        Write-Host "Stage1 VMs with prefix $VmPrefix still exist, skipping local cleanup for now"
        exit 0
    }

    if ($attempt -lt 5) {
        Write-Host "VBoxManage is not ready yet, waiting 3 seconds before retry $($attempt + 1)/5"
        Start-Sleep -Seconds 3
    }
}

Write-Host "VBoxManage stayed unavailable after destroy, cleaning only local stage1 runtime artifacts"
Remove-Stage1RuntimeArtifacts -WorkspaceDir $Stage1Dir
