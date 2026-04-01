@echo off
setlocal EnableDelayedExpansion

rem ============================================================================
rem Stage 1 full launcher
rem ============================================================================
rem This file is intentionally ASCII-only because cmd.exe can break on Unicode
rem characters depending on console code page and file encoding.
rem
rem What it does:
rem   1. checks Vagrant and VirtualBox
rem   2. checks that it runs from stage1
rem   3. checks cluster state (skip if already ready)
rem   4. runs vagrant up (only if needed)
rem   5. runs post-bootstrap finalization (only if needed)
rem   6. prints what to open and what to verify in Dashboard
rem ============================================================================

echo.
echo ============================================================
echo   Stage 1: full training cluster launch
echo ============================================================
echo.

where vagrant >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Vagrant not found.
    echo Install Vagrant and run launch.bat again:
    echo https://developer.hashicorp.com/vagrant/downloads
    echo.
    pause
    exit /b 1
)

echo [OK] Vagrant found:
vagrant --version
echo.

where VBoxManage >nul 2>&1
if errorlevel 1 (
    if exist "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" (
        set "PATH=%PATH%;C:\Program Files\Oracle\VirtualBox"
    ) else (
        echo [ERROR] VirtualBox not found.
        echo Install VirtualBox and run launch.bat again:
        echo https://www.virtualbox.org/wiki/Downloads
        echo.
        pause
        exit /b 1
    )
)

echo [OK] VirtualBox found:
VBoxManage --version
echo.

if not exist "Vagrantfile" (
    echo [ERROR] Vagrantfile not found in current directory.
    echo Current directory: %CD%
    echo Run launch.bat from K:\repositories\git\ipr\crm\stage1
    echo.
    pause
    exit /b 1
)

if not exist "scripts\run-post-bootstrap.ps1" (
    echo [ERROR] scripts\run-post-bootstrap.ps1 not found.
    echo Stage1 directory looks incomplete.
    echo.
    pause
    exit /b 1
)

echo [OK] Stage1 files found.
echo.

rem ============================================================================
rem Check: are there already running VMs for this stage1?
rem ============================================================================
echo ------------------------------------------------------------
echo [PRE-CHECK] Detecting current cluster state
echo ------------------------------------------------------------
echo.

set "VM_STATE=missing"
set "VAGRANT_STATE=missing"

rem Check if .vagrant/machines directory exists (Vagrant session state)
if exist ".vagrant\machines\k8s-master" (
    set "VAGRANT_STATE=present"
)

rem Check VM states in VirtualBox
for %%M in (k8s-master k8s-worker1 k8s-worker2) do (
    VBoxManage showvminfo "%%M" --machinereadable 2>nul | findstr /C:"VMState=" >nul
    if not errorlevel 1 (
        set "VM_STATE=running"
    )
)

rem Check if the cluster is already fully ready by querying the API
set "CLUSTER_READY=no"
if "%VM_STATE%"=="running" (
    echo   VMs are running, checking cluster API...
    vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes --no-headers 2>/dev/null" > "%TEMP%\stage1-nodes.txt" 2>nul
    if not errorlevel 1 (
        findstr /C:"Ready" "%TEMP%\stage1-nodes.txt" >nul
        if not errorlevel 1 (
            rem Check if smoke-test passed
            vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get job nginx-smoke-check -n smoke-tests -o jsonpath='{.status.succeeded}' 2>/dev/null" > "%TEMP%\stage1-smoke.txt" 2>nul
            set /p SMOKE_RESULT=<"%TEMP%\stage1-smoke.txt"
            if "!SMOKE_RESULT!"=="1" (
                rem Check if Dashboard is installed
                vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get namespace kubernetes-dashboard 2>/dev/null" >nul 2>&1
                if not errorlevel 1 (
                    set "CLUSTER_READY=yes"
                )
            )
        )
    )
    del "%TEMP%\stage1-nodes.txt" 2>nul
    del "%TEMP%\stage1-smoke.txt" 2>nul
)

