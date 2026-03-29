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
rem   3. runs vagrant up
rem   4. runs post-bootstrap finalization
rem   5. prints what to open and what to verify in Dashboard
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
