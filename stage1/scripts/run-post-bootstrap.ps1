param(
    [int]$ExpectedNodeCount = 3,
    [int]$NodeCountRetries = 30,
    [int]$NodeCountIntervalSeconds = 10,
    [int]$NodeReadyRetries = 36,
    [int]$NodeReadyIntervalSeconds = 10,
    [int]$SmokeWaitRetries = 30,
    [int]$SmokeWaitIntervalSeconds = 10
)

# =============================================================================
# run-post-bootstrap.ps1 — host-side финализация stage1
# =============================================================================
#
# ЧТО ЭТО:
#   PowerShell-скрипт, который запускается на Windows-хосте уже после того,
#   как Vagrant поднял master и worker-ноды (после vagrant up).
#
# ЗАЧЕМ ОТДЕЛЬНЫЙ СКРИПТ:
#   vagrant up создаёт ВМ и запускает provisioning (common.sh, master.sh,
#   worker.sh). Но после этого кластер ещё не полностью готов:
#     - Ноды могут ещё не зарегистрироваться в API
#     - Calico может ещё не развернуться
#     - Smoke-тест не запущен
#     - Dashboard не установлен
#     - kubeconfig не экспортирован на хост
#
#   Этот скрипт завершает настройку и подтверждает, что кластер работает.
#
# ЛОГИКА СЦЕНАРИЯ (7 фаз):
#   Фаза 1: Проверить, что в кластере зарегистрированы все ноды
#   Фаза 2: На master выполнить сетевую финализацию (Calico)
#   Фаза 3: Применить smoke-тест из корня проекта
#   Фаза 4: Убедиться, что smoke-тест реально прошёл
#   Фаза 5: Вывести сводку smoke-namespace
#   Фаза 6: Установить Dashboard
#   Фаза 7: Экспортировать kubeconfig для Windows-хоста
#
# ПОЧЕМУ ИМЕННО ТАКОЙ ПОРЯДОК:
#   Сначала нужно доказать, что кластер способен исполнять обычную нагрузку
#   (smoke-тест), и лишь потом добавлять веб-интерфейс как последнее удобство.
#   Это учит правильному подходу: инфраструктура → приложение → UI.
#
# КАК ЗАПУСТИТЬ:
#   powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
#
#   Или через launch.bat (который запускает vagrant up, а потом этот скрипт).
#
# КОНФИГУРИРУЕМЫЕ ПАРАМЕТРЫ:
#   ExpectedNodeCount           — сколько нод ожидаем (по умолчанию 3)
#   NodeCountRetries            — retries для проверки регистрации
#   NodeCountIntervalSeconds    — пауза между проверками регистрации
#   NodeReadyRetries            — retries для проверки Ready
#   NodeReadyIntervalSeconds    — пауза между проверками Ready
#   SmokeWaitRetries            — retries для ожидания smoke-теста
#   SmokeWaitIntervalSeconds    — пауза между проверками smoke-теста
# =============================================================================

# Stop — любая ошибка прерывает выполнение скрипта.
# Это важно: если одна фаза провалилась, нет смысла продолжать.
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Определение путей
# ---------------------------------------------------------------------------
# $PSScriptRoot — директория, в которой лежит этот скрипт (stage1/scripts/).
# Split-Path -Parent — подняться на уровень вверх.
$stage1Dir = Split-Path -Parent $PSScriptRoot           # stage1/
$repoRoot = Split-Path -Parent $stage1Dir                # корень проекта (crm/)
$smokeManifest = Join-Path $repoRoot "smoke-tests\nginx-smoke.yaml"
$hostKubeconfigScript = Join-Path $PSScriptRoot "export-host-kubeconfig.ps1"
$hostKubeconfigPath = Join-Path $stage1Dir "kubeconfig-stage1.yaml"
$hostKubectlHelper = Join-Path $PSScriptRoot "use-stage1-kubectl.ps1"

# ---------------------------------------------------------------------------
# Проверка наличия необходимых файлов
# ---------------------------------------------------------------------------
# Если файлы отсутствуют — нет смысла продолжать.
# throw — выбрасывает исключение, которое прерывает скрипт.
if (-not (Test-Path $smokeManifest)) {
    throw "Smoke manifest not found: $smokeManifest"
}

if (-not (Test-Path $hostKubeconfigScript)) {
    throw "Host kubeconfig export script not found: $hostKubeconfigScript"
}

if (-not (Test-Path $hostKubectlHelper)) {
    throw "Host kubectl helper script not found: $hostKubectlHelper"
}

# Переходим в директорию stage1 — это нужно для корректной работы
# vagrant-команд (Vagrant ищет Vagrantfile в текущей директории).
Push-Location $stage1Dir

# ---------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ---------------------------------------------------------------------------

