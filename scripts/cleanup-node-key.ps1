param(
    [Parameter(Mandatory = $true)]
    [string]$NodeName,

    [Parameter(Mandatory = $true)]
    [string]$KeyDirectory
)

$ErrorActionPreference = "Stop"

$privateKeyPath = Join-Path $KeyDirectory "$NodeName.ed25519"
$publicKeyPath = "$privateKeyPath.pub"

foreach ($path in @($publicKeyPath, $privateKeyPath)) {
    if (Test-Path $path) {
        Remove-Item -Force $path
        Write-Host "Removed $path"
    }
}

if (Test-Path $KeyDirectory) {
    $remaining = Get-ChildItem -Force $KeyDirectory
    if (-not $remaining) {
        Remove-Item -Force $KeyDirectory
        Write-Host "Removed empty key directory $KeyDirectory"
    }
}
