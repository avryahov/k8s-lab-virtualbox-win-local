param(
    [Parameter(Mandatory = $true)]
    [string]$NodeName,

    [Parameter(Mandatory = $true)]
    [string]$KeyDirectory
)

$ErrorActionPreference = "Stop"

$privateKeyPath = Join-Path $KeyDirectory "$NodeName.ed25519"
$publicKeyPath = "$privateKeyPath.pub"

function Set-StrictAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $command = 'icacls "{0}" /inheritance:r /grant:r "%USERNAME%:F" /grant:r "*S-1-5-18:F" /grant:r "*S-1-5-32-544:F"' -f $Path
    & cmd.exe /c $command | Out-Null
}

New-Item -ItemType Directory -Force -Path $KeyDirectory | Out-Null

if (-not (Test-Path $privateKeyPath)) {
    $comment = "vagrant-$NodeName"
    $sshKeygenCommand = 'ssh-keygen -t ed25519 -q -N "" -C "{0}" -f "{1}"' -f $comment, $privateKeyPath
    & cmd.exe /c $sshKeygenCommand | Out-Null
}

if (-not (Test-Path $publicKeyPath)) {
    throw "Public key was not created for $NodeName"
}

Set-StrictAcl -Path $privateKeyPath
Set-StrictAcl -Path $publicKeyPath

Write-Host "SSH key ready for ${NodeName}: $privateKeyPath"