# Invoke-VagrantCapture — выполнить команду на master-ноде через vagrant ssh.
#
# КАК РАБОТАЕТ:
#   vagrant ssh k8s-master -c "команда" — подключается к master-ноде
#   и выполняет команду в non-interactive режиме.
#
#   2>$null — подавляем stderr (ошибки подключения и т.п.),
#   чтобы вывод содержал только результат команды.
#
# ЗАЧЕМ ФУНКЦИЯ:
#   Чтобы не повторять одну и ту же конструкцию vagrant ssh
#   в каждой фазе. DRY (Don't Repeat Yourself).
function Invoke-VagrantCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    & vagrant ssh k8s-master -c $Command 2>$null
}

# Invoke-MasterKubectl — выполнить kubectl-команду на master-ноде.
#
# ЗАЧЕМ ОТДЕЛЬНАЯ ФУНКЦИЯ:
#   kubectl на master-ноде требует:
#     1. sudo (для доступа к /etc/kubernetes/admin.conf)
#     2. KUBECONFIG=/etc/kubernetes/admin.conf
#   Эта функция оборачивает всё в одну удобную обёртку.
#
# ПРИМЕР ИСПОЛЬЗОВАНИЯ:
#   Invoke-MasterKubectl "get nodes"
#   Invoke-MasterKubectl "get pods -A"
function Invoke-MasterKubectl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$KubectlCommand
    )

    Invoke-VagrantCapture "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl $KubectlCommand"
}

# =============================================================================
# ФАЗА 1: Проверка регистрации нод в кластере
# =============================================================================
# После kubeadm join worker-ноды не появляются в API мгновенно.
# Control plane должен обработать запрос, создать объект Node,
# kubelet должен зарегистрироваться. Это занимает 30–120 секунд.
#
# Мы опрашиваем API с интервалом, пока не увидим все ожидаемые ноды.
Write-Host ">>> [post-bootstrap] Фаза 1/7: Проверка регистрации нод..."

for ($attempt = 1; $attempt -le $NodeCountRetries; $attempt++) {
    # Получаем список нод без заголовков таблицы.
    $nodesOutput = Invoke-MasterKubectl "get nodes --no-headers"
    # Фильтруем пустые строки и считаем количество нод.
    $nodeLines = @($nodesOutput | Where-Object { $_.Trim() -ne "" })
    $totalCount = $nodeLines.Count

    if ($totalCount -eq $ExpectedNodeCount) {
        Write-Host "  Cluster API уже видит все $ExpectedNodeCount ноды."
        break
    }

    if ($attempt -eq $NodeCountRetries) {
        # Все попытки исчерпаны — ноды не зарегистрировались.
        Write-Host $nodesOutput
        throw "Stage1 nodes did not all register in the cluster in time."
    }

    Write-Host ("  Найдено {0}/{1} нод. Ждём {2}с (попытка {3}/{4})..." -f $totalCount, $ExpectedNodeCount, $NodeCountIntervalSeconds, $attempt, $NodeCountRetries)
    Start-Sleep -Seconds $NodeCountIntervalSeconds
}

# =============================================================================
# ФАЗА 2: Финализация сетевой настройки (Calico)
# =============================================================================
# Запускаем finalize-cluster.sh на master-ноде.
# Этот скрипт:
#   - Проверяет, что все ноды зарегистрированы
#   - Устанавливает Calico (если ещё не установлен)
#   - Ждёт, пока ноды станут Ready
#   - Проверяет Calico-поды
#
# Передаём параметры через env-переменные, чтобы скрипт знал,
# сколько нод ожидать и сколько раз retries.
Write-Host ">>> [post-bootstrap] Фаза 2/7: Финализация сети (Calico)..."
& vagrant ssh k8s-master -c "sudo EXPECTED_NODE_COUNT=$ExpectedNodeCount NODE_COUNT_RETRIES=$NodeCountRetries NODE_COUNT_INTERVAL=$NodeCountIntervalSeconds NODE_READY_RETRIES=$NodeReadyRetries NODE_READY_INTERVAL=$NodeReadyIntervalSeconds bash /vagrant/scripts/finalize-cluster.sh"

# =============================================================================
# ФАЗА 3: Применение smoke-теста
# =============================================================================
# Smoke-тест — это простой nginx-Deployment с 3 репликами,
# ClusterIP Service и проверочный Job.
#
# КАК ПРИМЕНЯЕМ:
#   Get-Content -Raw — читаем YAML-файл целиком как одну строку.
#   | & vagrant ssh ... -c "cat > /tmp/nginx-smoke.yaml; kubectl apply ..."
#   — передаём содержимое через stdin на master-ноду,
#     записываем во временный файл и применяем через kubectl.
#
# ПОЧЕМУ НЕ vagrant ssh ... -c "kubectl apply -f /vagrant/smoke-tests/...":
#   /vagrant/ на master-ноде — это директория stage1/, а smoke-tests/
#   лежит в корне проекта (crm/smoke-tests/). Путь /vagrant/smoke-tests/
#   не существует внутри ВМ. Поэтому передаём файл через stdin.
Write-Host ">>> [post-bootstrap] Фаза 3/7: Применение smoke-манифеста..."
Get-Content -Raw $smokeManifest | & vagrant ssh k8s-master -c "cat > /tmp/nginx-smoke.yaml; sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/nginx-smoke.yaml"

