; =============================================================================
; k8s-lab.nsi — NSIS-установщик Kubernetes Cluster Lab (расширенная версия)
; =============================================================================
;
; КАК СКОМПИЛИРОВАТЬ:
;   makensis k8s-lab.nsi   →   k8s-lab-setup.exe
;
; СТРУКТУРА ВИЗАРДА:
;   1. Приветствие
;   2. Проверка зависимостей
;   3. Папка установки
;   4. Настройка Master-ноды (CPU, RAM, HDD)
;   5. Настройка сети (подсеть, маска, мост, порты)
;   6. Настройка Worker-нод (CPU, RAM, HDD, количество)
;   7. Сводка настроек
;   8. Установка (поэтапный прогрессбар)
;   9. Финиш (токен, информация)
; =============================================================================

; === 1. ЗАГОЛОВОК ============================================================

Name "Kubernetes Cluster Lab"
OutFile "k8s-lab-setup.exe"
InstallDir "$DOCUMENTS\k8s-lab"
InstallDirRegKey HKCU "Software\K8sLab" "InstallDir"
SetCompressor /SOLID lzma

VIProductVersion "2.0.0.0"
VIAddVersionKey "ProductName" "Kubernetes Cluster Lab"
VIAddVersionKey "ProductVersion" "2.0.0"
VIAddVersionKey "FileVersion" "2.0.0.0"
VIAddVersionKey "FileDescription" "Kubernetes lab installer for Windows"
VIAddVersionKey "LegalCopyright" "MIT License"

; === 2. ПОДКЛЮЧЕНИЕ БИБЛИОТЕК ================================================

!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"
!include "FileFunc.nsh"

; === 3. НАСТРОЙКИ ВНЕШНЕГО ВИДА MUI =========================================

!define MUI_ABORTWARNING

; === 4. ПЕРЕМЕННЫЕ ===========================================================

; Общие
Var ClusterPrefix

; Master-нода
Var MasterCpu
Var MasterRam
Var MasterHdd

; Сеть
Var SubnetPrefix
Var SubnetMask
Var BridgeAdapter
Var SecondAdapter
Var MasterSshPort
Var MasterApiPort
Var MasterDashPort

; Worker-ноды
Var WorkerCount
Var WorkerCpu
Var WorkerRam
Var WorkerHdd

; Smoke-тест
Var RunSmokeTest

; Дескрипторы элементов диалогов
Var hDialog
Var hDepsDialog

; Master
Var hPrefixField
Var hMasterCpuField
Var hMasterRamField
Var hMasterHddField

; Network
Var hSubnetField
Var hMaskCombo
Var hBridgeCombo
Var hSecondAdapterCombo
Var hMasterPortField
Var hApiPortField
Var hDashPortField

; Worker
Var hWorkerCountField
Var hWorkerCpuField
Var hWorkerRamField
Var hWorkerHddField

; Smoke
Var hSmokeCheckbox

; Summary
; (no extra handles needed)

; Finish
Var hFinishDialog

; === 5. СТРАНИЦЫ ВИЗАРДА =====================================================

; Страница 1: Приветствие
!insertmacro MUI_PAGE_WELCOME

; Страница 2: Проверка зависимостей
Page custom DepsPageCreate DepsPageLeave

; Страница 3: Папка установки
!insertmacro MUI_PAGE_DIRECTORY

; Страница 4: Настройка Master-ноды
Page custom MasterPageCreate MasterPageLeave

; Страница 5: Настройка сети
Page custom NetworkPageCreate NetworkPageLeave

; Страница 6: Настройка Worker-нод
Page custom WorkerPageCreate WorkerPageLeave

; Страница 7: Smoke-тест (опционально)
Page custom SmokePageCreate SmokePageLeave

; Страница 8: Сводка настроек
Page custom SummaryPageCreate SummaryPageLeave

; Страница 9: Прогресс установки
!insertmacro MUI_PAGE_INSTFILES