if "%CLUSTER_READY%"=="yes" (
    echo.
    echo ============================================================
    echo   Cluster is already fully ready!
    echo ============================================================
    echo.
    echo   All 3 nodes: Ready
    echo   Smoke-test: passed
    echo   Dashboard: installed
    echo.
    echo   Opening Dashboard at: https://localhost:30443
    echo.

    rem Show dashboard token from saved file
    if exist "dashboard-token.txt" (
        echo   Token from dashboard-token.txt:
        type "dashboard-token.txt"
        echo.
    ) else (
        echo   Generating fresh token...
        vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
        echo.
    )

    echo   Useful commands:
    echo     vagrant status
    echo     vagrant ssh k8s-master
    echo     vagrant halt
    echo     vagrant destroy -f
    echo.
    echo   To open Dashboard: https://localhost:30443
    echo.
    pause
    exit /b 0
)

rem ============================================================================
rem Check for orphan VMs from previous stage1 clusters
rem ============================================================================
if "%VM_STATE%"=="running" (
    echo   VMs are running but cluster is not fully ready.
    echo   Continuing with post-bootstrap...
    echo.
) else (
    if "%VAGRANT_STATE%"=="present" (
        echo   Vagrant state found but VMs may not be running.
        echo   Running vagrant up to start/resume VMs...
        echo.
    ) else (
        echo   No existing cluster found. Fresh start.
        echo.

        rem Check for orphan VMs from previous stage1 runs
        echo   Checking for orphan VMs from previous runs...
        for /f "tokens=*" %%L in ('VBoxManage list vms 2^>nul') do (
            echo %%L | findstr /C:"k8s-stage1-" >nul
            if not errorlevel 1 (
                echo.
                echo   [WARNING] Found orphan VM: %%L
                echo   This may be from a previous stage1 cluster.
                echo   Consider running: vagrant destroy -f
                echo   Or manually remove it in VirtualBox.
                echo.
            )
        )
    )
)

echo ------------------------------------------------------------
echo [STEP 1/2] Running vagrant up
echo ------------------------------------------------------------
echo This creates 3 VMs and performs the base cluster bootstrap.
echo First run can take 15-30 minutes.
echo.

vagrant up
if errorlevel 1 (
    echo.
    echo [ERROR] vagrant up failed.
    echo.
    echo Next checks:
    echo   vagrant status
    echo   vagrant destroy -f
    echo   .\launch.bat
    echo.
    echo See docs\troubleshooting.md
    echo.
    pause
    exit /b 1
)

echo.
echo ------------------------------------------------------------
echo [STEP 2/2] Running post-bootstrap finalization
echo ------------------------------------------------------------
echo This will verify 3 nodes, finalize Calico, run smoke-test,
echo and install Dashboard at the very end.
echo.

powershell.exe -ExecutionPolicy Bypass -File ".\scripts\run-post-bootstrap.ps1"
if errorlevel 1 (
    echo.
    echo [ERROR] Post-bootstrap finalization failed.
    echo.
    echo Useful checks:
    echo   vagrant status
    echo   vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"
    echo   vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -A -o wide"
    echo.
    echo See docs\troubleshooting.md
    echo.
    pause
    exit /b 1
)

echo.
echo ------------------------------------------------------------
echo Final node check
echo ------------------------------------------------------------
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"
echo.

echo ============================================================
echo   Stage 1 completed successfully
echo ============================================================
echo.
echo Open in browser:
echo   https://localhost:30443
echo.

rem Show dashboard token from saved file
if exist "dashboard-token.txt" (
    echo Dashboard token (from dashboard-token.txt):
    type "dashboard-token.txt"
    echo.
)

echo Then verify:
echo   1. 3 nodes in Dashboard / Nodes
echo   2. namespace smoke-tests
echo   3. nginx-smoke deployment
echo   4. nginx-smoke-check job
echo.
echo Host kubectl is also prepared:
echo   set KUBECONFIG=K:\repositories\git\ipr\crm\stage1\kubeconfig-stage1.yaml
echo   PowerShell: . .\scripts\use-stage1-kubectl.ps1
echo   kubectl get nodes -o wide
echo   kubectl get pods -A -o wide
echo.
echo Useful commands:
echo   vagrant status
echo   vagrant ssh k8s-master
echo   vagrant destroy -f
echo.
pause