# =============================================================================
# ФАЗА 4: Ожидание rollout smoke-Deployment
# =============================================================================
# rollout status — ждёт, пока Deployment достигнет желаемого состояния.
# --timeout=300s — максимум 5 минут на развёртывание.
#
# ЧТО ЖДЁМ:
#   3 реплики nginx-smoke должны перейти в Running и Ready.
#   Это включает: скачивание образа, запуск контейнера,
#   прохождение readiness probe.
Write-Host ">>> [post-bootstrap] Фаза 4/7: Ожидание rollout nginx-smoke..."
& vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/nginx-smoke -n smoke-tests --timeout=300s"

# =============================================================================
# ФАЗА 5: Ожидание успешного завершения smoke-Job
# =============================================================================
# Job nginx-smoke-check — это curl-контейнер, который пытается
# достучаться до nginx-smoke Service через in-cluster DNS.
#
# Job считается успешным, когда .status.succeeded == 1.
# Мы опрашиваем с интервалом, потому что Job может выполняться
# до 2.5 минут (30 попыток × 5 секунд).
Write-Host ">>> [post-bootstrap] Фаза 5/7: Ожидание smoke-Job..."
for ($attempt = 1; $attempt -le $SmokeWaitRetries; $attempt++) {
    # jsonpath — извлечь конкретное поле из JSON-вывода kubectl.
    # {.status.succeeded} — количество успешных завершений Job.
    $jobOutput = Invoke-MasterKubectl "get job nginx-smoke-check -n smoke-tests -o jsonpath='{.status.succeeded}'"
    if ($jobOutput -eq "1") {
        Write-Host "  Smoke-Job успешно завершён."
        break
    }

    if ($attempt -eq $SmokeWaitRetries) {
        # Job не завершился вовремя — выводим диагностику.
        & vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n smoke-tests -o wide"
        & vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs job/nginx-smoke-check -n smoke-tests"
        throw "Smoke-Job не завершился успешно за отведённое время."
    }

    Write-Host ("  Smoke-Job выполняется. Ждём {0}с (попытка {1}/{2})..." -f $SmokeWaitIntervalSeconds, $attempt, $SmokeWaitRetries)
    Start-Sleep -Seconds $SmokeWaitIntervalSeconds
}

# =============================================================================
# ФАЗА 5b: Сводка smoke-namespace
# =============================================================================
# Показываем все ресурсы в namespace smoke-tests.
# Это подтверждает ученику, что всё работает: Deployment, Service, Job, Pods.
Write-Host ">>> [post-bootstrap] Фаза 5b/7: Сводка smoke-namespace..."
& vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get all -n smoke-tests -o wide"

# =============================================================================
# ФАЗА 6: Установка Dashboard
# =============================================================================
# Только после успешного smoke-теста ставим Dashboard.
# install-dashboard.sh:
#   - Устанавливает Helm (если нужен)
#   - Скачивает и устанавливает Dashboard chart
#   - Настраивает NodePort 30443
#   - Создаёт admin-user ServiceAccount
#   - Выводит токен для входа
Write-Host ">>> [post-bootstrap] Фаза 6/7: Установка Dashboard..."
& vagrant ssh k8s-master -c "sudo bash /vagrant/scripts/install-dashboard.sh"

# =============================================================================
# ФАЗА 7: Экспорт kubeconfig для Windows-хоста
# =============================================================================
# export-host-kubeconfig.ps1:
#   1. Забирает /etc/kubernetes/admin.conf с master-ноды
#   2. Заменяет адрес API на https://127.0.0.1:6443 (проброшенный порт)
#   3. Убирает certificate-authority-data
#   4. Добавляет insecure-skip-tls-verify: true
#   5. Сохраняет в kubeconfig-stage1.yaml
#
# После этого можно использовать kubectl прямо из Windows PowerShell.
Write-Host ">>> [post-bootstrap] Фаза 7/7: Экспорт kubeconfig для Windows..."
& powershell.exe -ExecutionPolicy Bypass -File $hostKubeconfigScript -OutputPath $hostKubeconfigPath

# =============================================================================
# ФИНАЛЬНЫЕ ПОДСКАЗКИ
# =============================================================================
# Выводим инструкции для ученика, как пользоваться кластером.
Write-Host ""
Write-Host "========================================================"
Write-Host "  STAGE 1 ГОТОВ!"
Write-Host "========================================================"
Write-Host ""
Write-Host "  Dashboard: https://localhost:${DASHBOARD_NODEPORT}"
Write-Host "  (Токен был выведен выше — скопируй его)"
Write-Host ""
Write-Host "  kubectl из Windows PowerShell:"
Write-Host ('    $env:KUBECONFIG = "{0}"' -f $hostKubeconfigPath)
Write-Host ""
Write-Host "  Или используй helper в текущей сессии:"
Write-Host "    . .\scripts\use-stage1-kubectl.ps1"
Write-Host ""
Write-Host "  Проверка:"
Write-Host "    kubectl get nodes -o wide"
Write-Host "    kubectl get pods -A -o wide"
Write-Host "========================================================"

Pop-Location