; Страница 10: Финиш
Page custom FinishPageCreate

; Деинсталлятор
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; === 6. ЯЗЫКИ =================================================================

!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

; === 7. СТРОКИ ИНТЕРФЕЙСА =====================================================

!include "lang\russian.nsh"
!include "lang\english.nsh"

; === 8. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==============================================

Function CheckPortInUse
  ; $0 — порт для проверки
  ; Возвращает: $1 = "0" если свободен, "1" если занят
  nsExec::ExecToStack 'cmd.exe /C "netstat -ano | findstr :$0 | findstr LISTENING"'
  Pop $1
  ${If} $1 == "0"
    StrCpy $1 "1"
  ${Else}
    StrCpy $1 "0"
  ${EndIf}
FunctionEnd

Function GetBridgeAdapters
  ; Заполняет список доступных сетевых адаптеров для моста
  nsExec::ExecToStack 'cmd.exe /C "VBoxManage list bridgedifs"'
  Pop $0
  Pop $1
FunctionEnd

; === 9. СТРАНИЦА: ПРОВЕРКА ЗАВИСИМОСТЕЙ ======================================

Function DepsPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_DEPS_TITLE)" "$(STR_DEPS_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDepsDialog
  ${If} $hDepsDialog == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 10 5 370 14 "$(STR_DEPS_SUBTITLE):"

  ; Vagrant
  ${NSD_CreateLabel} 10 28 200 14 "$(STR_DEPS_VAGRANT):"
  nsExec::ExecToStack 'cmd.exe /C "vagrant --version"'
  Pop $0
  Pop $1
  ${If} $0 == "0"
    ${NSD_CreateLabel} 215 28 155 14 "$(STR_DEPS_OK)"
  ${Else}
    ${NSD_CreateLabel} 215 28 155 14 "$(STR_DEPS_MISSING)"
  ${EndIf}

  ; VirtualBox
  ${NSD_CreateLabel} 10 48 200 14 "$(STR_DEPS_VBOX):"
  nsExec::ExecToStack 'cmd.exe /C "VBoxManage --version"'
  Pop $2
  Pop $3
  ${If} $2 == "0"
    ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_OK)"
  ${Else}
    ${If} ${FileExists} "$PROGRAMFILES\Oracle\VirtualBox\VBoxManage.exe"
      ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_OK)"
      StrCpy $2 "0"
    ${ElseIf} ${FileExists} "$PROGRAMFILES64\Oracle\VirtualBox\VBoxManage.exe"
      ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_OK)"
      StrCpy $2 "0"
    ${Else}
      ReadRegStr $4 HKLM "SOFTWARE\Oracle\VirtualBox" "InstallDir"
      ${If} $4 != ""
        ${If} ${FileExists} "$4\VBoxManage.exe"
          ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_OK)"
          StrCpy $2 "0"
        ${Else}
          ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_MISSING)"
        ${EndIf}
      ${Else}
        ReadRegStr $4 HKLM "SOFTWARE\WOW6432Node\Oracle\VirtualBox" "InstallDir"
        ${If} $4 != ""
          ${If} ${FileExists} "$4\VBoxManage.exe"
            ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_OK)"
            StrCpy $2 "0"
          ${Else}
            ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_MISSING)"
          ${EndIf}
        ${Else}
          ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_MISSING)"
        ${EndIf}
      ${EndIf}
    ${EndIf}
  ${EndIf}

  ${NSD_CreateLabel} 10 78 370 30 "$(STR_DEPS_HINT)"

  nsDialogs::Show
FunctionEnd

