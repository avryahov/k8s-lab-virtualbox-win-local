param(
    [Parameter(Mandatory = $true)]
    [string]$NodeName,

    [Parameter(Mandatory = $true)]
    [string]$KeyDirectory
)

# =============================================================================
# generate-node-key.ps1 — Генерация SSH-ключа ed25519 для ноды (Stage 2)
# =============================================================================
#
# ЗАЧЕМ НУЖЕН:
#   В Stage 2 вместо пароля vagrant/vagrant используются SSH-ключи.
#   Этот скрипт генерирует пару ключей (приватный + публичный) для каждой
#   ноды кластера ДО запуска виртуальных машин.
#
# КЕМ ВЫЗЫВАЕТСЯ:
#   Vagrantfile (функция ensure_node_key) при каждом vagrant up/reload/provision.
#
# ГДЕ ХРАНЯТСЯ КЛЮЧИ:
#   .vagrant/node-keys/<имя_ноды>.ed25519      — приватный ключ
#   .vagrant/node-keys/<имя_ноды>.ed25519.pub  — публичный ключ
#
# ПОЧЕМУ ED25519:
#   - Быстрее RSA при эквивалентной безопасности
#   - Ключ всего 32 байта (против 2048+ бит у RSA)
#   - Рекомендован NIST, OpenSSH, GitHub с 2014 года
#   - Не подвержен атакам на генератор случайных чисел (в отличие от ECDSA)
#
# ИДЕМПОТЕНТНОСТЬ:
#   Если приватный ключ уже существует — скрипт НЕ перегенерирует его.
#   Это позволяет безопасно вызывать vagrant up повторно без потери ключей.
#
# БЕЗОПАСНОСТЬ:
#   После генерации на ключи накладывается строгий ACL через icacls:
#   - Убирается наследование прав от родительской директории
#   - Доступ только у: текущего пользователя, SYSTEM, Administrators
#   Это предотвращает чтение ключей другими процессами на хосте.
# =============================================================================

$ErrorActionPreference = "Stop"

$privateKeyPath = Join-Path $KeyDirectory "$NodeName.ed25519"
$publicKeyPath = "$privateKeyPath.pub"

# ---------------------------------------------------------------------------
# Set-StrictAcl — наложение строгого ACL на файл ключа
# ---------------------------------------------------------------------------
# В Windows стандартные права NTFS могут давать доступ к файлу
# группе "Пользователи" или другим учётным записям.
# Для SSH-ключей это неприемлемо — приватный ключ должен быть доступен
# только владельцу.
#
# icacls /inheritance:r — убрать наследование прав
# /grant:r — заменить все существующие права на указанные:
#   %USERNAME%:F     — полный доступ текущему пользователю
#   *S-1-5-18:F      — полный доступ SYSTEM (SID: S-1-5-18)
#   *S-1-5-32-544:F  — полный доступ Administrators (SID: S-1-5-32-544)
#
# Почему через cmd.exe /c icacls, а не через Set-Acl:
#   Set-Acl в PowerShell сложен для точной настройки прав.
#   icacls — стандартная утилита Windows, надёжнее и проще.
function Set-StrictAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $command = 'icacls "{0}" /inheritance:r /grant:r "%USERNAME%:F" /grant:r "*S-1-5-18:F" /grant:r "*S-1-5-32-544:F"' -f $Path
    & cmd.exe /c $command | Out-Null
}

# Создаём директорию для ключей, если не существует.
# -Force — не ошибка, если уже есть.
# | Out-Null — подавляем вывод New-Item.
New-Item -ItemType Directory -Force -Path $KeyDirectory | Out-Null

# Генерируем пару ключей ed25519, если приватный ключ ещё не существует.
# ssh-keygen -t ed25519 — тип ключа
# -q — тихий режим (без вывода прогресса)
# -N "" — пустая passphrase (для автоматизации, без интерактивного ввода)
# -C "vagrant-<имя_ноды>" — комментарий в ключе (для идентификации)
# -f "<путь>" — куда сохранить приватный ключ (публичный будет <путь>.pub)
if (-not (Test-Path $privateKeyPath)) {
    $comment = "vagrant-$NodeName"
    $sshKeygenCommand = 'ssh-keygen -t ed25519 -q -N "" -C "{0}" -f "{1}"' -f $comment, $privateKeyPath
    & cmd.exe /c $sshKeygenCommand | Out-Null
}

# Проверяем, что публичный ключ действительно создался.
# ssh-keygen должен создать оба файла, но защита от «тихой» ошибки не помешает.
if (-not (Test-Path $publicKeyPath)) {
    throw "Public key was not created for $NodeName"
}

# Накладываем строгий ACL на оба файла.
Set-StrictAcl -Path $privateKeyPath
Set-StrictAcl -Path $publicKeyPath

Write-Host "SSH key ready for ${NodeName}: $privateKeyPath"
