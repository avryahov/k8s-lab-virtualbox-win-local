param(
    [Parameter(Mandatory = $true)]
    [string]$NodeName,

    [Parameter(Mandatory = $true)]
    [string]$KeyDirectory
)

# =============================================================================
# cleanup-node-key.ps1 — Удаление SSH-ключей ноды при destroy (Stage 2)
# =============================================================================
#
# ЗАЧЕМ НУЖЕН:
#   При уничтожении ВМ через vagrant destroy нужно удалить файлы SSH-ключей,
#   чтобы они не накапливались в .vagrant/node-keys/ как «мусор».
#
# КЕМ ВЫЗЫВАЕТСЯ:
#   Vagrantfile (trigger.after :destroy) для каждой ноды отдельно.
#
# ЧТО ДЕЛАЕТ:
#   1. Удаляет публичный ключ (<имя>.ed25519.pub)
#   2. Удаляет приватный ключ (<имя>.ed25519)
#   3. Если директория .vagrant/node-keys/ опустела — удаляет и её
#
# ПОЧЕМУ ОТДЕЛЬНЫЙ СКРИПТ:
#   Vagrant-триггеры запускаются на хосте (Windows), а не внутри ВМ.
#   Поэтому нужен PowerShell-скрипт, а не bash.
#
# ИДЕМПОТЕНТНОСТЬ:
#   Проверяет наличие файлов перед удалением — не ошибка, если файлов нет.
# =============================================================================

$ErrorActionPreference = "Stop"

$privateKeyPath = Join-Path $KeyDirectory "$NodeName.ed25519"
$publicKeyPath = "$privateKeyPath.pub"

# Удаляем оба файла (сначала публичный, потом приватный).
# -Force — не спрашивать подтверждение.
# Проверка Test-Path — не ошибка, если файл уже удалён.
foreach ($path in @($publicKeyPath, $privateKeyPath)) {
    if (Test-Path $path) {
        Remove-Item -Force $path
        Write-Host "Removed $path"
    }
}

# Если директория ключей опустела — удаляем и её.
# Это предотвращает накопление пустых директорий после destroy всех нод.
if (Test-Path $KeyDirectory) {
    $remaining = Get-ChildItem -Force $KeyDirectory
    if (-not $remaining) {
        Remove-Item -Force $KeyDirectory
        Write-Host "Removed empty key directory $KeyDirectory"
    }
}