Function DepsPageLeave
  nsExec::ExecToStack 'cmd.exe /C "vagrant --version"'
  Pop $0
  Pop $1
  ${If} $0 != "0"
    MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_DEPS_WARN_VAGRANT)" IDYES +2
    Abort
  ${EndIf}

  nsExec::ExecToStack 'cmd.exe /C "VBoxManage --version"'
  Pop $0
  Pop $1
  ${If} $0 != "0"
    ${If} ${FileExists} "$PROGRAMFILES\Oracle\VirtualBox\VBoxManage.exe"
    ${ElseIf} ${FileExists} "$PROGRAMFILES64\Oracle\VirtualBox\VBoxManage.exe"
    ${Else}
      ReadRegStr $2 HKLM "SOFTWARE\Oracle\VirtualBox" "InstallDir"
      ${If} $2 != ""
        ${If} ${FileExists} "$2\VBoxManage.exe"
        ${Else}
          MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_DEPS_WARN_VBOX)" IDYES +2
          Abort
        ${EndIf}
      ${Else}
        MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_DEPS_WARN_VBOX)" IDYES +2
        Abort
      ${EndIf}
    ${EndIf}
  ${EndIf}
FunctionEnd

; === 10. СТРАНИЦА: НАСТРОЙКА MASTER-НОДЫ =====================================

Function MasterPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_MASTER_TITLE)" "$(STR_MASTER_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $ClusterPrefix == ""
    StrCpy $ClusterPrefix "lab-k8s"
  ${EndIf}
  ${If} $MasterCpu == ""
    StrCpy $MasterCpu "2"
  ${EndIf}
  ${If} $MasterRam == ""
    StrCpy $MasterRam "2048"
  ${EndIf}
  ${If} $MasterHdd == ""
    StrCpy $MasterHdd "30"
  ${EndIf}

  ${NSD_CreateLabel} 10 10 200 14 "$(STR_MASTER_PREFIX):"
  ${NSD_CreateText}  215 8 150 16 "$ClusterPrefix"
  Pop $hPrefixField

  ${NSD_CreateLabel} 10 32 200 14 "$(STR_MASTER_CPU):"
  ${NSD_CreateText}  215 30 150 16 "$MasterCpu"
  Pop $hMasterCpuField

  ${NSD_CreateLabel} 10 54 200 14 "$(STR_MASTER_RAM):"
  ${NSD_CreateText}  215 52 150 16 "$MasterRam"
  Pop $hMasterRamField

  ${NSD_CreateLabel} 10 76 200 14 "$(STR_MASTER_HDD):"
  ${NSD_CreateText}  215 74 150 16 "$MasterHdd"
  Pop $hMasterHddField

  ${NSD_CreateLabel} 10 106 370 20 "$(STR_MASTER_HINT)"

  nsDialogs::Show
FunctionEnd

Function MasterPageLeave
  ${NSD_GetText} $hPrefixField    $ClusterPrefix
  ${NSD_GetText} $hMasterCpuField $MasterCpu
  ${NSD_GetText} $hMasterRamField $MasterRam
  ${NSD_GetText} $hMasterHddField $MasterHdd

  StrLen $0 $ClusterPrefix
  ${If} $0 < 2
    MessageBox MB_OK|MB_ICONEXCLAMATION "Префикс слишком короткий (минимум 2 символа)."
    Abort
  ${EndIf}

  IntCmp $MasterCpu 1 +3
  IntCmp $MasterCpu 8 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "CPU: от 1 до 8."
  Abort

  IntCmp $MasterRam 512 +3
  IntCmp $MasterRam 16384 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "RAM: от 512 до 16384 МБ."
  Abort
FunctionEnd

; === 11. СТРАНИЦА: НАСТРОЙКА СЕТИ ============================================

Function NetworkPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_NETWORK_TITLE)" "$(STR_NETWORK_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $SubnetPrefix == ""
    StrCpy $SubnetPrefix "192.168.56"
  ${EndIf}
  ${If} $SubnetMask == ""
    StrCpy $SubnetMask "255.255.255.0"
  ${EndIf}
  ${If} $MasterSshPort == ""
    StrCpy $MasterSshPort "2232"
  ${EndIf}
  ${If} $MasterApiPort == ""
    StrCpy $MasterApiPort "6443"
  ${EndIf}
  ${If} $MasterDashPort == ""
    StrCpy $MasterDashPort "30443"
  ${EndIf}

  ${NSD_CreateLabel} 10 10 200 14 "$(STR_NETWORK_SUBNET):"
  ${NSD_CreateText}  215 8 150 16 "$SubnetPrefix"
  Pop $hSubnetField

  ${NSD_CreateLabel} 10 32 200 14 "$(STR_NETWORK_MASK):"
  ${NSD_CreateComboBox} 215 30 150 80
  Pop $hMaskCombo
  SendMessage $hMaskCombo ${CB_ADDSTRING} 0 "STR:255.255.255.0"
  SendMessage $hMaskCombo ${CB_ADDSTRING} 0 "STR:255.255.0.0"
  SendMessage $hMaskCombo ${CB_ADDSTRING} 0 "STR:255.0.0.0"
  SendMessage $hMaskCombo ${CB_SELECTSTRING} -1 "STR:$SubnetMask"

  ${NSD_CreateLabel} 10 54 200 14 "$(STR_NETWORK_BRIDGE):"
  ${NSD_CreateText}  215 52 150 16 "$BridgeAdapter"
  Pop $hBridgeCombo

  ${NSD_CreateLabel} 10 76 200 14 "$(STR_NETWORK_ADAPTER):"
  ${NSD_CreateComboBox} 215 74 150 80
  Pop $hSecondAdapterCombo
  SendMessage $hSecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NONE)"
  SendMessage $hSecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_BRIDGE)"
  SendMessage $hSecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NAT)"
  ${If} $SecondAdapter == ""
    StrCpy $SecondAdapter "$(STR_NETWORK_ADAPTER_NONE)"
  ${EndIf}
  SendMessage $hSecondAdapterCombo ${CB_SELECTSTRING} -1 "STR:$SecondAdapter"

  ${NSD_CreateLabel} 10 98 200 14 "$(STR_NETWORK_MASTER_PORT):"
  ${NSD_CreateText}  215 96 150 16 "$MasterSshPort"
  Pop $hMasterPortField

  ${NSD_CreateLabel} 10 120 200 14 "$(STR_NETWORK_API_PORT):"
  ${NSD_CreateText}  215 118 150 16 "$MasterApiPort"
  Pop $hApiPortField

  ${NSD_CreateLabel} 10 142 200 14 "$(STR_NETWORK_DASH_PORT):"
  ${NSD_CreateText}  215 140 150 16 "$MasterDashPort"
  Pop $hDashPortField

  ${NSD_CreateLabel} 10 166 370 20 "$(STR_NETWORK_HINT)"

  nsDialogs::Show
FunctionEnd

Function NetworkPageLeave
  ${NSD_GetText} $hSubnetField      $SubnetPrefix
  ${NSD_GetText} $hMaskCombo        $SubnetMask
  ${NSD_GetText} $hBridgeCombo      $BridgeAdapter
  ${NSD_GetText} $hSecondAdapterCombo $SecondAdapter
  ${NSD_GetText} $hMasterPortField  $MasterSshPort
  ${NSD_GetText} $hApiPortField     $MasterApiPort
  ${NSD_GetText} $hDashPortField    $MasterDashPort

  ; Валидация подсети
  StrLen $0 $SubnetPrefix
  ${If} $0 < 7
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_INVALID_SUBNET)"
    Abort
  ${EndIf}

  ; Проверка портов
  Push $MasterSshPort
  Call CheckPortInUse
  Pop $1
  ${If} $1 == "1"
    StrCpy $0 $MasterSshPort
    MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_NETWORK_PORT_WARN)" IDYES +2
    Abort
  ${EndIf}

  Push $MasterApiPort
  Call CheckPortInUse
  Pop $1
  ${If} $1 == "1"
    StrCpy $0 $MasterApiPort
    MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_NETWORK_PORT_WARN)" IDYES +2
    Abort
  ${EndIf}

  Push $MasterDashPort
  Call CheckPortInUse
  Pop $1
  ${If} $1 == "1"
    StrCpy $0 $MasterDashPort
    MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_NETWORK_PORT_WARN)" IDYES +2
    Abort
  ${EndIf}
FunctionEnd

; === 12. СТРАНИЦА: НАСТРОЙКА WORKER-НОД ======================================

Function WorkerPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_WORKER_TITLE)" "$(STR_WORKER_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $WorkerCount == ""
    StrCpy $WorkerCount "2"
  ${EndIf}
  ${If} $WorkerCpu == ""
    StrCpy $WorkerCpu "2"
  ${EndIf}
  ${If} $WorkerRam == ""
    StrCpy $WorkerRam "2048"
  ${EndIf}
  ${If} $WorkerHdd == ""
    StrCpy $WorkerHdd "30"
  ${EndIf}

  ${NSD_CreateLabel} 10 10 200 14 "$(STR_WORKER_COUNT):"
  ${NSD_CreateText}  215 8 150 16 "$WorkerCount"
  Pop $hWorkerCountField

  ${NSD_CreateLabel} 10 32 200 14 "$(STR_WORKER_CPU):"
  ${NSD_CreateText}  215 30 150 16 "$WorkerCpu"
  Pop $hWorkerCpuField

  ${NSD_CreateLabel} 10 54 200 14 "$(STR_WORKER_RAM):"
  ${NSD_CreateText}  215 52 150 16 "$WorkerRam"
  Pop $hWorkerRamField

  ${NSD_CreateLabel} 10 76 200 14 "$(STR_WORKER_HDD):"
  ${NSD_CreateText}  215 74 150 16 "$WorkerHdd"
  Pop $hWorkerHddField

  ${NSD_CreateLabel} 10 106 370 20 "$(STR_WORKER_HINT)"

  nsDialogs::Show
FunctionEnd

Function WorkerPageLeave
  ${NSD_GetText} $hWorkerCountField $WorkerCount
  ${NSD_GetText} $hWorkerCpuField   $WorkerCpu
  ${NSD_GetText} $hWorkerRamField   $WorkerRam
  ${NSD_GetText} $hWorkerHddField   $WorkerHdd

  IntCmp $WorkerCount 1 +3
  IntCmp $WorkerCount 4 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "Количество воркеров: от 1 до 4."
  Abort

  IntCmp $WorkerCpu 1 +3
  IntCmp $WorkerCpu 8 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "CPU: от 1 до 8."
  Abort

  IntCmp $WorkerRam 512 +3
  IntCmp $WorkerRam 16384 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "RAM: от 512 до 16384 МБ."
  Abort
FunctionEnd

; === 13. СТРАНИЦА: SMOKE-ТЕСТ ================================================

Function SmokePageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_SMOKE_TITLE)" "$(STR_SMOKE_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${NSD_CreateCheckbox} 10 10 370 20 "$(STR_SMOKE_RUN)"
  Pop $hSmokeCheckbox
  ${If} $RunSmokeTest == ""
    StrCpy $RunSmokeTest "1"
  ${EndIf}
  ${If} $RunSmokeTest == "1"
    ${NSD_Check} $hSmokeCheckbox
  ${Else}
    ${NSD_Uncheck} $hSmokeCheckbox
  ${EndIf}

  ${NSD_CreateLabel} 10 40 370 50 "$(STR_SMOKE_DESC)"

  nsDialogs::Show
FunctionEnd

Function SmokePageLeave
  ${NSD_GetState} $hSmokeCheckbox $RunSmokeTest
FunctionEnd

; === 14. СТРАНИЦА: СВОДКА НАСТРОЕК ===========================================

Function SummaryPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_SUMMARY_TITLE)" "$(STR_SUMMARY_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog

  ${NSD_CreateLabel} 10 5  370 14 "$(STR_SUMMARY_HEADER)"
  ${NSD_CreateLabel} 10 25 160 14 "$(STR_SUMMARY_PREFIX)"
  ${NSD_CreateLabel} 175 25 195 14 "$ClusterPrefix"

  ${NSD_CreateLabel} 10 42 160 14 "$(STR_SUMMARY_MASTER)"
  ${NSD_CreateLabel} 175 42 195 14 "CPU=$MasterCpu, RAM=$MasterRam MB, HDD=$MasterHdd GB"

  ${NSD_CreateLabel} 10 59 160 14 "$(STR_SUMMARY_WORKERS)"
  ${NSD_CreateLabel} 175 59 195 14 "$WorkerCount"

  ${NSD_CreateLabel} 10 76 160 14 "$(STR_SUMMARY_WORKER)"
  ${NSD_CreateLabel} 175 76 195 14 "CPU=$WorkerCpu, RAM=$WorkerRam MB, HDD=$WorkerHdd GB"

  ${NSD_CreateLabel} 10 93 160 14 "$(STR_SUMMARY_SUBNET)"
  ${NSD_CreateLabel} 175 93 195 14 "$SubnetPrefix.0/24 ($SubnetMask)"

  ${NSD_CreateLabel} 10 110 160 14 "$(STR_SUMMARY_BRIDGE)"
  ${NSD_CreateLabel} 175 110 195 14 "$BridgeAdapter ($SecondAdapter)"

  ${NSD_CreateLabel} 10 127 160 14 "$(STR_SUMMARY_PORTS)"
  ${NSD_CreateLabel} 175 127 195 14 "SSH=$MasterSshPort, API=$MasterApiPort, Dash=$MasterDashPort"

  ${NSD_CreateLabel} 10 144 160 14 "$(STR_SUMMARY_DIR)"
  ${NSD_CreateLabel} 175 144 195 14 "$INSTDIR"

  ${NSD_CreateLabel} 10 161 160 14 "$(STR_SUMMARY_SMOKE)"
  ${If} $RunSmokeTest == "1"
    ${NSD_CreateLabel} 175 161 195 14 "$(STR_SMOKE_YES)"
  ${Else}
    ${NSD_CreateLabel} 175 161 195 14 "$(STR_SMOKE_NO)"
  ${EndIf}

  ${NSD_CreateLabel} 10 189 370 20 "$(STR_SUMMARY_NOTE)"

  nsDialogs::Show
FunctionEnd

Function SummaryPageLeave
FunctionEnd

; === 14. СТРАНИЦА: ФИНИШ =====================================================

Function FinishPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_FINISH_TITLE)" "$(STR_FINISH_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hFinishDialog
  ${If} $hFinishDialog == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 10 5 370 14 "$(STR_FINISH_TEXT)"

  ${NSD_CreateLabel} 10 25 160 14 "$(STR_FINISH_DASHBOARD)"
  ${NSD_CreateLabel} 175 25 195 14 "$(STR_FINISH_DASHBOARD_URL)"

  ${NSD_CreateLabel} 10 42 160 14 "$(STR_FINISH_TOKEN)"
  ${NSD_CreateLabel} 175 42 195 14 "$(STR_FINISH_TOKEN_FILE)"

  ${NSD_CreateLabel} 10 59 160 14 "$(STR_FINISH_KUBECONFIG)"
  ${NSD_CreateLabel} 175 59 195 14 "$(STR_FINISH_KUBECONFIG_FILE)"

  ${NSD_CreateLabel} 10 76 160 14 "$(STR_FINISH_NODES)"
  ${NSD_CreateLabel} 175 76 195 14 "1 master + $WorkerCount worker(s)"

  ${NSD_CreateLabel} 10 106 370 30 "Открой $INSTDIR для работы с кластером.$\nИспользуй kubectl из Windows или Dashboard в браузере."

  nsDialogs::Show
FunctionEnd

; === 15. СЕКЦИИ УСТАНОВКИ (каждая = отдельный этап прогрессбара) =============

Section "Копирование файлов" SecCopyFiles
  SetOutPath "$INSTDIR"

  File "..\..\.gitignore"
  File "..\..\stage2\Vagrantfile"
  CreateDirectory "$INSTDIR\scripts"
  File /oname=scripts\common.sh "..\..\stage2\scripts\common.sh"
  File /oname=scripts\master.sh "..\..\stage2\scripts\master.sh"
  File /oname=scripts\worker.sh "..\..\stage2\scripts\worker.sh"
  File /oname=scripts\finalize-cluster.sh "..\..\stage2\scripts\finalize-cluster.sh"
  File /oname=scripts\install-dashboard.sh "..\..\stage2\scripts\install-dashboard.sh"
  File /oname=scripts\generate-node-key.ps1 "..\..\stage2\scripts\generate-node-key.ps1"
  File /oname=scripts\cleanup-node-key.ps1  "..\..\stage2\scripts\cleanup-node-key.ps1"
  File /oname=scripts\run-post-bootstrap.ps1 "..\..\stage2\scripts\run-post-bootstrap.ps1"
  File /oname=scripts\export-host-kubeconfig.ps1 "..\..\stage2\scripts\export-host-kubeconfig.ps1"
  File /oname=scripts\use-stage2-kubectl.ps1 "..\..\stage2\scripts\use-stage2-kubectl.ps1"

  DetailPrint "$(STR_INSTALL_COPY)"
SectionEnd

Section "Создание конфигурации" SecCreateConfig
  FileOpen $0 "$INSTDIR\.env" w
  FileWrite $0 "# Kubernetes Cluster Lab — конфигурация$\r$\n"
  FileWrite $0 "# Создано NSIS-визардом v2$\r$\n$\r$\n"
  FileWrite $0 "CLUSTER_PREFIX=$ClusterPrefix$\r$\n"
  FileWrite $0 "MASTER_VM_NAME=$ClusterPrefix-master$\r$\n"
  FileWrite $0 "MASTER_HOSTNAME=$ClusterPrefix-master$\r$\n$\r$\n"
  FileWrite $0 "VM_BOX=bento/ubuntu-24.04$\r$\n"
  FileWrite $0 "VM_CPUS=$MasterCpu$\r$\n"
  FileWrite $0 "VM_MEMORY_MB=$MasterRam$\r$\n"
  FileWrite $0 "VM_DISK_GB=$MasterHdd$\r$\n"
  FileWrite $0 "VM_BOOT_TIMEOUT=600$\r$\n"
  FileWrite $0 "WORKER_COUNT=$WorkerCount$\r$\n"
  FileWrite $0 "WORKER_CPUS=$WorkerCpu$\r$\n"
  FileWrite $0 "WORKER_MEMORY_MB=$WorkerRam$\r$\n"
  FileWrite $0 "WORKER_DISK_GB=$WorkerHdd$\r$\n$\r$\n"
  FileWrite $0 "PRIVATE_NETWORK_PREFIX=$SubnetPrefix$\r$\n"
  FileWrite $0 "PRIVATE_NETWORK_GATEWAY=$SubnetPrefix.1$\r$\n"
  FileWrite $0 "MASTER_PRIVATE_IP=$SubnetPrefix.10$\r$\n"
  FileWrite $0 "MASTER_SSH_PORT=$MasterSshPort$\r$\n"
  FileWrite $0 "MASTER_API_PORT=$MasterApiPort$\r$\n"
  FileWrite $0 "MASTER_DASHBOARD_PORT=$MasterDashPort$\r$\n"
  FileWrite $0 "SUBNET_MASK=$SubnetMask$\r$\n"
  FileWrite $0 "BRIDGE_ADAPTER=$BridgeAdapter$\r$\n"
  FileWrite $0 "SECOND_ADAPTER=$SecondAdapter$\r$\n$\r$\n"
  FileWrite $0 "WORKER1_VM_NAME=$ClusterPrefix-worker1$\r$\n"
  FileWrite $0 "WORKER1_HOSTNAME=$ClusterPrefix-worker1$\r$\n"
  FileWrite $0 "WORKER1_PRIVATE_IP=$SubnetPrefix.11$\r$\n"
  FileWrite $0 "WORKER1_SSH_PORT=2242$\r$\n$\r$\n"
  FileWrite $0 "WORKER2_VM_NAME=$ClusterPrefix-worker2$\r$\n"
  FileWrite $0 "WORKER2_HOSTNAME=$ClusterPrefix-worker2$\r$\n"
  FileWrite $0 "WORKER2_PRIVATE_IP=$SubnetPrefix.12$\r$\n"
  FileWrite $0 "WORKER2_SSH_PORT=2252$\r$\n$\r$\n"
  FileWrite $0 "KUBERNETES_VERSION=1.34$\r$\n"
  FileWrite $0 "POD_CIDR=10.244.0.0/16$\r$\n"
  FileClose $0

  DetailPrint "$(STR_INSTALL_CONFIG)"
SectionEnd

Section "Генерация SSH-ключей" SecGenKeys
  CreateDirectory "$INSTDIR\.vagrant\node-keys"

  nsExec::ExecToLog 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\scripts\generate-node-key.ps1" -NodeName "$ClusterPrefix-master" -KeyDirectory "$INSTDIR\.vagrant\node-keys"'
  Pop $0
  nsExec::ExecToLog 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\scripts\generate-node-key.ps1" -NodeName "$ClusterPrefix-worker1" -KeyDirectory "$INSTDIR\.vagrant\node-keys"'
  Pop $0
  nsExec::ExecToLog 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\scripts\generate-node-key.ps1" -NodeName "$ClusterPrefix-worker2" -KeyDirectory "$INSTDIR\.vagrant\node-keys"'
  Pop $0

  DetailPrint "$(STR_INSTALL_KEYS)"
SectionEnd

Section "Запуск виртуальных машин" SecVagrantUp
  UserInfo::GetAccountType
  Pop $0
  ${If} $0 != "Admin"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_NO_ADMIN)"
    Abort
  ${EndIf}

  DetailPrint "$(STR_INSTALL_VAGRANT_UP)"
  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant up"'
  Pop $0

  ${If} $0 != "0"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_VAGRANT_FAIL)"
    Abort
  ${EndIf}
SectionEnd

Section "Настройка Kubernetes" SecBootstrap
  DetailPrint "$(STR_INSTALL_BOOTSTRAP)"

  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl -n kubernetes-dashboard create token admin-user --duration=168h" > "$INSTDIR\dashboard-token.txt" 2>&1"'
  Pop $0

  DetailPrint "$(STR_INSTALL_TOKEN)"
SectionEnd

Section "Завершение" SecFinalize
  DetailPrint "$(STR_INSTALL_DONE)"

  WriteRegStr HKCU "Software\K8sLab" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "DisplayName" "Kubernetes Cluster Lab"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "DisplayVersion" "2.0.0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

; === 16. ДЕИНСТАЛЛЯТОР =======================================================

Section "Uninstall"
  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant destroy -f"'

  RMDir /r "$INSTDIR\.vagrant"
  RMDir /r "$INSTDIR\scripts"
  Delete "$INSTDIR\.env"
  Delete "$INSTDIR\.gitignore"
  Delete "$INSTDIR\Vagrantfile"
  Delete "$INSTDIR\dashboard-token.txt"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\uninstall.exe"

  DeleteRegKey HKCU "Software\K8sLab"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab"

  RMDir "$INSTDIR"
SectionEnd
