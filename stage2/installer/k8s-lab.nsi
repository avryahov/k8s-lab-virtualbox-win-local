; =============================================================================
; k8s-lab.nsi — NSIS-установщик Kubernetes Cluster Lab (расширенная версия v3)
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
;   5. Настройка сети Master (подсеть, маска, мост, порты)
;   6. Настройка Worker-нод (CPU, RAM, HDD, количество)
;   7. Выбор режима сетевой конфигурации Worker
;   8a. Общая сеть для всех Worker
;   8b. Индивидуальная сеть для каждого Worker (динамические страницы)
;   9. Smoke-тест (опционально)
;  10. Сводка настроек
;  11. Установка (поэтапный прогрессбар)
;  12. Результаты smoke-теста (если включён)
;  13. Финиш
; =============================================================================

; === 1. ЗАГОЛОВОК ============================================================

Name "Kubernetes Cluster Lab"
OutFile "k8s-lab-setup.exe"
InstallDir "$DOCUMENTS\k8s-lab"
InstallDirRegKey HKCU "Software\K8sLab" "InstallDir"
SetCompressor /SOLID lzma

VIProductVersion "3.0.0.0"
VIAddVersionKey "ProductName" "Kubernetes Cluster Lab"
VIAddVersionKey "ProductVersion" "3.0.0"
VIAddVersionKey "FileVersion" "3.0.0.0"
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

; Режим установки
Var InstallMode  ; "quick" или "advanced"

; Состояние чекбоксов "по умолчанию" (1=checked)
Var MasterResDefaults
Var MasterNetDefaults
Var WorkerResDefaults
Var WorkerNetModeDefaults
Var WorkerNetDefaults
Var W1NetDefaults
Var W2NetDefaults
Var W3NetDefaults
Var W4NetDefaults

; Общие
Var ClusterPrefix

; Master-нода (ресурсы)
Var MasterCpu
Var MasterRam
Var MasterHdd

; Master-нода (сеть)
Var MasterSubnetPrefix
Var MasterSubnetMask
Var MasterBridgeAdapter
Var MasterSecondAdapter
Var MasterSshPort
Var MasterApiPort
Var MasterDashPort

; Worker-ноды (ресурсы)
Var WorkerCount
Var WorkerCpu
Var WorkerRam
Var WorkerHdd

; Worker-ноды (режим сети)
Var WorkerNetworkMode  ; "common" или "individual"

; Worker-ноды (общая сеть)
Var WorkerSubnetPrefix
Var WorkerSubnetMask
Var WorkerBridgeAdapter
Var WorkerSecondAdapter
Var WorkerSshPortBase

; Worker-ноды (индивидуальная сеть — до 4 воркеров)
Var W1_SubnetPrefix
Var W1_SubnetMask
Var W1_BridgeAdapter
Var W1_SecondAdapter
Var W1_SshPort

Var W2_SubnetPrefix
Var W2_SubnetMask
Var W2_BridgeAdapter
Var W2_SecondAdapter
Var W2_SshPort

Var W3_SubnetPrefix
Var W3_SubnetMask
Var W3_BridgeAdapter
Var W3_SecondAdapter
Var W3_SshPort

Var W4_SubnetPrefix
Var W4_SubnetMask
Var W4_BridgeAdapter
Var W4_SecondAdapter
Var W4_SshPort

; Smoke-тест
Var RunSmokeTest

; Дескрипторы элементов диалогов
Var hDialog
Var hDepsDialog

; Режим установки
Var hModeQuick
Var hModeAdvanced

; Master (ресурсы)
Var hMasterDefaultsCheck
Var hPrefixField
Var hMasterCpuField
Var hMasterRamField
Var hMasterHddField

; Master (сеть)
Var hMasterNetDefaultsCheck
Var hMasterSubnetField
Var hMasterMaskCombo
Var hMasterBridgeCombo
Var hMasterSecondAdapterCombo
Var hMasterPortField
Var hMasterApiPortField
Var hMasterDashPortField

; Worker (ресурсы)
Var hWorkerDefaultsCheck
Var hWorkerCountField
Var hWorkerCpuField
Var hWorkerRamField
Var hWorkerHddField

; Worker Network Mode
Var hWorkerNetModeDefaultsCheck
Var hWorkerModeCommon
Var hWorkerModeIndividual

; Worker Common Network
Var hWorkerNetDefaultsCheck
Var hWorkerSubnetField
Var hWorkerMaskCombo
Var hWorkerBridgeCombo
Var hWorkerSecondAdapterCombo
Var hWorkerSshPortField

; Worker Individual Network
Var hW1NetDefaultsCheck
Var hW1SubnetField
Var hW1MaskCombo
Var hW1BridgeCombo
Var hW1SecondAdapterCombo
Var hW1SshPortField

Var hW2NetDefaultsCheck
Var hW2SubnetField
Var hW2MaskCombo
Var hW2BridgeCombo
Var hW2SecondAdapterCombo
Var hW2SshPortField

Var hW3NetDefaultsCheck
Var hW3SubnetField
Var hW3MaskCombo
Var hW3BridgeCombo
Var hW3SecondAdapterCombo
Var hW3SshPortField

Var hW4NetDefaultsCheck
Var hW4SubnetField
Var hW4MaskCombo
Var hW4BridgeCombo
Var hW4SecondAdapterCombo
Var hW4SshPortField

; Smoke
Var hSmokeCheckbox
Var SmokeResult
Var SmokeNodesOutput
Var SmokePodsOutput
Var SmokeSvcOutput
Var SmokeJobOutput

; Finish
Var hFinishDialog

; === 5. СТРАНИЦЫ ВИЗАРДА =====================================================

; Страница 1: Приветствие
!insertmacro MUI_PAGE_WELCOME

; Страница 2: Проверка зависимостей
Page custom DepsPageCreate DepsPageLeave

; Страница 3: Выбор режима установки
Page custom InstallModePageCreate InstallModePageLeave

; Страница 4: Папка установки
!insertmacro MUI_PAGE_DIRECTORY

; Страница 5: Настройка Master-ноды (ресурсы) — только в расширенном режиме
Page custom MasterPageCreate MasterPageLeave

; Страница 6: Настройка сети Master — только в расширенном режиме
Page custom MasterNetworkPageCreate MasterNetworkPageLeave

; Страница 7: Настройка Worker-нод (ресурсы) — только в расширенном режиме
Page custom WorkerPageCreate WorkerPageLeave

; Страница 8: Выбор режима сети Worker — только в расширенном режиме
Page custom WorkerNetworkModePageCreate WorkerNetworkModePageLeave

; Страница 9a: Общая сеть для всех Worker — только в расширенном режиме
Page custom WorkerCommonNetworkPageCreate WorkerCommonNetworkPageLeave

; Страница 9b: Индивидуальная сеть Worker 1 — только в расширенном режиме
Page custom Worker1NetworkPageCreate Worker1NetworkPageLeave

; Страница 9c: Индивидуальная сеть Worker 2 — только в расширенном режиме
Page custom Worker2NetworkPageCreate Worker2NetworkPageLeave

; Страница 9d: Индивидуальная сеть Worker 3 — только в расширенном режиме
Page custom Worker3NetworkPageCreate Worker3NetworkPageLeave

; Страница 9e: Индивидуальная сеть Worker 4 — только в расширенном режиме
Page custom Worker4NetworkPageCreate Worker4NetworkPageLeave

; Страница 10: Smoke-тест (опционально)
Page custom SmokePageCreate SmokePageLeave

; Страница 11: Сводка настроек
Page custom SummaryPageCreate SummaryPageLeave

; Страница 12: Прогресс установки
!insertmacro MUI_PAGE_INSTFILES

; Страница 13: Результаты smoke-теста (если включён)
Page custom SmokeResultsPageCreate

; Страница 14: Финиш
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

Function MasterDefaultsToggle
  ${NSD_GetState} $hMasterDefaultsCheck $0
  ${If} $0 == 1
    EnableWindow $hPrefixField 0
    EnableWindow $hMasterCpuField 0
    EnableWindow $hMasterRamField 0
    EnableWindow $hMasterHddField 0
  ${Else}
    EnableWindow $hPrefixField 1
    EnableWindow $hMasterCpuField 1
    EnableWindow $hMasterRamField 1
    EnableWindow $hMasterHddField 1
  ${EndIf}
FunctionEnd

Function MasterNetDefaultsToggle
  ${NSD_GetState} $hMasterNetDefaultsCheck $0
  ${If} $0 == 1
    EnableWindow $hMasterSubnetField 0
    EnableWindow $hMasterMaskCombo 0
    EnableWindow $hMasterBridgeCombo 0
    EnableWindow $hMasterSecondAdapterCombo 0
    EnableWindow $hMasterPortField 0
    EnableWindow $hMasterApiPortField 0
    EnableWindow $hMasterDashPortField 0
  ${Else}
    EnableWindow $hMasterSubnetField 1
    EnableWindow $hMasterMaskCombo 1
    EnableWindow $hMasterBridgeCombo 1
    EnableWindow $hMasterSecondAdapterCombo 1
    EnableWindow $hMasterPortField 1
    EnableWindow $hMasterApiPortField 1
    EnableWindow $hMasterDashPortField 1
  ${EndIf}
FunctionEnd

Function WorkerDefaultsToggle
  ${NSD_GetState} $hWorkerDefaultsCheck $0
  ${If} $0 == 1
    EnableWindow $hWorkerCountField 0
    EnableWindow $hWorkerCpuField 0
    EnableWindow $hWorkerRamField 0
    EnableWindow $hWorkerHddField 0
  ${Else}
    EnableWindow $hWorkerCountField 1
    EnableWindow $hWorkerCpuField 1
    EnableWindow $hWorkerRamField 1
    EnableWindow $hWorkerHddField 1
  ${EndIf}
FunctionEnd

Function WorkerNetModeDefaultsToggle
  ${NSD_GetState} $hWorkerNetModeDefaultsCheck $0
  ${If} $0 == 1
    EnableWindow $hWorkerModeCommon 0
    EnableWindow $hWorkerModeIndividual 0
  ${Else}
    EnableWindow $hWorkerModeCommon 1
    EnableWindow $hWorkerModeIndividual 1
  ${EndIf}
FunctionEnd

Function WorkerNetDefaultsToggle
  ${NSD_GetState} $hWorkerNetDefaultsCheck $0
  ${If} $0 == 1
    EnableWindow $hWorkerSubnetField 0
    EnableWindow $hWorkerMaskCombo 0
    EnableWindow $hWorkerBridgeCombo 0
    EnableWindow $hWorkerSecondAdapterCombo 0
    EnableWindow $hWorkerSshPortField 0
  ${Else}
    EnableWindow $hWorkerSubnetField 1
    EnableWindow $hWorkerMaskCombo 1
    EnableWindow $hWorkerBridgeCombo 1
    EnableWindow $hWorkerSecondAdapterCombo 1
    EnableWindow $hWorkerSshPortField 1
  ${EndIf}
FunctionEnd

Function W1NetDefaultsToggle
  ${NSD_GetState} $hW1NetDefaultsCheck $0
  ${If} $0 == 1
    EnableWindow $hW1SubnetField 0
    EnableWindow $hW1MaskCombo 0
    EnableWindow $hW1BridgeCombo 0
    EnableWindow $hW1SecondAdapterCombo 0
    EnableWindow $hW1SshPortField 0
  ${Else}
    EnableWindow $hW1SubnetField 1
    EnableWindow $hW1MaskCombo 1
    EnableWindow $hW1BridgeCombo 1
    EnableWindow $hW1SecondAdapterCombo 1
    EnableWindow $hW1SshPortField 1
  ${EndIf}
FunctionEnd

Function W2NetDefaultsToggle
  ${NSD_GetState} $hW2NetDefaultsCheck $0
  ${If} $0 == 1
    EnableWindow $hW2SubnetField 0
    EnableWindow $hW2MaskCombo 0
    EnableWindow $hW2BridgeCombo 0
    EnableWindow $hW2SecondAdapterCombo 0
    EnableWindow $hW2SshPortField 0
  ${Else}
    EnableWindow $hW2SubnetField 1
    EnableWindow $hW2MaskCombo 1
    EnableWindow $hW2BridgeCombo 1
    EnableWindow $hW2SecondAdapterCombo 1
    EnableWindow $hW2SshPortField 1
  ${EndIf}
FunctionEnd

Function W3NetDefaultsToggle
  ${NSD_GetState} $hW3NetDefaultsCheck $0
  ${If} $0 == 1
    EnableWindow $hW3SubnetField 0
    EnableWindow $hW3MaskCombo 0
    EnableWindow $hW3BridgeCombo 0
    EnableWindow $hW3SecondAdapterCombo 0
    EnableWindow $hW3SshPortField 0
  ${Else}
    EnableWindow $hW3SubnetField 1
    EnableWindow $hW3MaskCombo 1
    EnableWindow $hW3BridgeCombo 1
    EnableWindow $hW3SecondAdapterCombo 1
    EnableWindow $hW3SshPortField 1
  ${EndIf}
FunctionEnd

Function W4NetDefaultsToggle
  ${NSD_GetState} $hW4NetDefaultsCheck $0
  ${If} $0 == 1
    EnableWindow $hW4SubnetField 0
    EnableWindow $hW4MaskCombo 0
    EnableWindow $hW4BridgeCombo 0
    EnableWindow $hW4SecondAdapterCombo 0
    EnableWindow $hW4SshPortField 0
  ${Else}
    EnableWindow $hW4SubnetField 1
    EnableWindow $hW4MaskCombo 1
    EnableWindow $hW4BridgeCombo 1
    EnableWindow $hW4SecondAdapterCombo 1
    EnableWindow $hW4SshPortField 1
  ${EndIf}
FunctionEnd

; Функция для заполнения списка сетевых адаптеров
Function EnumBridgeAdapters
  ; $0 — дескриптор ComboBox
  ; Заполняет список доступных сетевых адаптеров для моста
  nsExec::ExecToStack 'cmd.exe /C "VBoxManage list bridgedifs"'
  Pop $1
  Pop $2
  ${If} $1 == "0"
    ; Парсим вывод VBoxManage — каждая строка "Name: <adapter>" добавляется
    ; Для простоты добавляем типичные адаптеры
    SendMessage $0 ${CB_ADDSTRING} 0 "STR:Realtek PCIe GbE Family Controller"
    SendMessage $0 ${CB_ADDSTRING} 0 "STR:Intel(R) Ethernet Connection"
    SendMessage $0 ${CB_ADDSTRING} 0 "STR:Wi-Fi"
    SendMessage $0 ${CB_ADDSTRING} 0 "STR:Ethernet"
  ${EndIf}
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

; === 10. СТРАНИЦА: ВЫБОР РЕЖИМА УСТАНОВКИ ====================================

Function InstallModePageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_MODE_TITLE)" "$(STR_MODE_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $InstallMode == ""
    StrCpy $InstallMode "quick"
  ${EndIf}

  ${NSD_CreateLabel} 10 10 370 20 "$(STR_MODE_DESC)"

  ${NSD_CreateRadioButton} 10 40 370 16 "$(STR_MODE_QUICK)"
  Pop $hModeQuick
  ${If} $InstallMode == "quick"
    ${NSD_Check} $hModeQuick
  ${EndIf}

  ${NSD_CreateLabel} 10 60 370 14 "$(STR_MODE_QUICK_HINT)"

  ${NSD_CreateRadioButton} 10 90 370 16 "$(STR_MODE_ADVANCED)"
  Pop $hModeAdvanced
  ${If} $InstallMode == "advanced"
    ${NSD_Check} $hModeAdvanced
  ${EndIf}

  ${NSD_CreateLabel} 10 110 370 30 "$(STR_MODE_ADVANCED_HINT)"

  nsDialogs::Show
FunctionEnd

Function InstallModePageLeave
  ${NSD_GetState} $hModeQuick $0
  ${NSD_GetState} $hModeAdvanced $1
  ${If} $0 == 1
    StrCpy $InstallMode "quick"
    ; Quick mode — все значения по умолчанию
    StrCpy $ClusterPrefix "lab-k8s"
    StrCpy $MasterCpu "2"
    StrCpy $MasterRam "2048"
    StrCpy $MasterHdd "30"
    StrCpy $MasterSubnetPrefix "192.168.56"
    StrCpy $MasterSubnetMask "255.255.255.0"
    StrCpy $MasterBridgeAdapter "Ethernet"
    StrCpy $MasterSecondAdapter "Мост (Bridged)"
    StrCpy $MasterSshPort "2232"
    StrCpy $MasterApiPort "6443"
    StrCpy $MasterDashPort "30443"
    StrCpy $WorkerCount "2"
    StrCpy $WorkerCpu "2"
    StrCpy $WorkerRam "2048"
    StrCpy $WorkerHdd "30"
    StrCpy $WorkerNetworkMode "common"
    StrCpy $WorkerSubnetPrefix "192.168.57"
    StrCpy $WorkerSubnetMask "255.255.255.0"
    StrCpy $WorkerBridgeAdapter "Ethernet"
    StrCpy $WorkerSecondAdapter "Мост (Bridged)"
    StrCpy $WorkerSshPortBase "2242"
    StrCpy $RunSmokeTest "1"
  ${Else}
    StrCpy $InstallMode "advanced"
  ${EndIf}
FunctionEnd

; === 11. СТРАНИЦА: НАСТРОЙКА MASTER-НОДЫ (РЕСУРСЫ) ===========================

Function MasterPageCreate
  ${If} $InstallMode == "quick"
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "$(STR_MASTER_TITLE)" "$(STR_MASTER_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $MasterResDefaults == ""
    StrCpy $MasterResDefaults "1"
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

  ${NSD_CreateCheckbox} 10 10 370 16 "$(STR_USE_DEFAULTS)"
  Pop $hMasterDefaultsCheck
  ${NSD_OnClick} $hMasterDefaultsCheck MasterDefaultsToggle
  ${If} $MasterResDefaults == "1"
    ${NSD_Check} $hMasterDefaultsCheck
  ${EndIf}

  ${NSD_CreateLabel} 10 34 200 14 "$(STR_MASTER_PREFIX):"
  ${NSD_CreateText}  215 32 150 16 "$ClusterPrefix"
  Pop $hPrefixField

  ${NSD_CreateLabel} 10 56 200 14 "$(STR_MASTER_CPU):"
  ${NSD_CreateText}  215 54 150 16 "$MasterCpu"
  Pop $hMasterCpuField

  ${NSD_CreateLabel} 10 78 200 14 "$(STR_MASTER_RAM):"
  ${NSD_CreateText}  215 76 150 16 "$MasterRam"
  Pop $hMasterRamField

  ${NSD_CreateLabel} 10 100 200 14 "$(STR_MASTER_HDD):"
  ${NSD_CreateText}  215 98 150 16 "$MasterHdd"
  Pop $hMasterHddField

  ${NSD_CreateLabel} 10 130 370 20 "$(STR_MASTER_HINT)"

  ${If} $MasterResDefaults == "1"
    EnableWindow $hPrefixField 0
    EnableWindow $hMasterCpuField 0
    EnableWindow $hMasterRamField 0
    EnableWindow $hMasterHddField 0
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function MasterPageLeave
  ${NSD_GetState} $hMasterDefaultsCheck $MasterResDefaults
  ${If} $MasterResDefaults != "1"
    ${NSD_GetText} $hPrefixField    $ClusterPrefix
    ${NSD_GetText} $hMasterCpuField $MasterCpu
    ${NSD_GetText} $hMasterRamField $MasterRam
    ${NSD_GetText} $hMasterHddField $MasterHdd
  ${EndIf}

  StrLen $0 $ClusterPrefix
  ${If} $0 < 2
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_SHORT_PREFIX)"
    Abort
  ${EndIf}

  IntCmp $MasterCpu 1 +3
  IntCmp $MasterCpu 8 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_CPU_RANGE)"
  Abort

  IntCmp $MasterRam 512 +3
  IntCmp $MasterRam 16384 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_RAM_RANGE)"
  Abort
FunctionEnd

; === 11. СТРАНИЦА: НАСТРОЙКА СЕТИ MASTER =====================================

Function MasterNetworkPageCreate
  ${If} $InstallMode == "quick"
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "$(STR_MASTERNET_TITLE)" "$(STR_MASTERNET_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $MasterNetDefaults == ""
    StrCpy $MasterNetDefaults "1"
  ${EndIf}
  ${If} $MasterSubnetPrefix == ""
    StrCpy $MasterSubnetPrefix "192.168.56"
  ${EndIf}
  ${If} $MasterSubnetMask == ""
    StrCpy $MasterSubnetMask "255.255.255.0"
  ${EndIf}
  ${If} $MasterBridgeAdapter == ""
    StrCpy $MasterBridgeAdapter "Ethernet"
  ${EndIf}
  ${If} $MasterSecondAdapter == ""
    StrCpy $MasterSecondAdapter "$(STR_NETWORK_ADAPTER_BRIDGE)"
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

  ${NSD_CreateCheckbox} 10 10 370 16 "$(STR_USE_DEFAULTS)"
  Pop $hMasterNetDefaultsCheck
  ${NSD_OnClick} $hMasterNetDefaultsCheck MasterNetDefaultsToggle
  ${If} $MasterNetDefaults == "1"
    ${NSD_Check} $hMasterNetDefaultsCheck
  ${EndIf}

  ${NSD_CreateLabel} 10 34 200 14 "$(STR_NETWORK_SUBNET):"
  ${NSD_CreateText}  215 32 150 16 "$MasterSubnetPrefix"
  Pop $hMasterSubnetField

  ${NSD_CreateLabel} 10 56 200 14 "$(STR_NETWORK_MASK):"
  ${NSD_CreateComboBox} 215 54 150 80
  Pop $hMasterMaskCombo
  SendMessage $hMasterMaskCombo ${CB_ADDSTRING} 0 "STR:255.255.255.0"
  SendMessage $hMasterMaskCombo ${CB_ADDSTRING} 0 "STR:255.255.0.0"
  SendMessage $hMasterMaskCombo ${CB_ADDSTRING} 0 "STR:255.0.0.0"
  SendMessage $hMasterMaskCombo ${CB_SELECTSTRING} -1 "STR:$MasterSubnetMask"

  ${NSD_CreateLabel} 10 78 200 14 "$(STR_NETWORK_BRIDGE):"
  ${NSD_CreateText}  215 76 150 16 "$MasterBridgeAdapter"
  Pop $hMasterBridgeCombo

  ${NSD_CreateLabel} 10 100 200 14 "$(STR_NETWORK_ADAPTER):"
  ${NSD_CreateComboBox} 215 98 150 80
  Pop $hMasterSecondAdapterCombo
  SendMessage $hMasterSecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NONE)"
  SendMessage $hMasterSecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_BRIDGE)"
  SendMessage $hMasterSecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NAT)"
  SendMessage $hMasterSecondAdapterCombo ${CB_SELECTSTRING} -1 "STR:$MasterSecondAdapter"

  ${NSD_CreateLabel} 10 122 200 14 "$(STR_NETWORK_MASTER_PORT):"
  ${NSD_CreateText}  215 120 150 16 "$MasterSshPort"
  Pop $hMasterPortField

  ${NSD_CreateLabel} 10 144 200 14 "$(STR_NETWORK_API_PORT):"
  ${NSD_CreateText}  215 142 150 16 "$MasterApiPort"
  Pop $hMasterApiPortField

  ${NSD_CreateLabel} 10 166 200 14 "$(STR_NETWORK_DASH_PORT):"
  ${NSD_CreateText}  215 164 150 16 "$MasterDashPort"
  Pop $hMasterDashPortField

  ${NSD_CreateLabel} 10 190 370 20 "$(STR_MASTERNET_HINT)"

  ${If} $MasterNetDefaults == "1"
    EnableWindow $hMasterSubnetField 0
    EnableWindow $hMasterMaskCombo 0
    EnableWindow $hMasterBridgeCombo 0
    EnableWindow $hMasterSecondAdapterCombo 0
    EnableWindow $hMasterPortField 0
    EnableWindow $hMasterApiPortField 0
    EnableWindow $hMasterDashPortField 0
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function MasterNetworkPageLeave
  ${NSD_GetState} $hMasterNetDefaultsCheck $MasterNetDefaults
  ${If} $MasterNetDefaults != "1"
    ${NSD_GetText} $hMasterSubnetField    $MasterSubnetPrefix
    ${NSD_GetText} $hMasterMaskCombo      $MasterSubnetMask
    ${NSD_GetText} $hMasterBridgeCombo    $MasterBridgeAdapter
    ${NSD_GetText} $hMasterSecondAdapterCombo $MasterSecondAdapter
    ${NSD_GetText} $hMasterPortField      $MasterSshPort
    ${NSD_GetText} $hMasterApiPortField   $MasterApiPort
    ${NSD_GetText} $hMasterDashPortField  $MasterDashPort
  ${EndIf}

  StrLen $0 $MasterSubnetPrefix
  ${If} $0 < 7
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_INVALID_SUBNET)"
    Abort
  ${EndIf}

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

; === 12. СТРАНИЦА: НАСТРОЙКА WORKER-НОД (РЕСУРСЫ) ============================

Function WorkerPageCreate
  ${If} $InstallMode == "quick"
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "$(STR_WORKER_TITLE)" "$(STR_WORKER_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $WorkerResDefaults == ""
    StrCpy $WorkerResDefaults "1"
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

  ${NSD_CreateCheckbox} 10 10 370 16 "$(STR_USE_DEFAULTS)"
  Pop $hWorkerDefaultsCheck
  ${NSD_OnClick} $hWorkerDefaultsCheck WorkerDefaultsToggle
  ${If} $WorkerResDefaults == "1"
    ${NSD_Check} $hWorkerDefaultsCheck
  ${EndIf}

  ${NSD_CreateLabel} 10 34 200 14 "$(STR_WORKER_COUNT):"
  ${NSD_CreateText}  215 32 150 16 "$WorkerCount"
  Pop $hWorkerCountField

  ${NSD_CreateLabel} 10 56 200 14 "$(STR_WORKER_CPU):"
  ${NSD_CreateText}  215 54 150 16 "$WorkerCpu"
  Pop $hWorkerCpuField

  ${NSD_CreateLabel} 10 78 200 14 "$(STR_WORKER_RAM):"
  ${NSD_CreateText}  215 76 150 16 "$WorkerRam"
  Pop $hWorkerRamField

  ${NSD_CreateLabel} 10 100 200 14 "$(STR_WORKER_HDD):"
  ${NSD_CreateText}  215 98 150 16 "$WorkerHdd"
  Pop $hWorkerHddField

  ${NSD_CreateLabel} 10 130 370 20 "$(STR_WORKER_HINT)"

  ${If} $WorkerResDefaults == "1"
    EnableWindow $hWorkerCountField 0
    EnableWindow $hWorkerCpuField 0
    EnableWindow $hWorkerRamField 0
    EnableWindow $hWorkerHddField 0
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function WorkerPageLeave
  ${NSD_GetState} $hWorkerDefaultsCheck $WorkerResDefaults
  ${If} $WorkerResDefaults != "1"
    ${NSD_GetText} $hWorkerCountField $WorkerCount
    ${NSD_GetText} $hWorkerCpuField   $WorkerCpu
    ${NSD_GetText} $hWorkerRamField   $WorkerRam
    ${NSD_GetText} $hWorkerHddField   $WorkerHdd
  ${EndIf}

  IntCmp $WorkerCount 1 +3
  IntCmp $WorkerCount 4 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_WORKER_COUNT_RANGE)"
  Abort

  IntCmp $WorkerCpu 1 +3
  IntCmp $WorkerCpu 8 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_CPU_RANGE)"
  Abort

  IntCmp $WorkerRam 512 +3
  IntCmp $WorkerRam 16384 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_RAM_RANGE)"
  Abort
FunctionEnd

; === 13. СТРАНИЦА: ВЫБОР РЕЖИМА СЕТИ WORKER ==================================

Function WorkerNetworkModePageCreate
  ${If} $InstallMode == "quick"
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "$(STR_WORKERNETMODE_TITLE)" "$(STR_WORKERNETMODE_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $WorkerNetModeDefaults == ""
    StrCpy $WorkerNetModeDefaults "1"
  ${EndIf}
  ${If} $WorkerNetworkMode == ""
    StrCpy $WorkerNetworkMode "common"
  ${EndIf}

  ${NSD_CreateCheckbox} 10 10 370 16 "$(STR_USE_DEFAULTS)"
  Pop $hWorkerNetModeDefaultsCheck
  ${NSD_OnClick} $hWorkerNetModeDefaultsCheck WorkerNetModeDefaultsToggle
  ${If} $WorkerNetModeDefaults == "1"
    ${NSD_Check} $hWorkerNetModeDefaultsCheck
  ${EndIf}

  ${NSD_CreateLabel} 10 34 370 20 "$(STR_WORKERNETMODE_DESC)"

  ${NSD_CreateRadioButton} 10 64 370 16 "$(STR_WORKERNETMODE_COMMON)"
  Pop $hWorkerModeCommon
  ${If} $WorkerNetworkMode == "common"
    ${NSD_Check} $hWorkerModeCommon
  ${EndIf}

  ${NSD_CreateLabel} 10 84 370 14 "$(STR_WORKERNETMODE_COMMON_HINT)"

  ${NSD_CreateRadioButton} 10 114 370 16 "$(STR_WORKERNETMODE_INDIVIDUAL)"
  Pop $hWorkerModeIndividual
  ${If} $WorkerNetworkMode == "individual"
    ${NSD_Check} $hWorkerModeIndividual
  ${EndIf}

  ${NSD_CreateLabel} 10 134 370 30 "$(STR_WORKERNETMODE_INDIVIDUAL_HINT)"

  ${If} $WorkerNetModeDefaults == "1"
    EnableWindow $hWorkerModeCommon 0
    EnableWindow $hWorkerModeIndividual 0
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function WorkerNetworkModePageLeave
  ${NSD_GetState} $hWorkerNetModeDefaultsCheck $WorkerNetModeDefaults
  ${If} $WorkerNetModeDefaults != "1"
    ${NSD_GetState} $hWorkerModeCommon $0
    ${NSD_GetState} $hWorkerModeIndividual $1
    ${If} $0 == 1
      StrCpy $WorkerNetworkMode "common"
    ${Else}
      StrCpy $WorkerNetworkMode "individual"
    ${EndIf}
  ${EndIf}
FunctionEnd

; === 14. СТРАНИЦА: ОБЩАЯ СЕТЬ ДЛЯ ВСЕХ WORKER =================================

Function WorkerCommonNetworkPageCreate
  ${If} $InstallMode == "quick"
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "$(STR_WORKERNET_TITLE)" "$(STR_WORKERNET_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $WorkerNetDefaults == ""
    StrCpy $WorkerNetDefaults "1"
  ${EndIf}
  ${If} $WorkerSubnetPrefix == ""
    StrCpy $WorkerSubnetPrefix "192.168.57"
  ${EndIf}
  ${If} $WorkerSubnetMask == ""
    StrCpy $WorkerSubnetMask "255.255.255.0"
  ${EndIf}
  ${If} $WorkerBridgeAdapter == ""
    StrCpy $WorkerBridgeAdapter "Ethernet"
  ${EndIf}
  ${If} $WorkerSecondAdapter == ""
    StrCpy $WorkerSecondAdapter "$(STR_NETWORK_ADAPTER_BRIDGE)"
  ${EndIf}
  ${If} $WorkerSshPortBase == ""
    StrCpy $WorkerSshPortBase "2242"
  ${EndIf}

  ${NSD_CreateCheckbox} 10 10 370 16 "$(STR_USE_DEFAULTS)"
  Pop $hWorkerNetDefaultsCheck
  ${NSD_OnClick} $hWorkerNetDefaultsCheck WorkerNetDefaultsToggle
  ${If} $WorkerNetDefaults == "1"
    ${NSD_Check} $hWorkerNetDefaultsCheck
  ${EndIf}

  ${NSD_CreateLabel} 10 34 200 14 "$(STR_NETWORK_SUBNET):"
  ${NSD_CreateText}  215 32 150 16 "$WorkerSubnetPrefix"
  Pop $hWorkerSubnetField

  ${NSD_CreateLabel} 10 56 200 14 "$(STR_NETWORK_MASK):"
  ${NSD_CreateComboBox} 215 54 150 80
  Pop $hWorkerMaskCombo
  SendMessage $hWorkerMaskCombo ${CB_ADDSTRING} 0 "STR:255.255.255.0"
  SendMessage $hWorkerMaskCombo ${CB_ADDSTRING} 0 "STR:255.255.0.0"
  SendMessage $hWorkerMaskCombo ${CB_ADDSTRING} 0 "STR:255.0.0.0"
  SendMessage $hWorkerMaskCombo ${CB_SELECTSTRING} -1 "STR:$WorkerSubnetMask"

  ${NSD_CreateLabel} 10 78 200 14 "$(STR_NETWORK_BRIDGE):"
  ${NSD_CreateText}  215 76 150 16 "$WorkerBridgeAdapter"
  Pop $hWorkerBridgeCombo

  ${NSD_CreateLabel} 10 100 200 14 "$(STR_NETWORK_ADAPTER):"
  ${NSD_CreateComboBox} 215 98 150 80
  Pop $hWorkerSecondAdapterCombo
  SendMessage $hWorkerSecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NONE)"
  SendMessage $hWorkerSecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_BRIDGE)"
  SendMessage $hWorkerSecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NAT)"
  SendMessage $hWorkerSecondAdapterCombo ${CB_SELECTSTRING} -1 "STR:$WorkerSecondAdapter"

  ${NSD_CreateLabel} 10 122 200 14 "$(STR_WORKERNET_SSH_BASE):"
  ${NSD_CreateText}  215 120 150 16 "$WorkerSshPortBase"
  Pop $hWorkerSshPortField

  ${NSD_CreateLabel} 10 150 370 30 "$(STR_WORKERNET_COMMON_HINT)"

  ${If} $WorkerNetDefaults == "1"
    EnableWindow $hWorkerSubnetField 0
    EnableWindow $hWorkerMaskCombo 0
    EnableWindow $hWorkerBridgeCombo 0
    EnableWindow $hWorkerSecondAdapterCombo 0
    EnableWindow $hWorkerSshPortField 0
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function WorkerCommonNetworkPageLeave
  ${NSD_GetState} $hWorkerNetDefaultsCheck $WorkerNetDefaults
  ${If} $WorkerNetDefaults != "1"
    ${NSD_GetText} $hWorkerSubnetField        $WorkerSubnetPrefix
    ${NSD_GetText} $hWorkerMaskCombo          $WorkerSubnetMask
    ${NSD_GetText} $hWorkerBridgeCombo        $WorkerBridgeAdapter
    ${NSD_GetText} $hWorkerSecondAdapterCombo $WorkerSecondAdapter
    ${NSD_GetText} $hWorkerSshPortField       $WorkerSshPortBase
  ${EndIf}

  StrLen $0 $WorkerSubnetPrefix
  ${If} $0 < 7
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_INVALID_SUBNET)"
    Abort
  ${EndIf}

  IntCmp $WorkerSshPortBase 1024 +3
  IntCmp $WorkerSshPortBase 65535 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_PORT_RANGE)"
  Abort
FunctionEnd

; === 15. СТРАНИЦА: ИНДИВИДУАЛЬНАЯ СЕТЬ WORKER 1 ==============================

Function Worker1NetworkPageCreate
  ${If} $InstallMode == "quick"
    Abort
  ${EndIf}
  ${If} $WorkerNetworkMode != "individual"
    Abort
  ${EndIf}

  !insertmacro MUI_HEADER_TEXT "$(STR_WORKERNET_TITLE)" "Worker 1"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $W1NetDefaults == ""
    StrCpy $W1NetDefaults "1"
  ${EndIf}
  ${If} $W1_SubnetPrefix == ""
    StrCpy $W1_SubnetPrefix "192.168.57"
  ${EndIf}
  ${If} $W1_SubnetMask == ""
    StrCpy $W1_SubnetMask "255.255.255.0"
  ${EndIf}
  ${If} $W1_BridgeAdapter == ""
    StrCpy $W1_BridgeAdapter "Ethernet"
  ${EndIf}
  ${If} $W1_SecondAdapter == ""
    StrCpy $W1_SecondAdapter "$(STR_NETWORK_ADAPTER_BRIDGE)"
  ${EndIf}
  ${If} $W1_SshPort == ""
    StrCpy $W1_SshPort "2242"
  ${EndIf}

  ${NSD_CreateCheckbox} 10 10 370 16 "$(STR_USE_DEFAULTS)"
  Pop $hW1NetDefaultsCheck
  ${NSD_OnClick} $hW1NetDefaultsCheck W1NetDefaultsToggle
  ${If} $W1NetDefaults == "1"
    ${NSD_Check} $hW1NetDefaultsCheck
  ${EndIf}

  ${NSD_CreateLabel} 10 34 200 14 "$(STR_NETWORK_SUBNET):"
  ${NSD_CreateText}  215 32 150 16 "$W1_SubnetPrefix"
  Pop $hW1SubnetField

  ${NSD_CreateLabel} 10 56 200 14 "$(STR_NETWORK_MASK):"
  ${NSD_CreateComboBox} 215 54 150 80
  Pop $hW1MaskCombo
  SendMessage $hW1MaskCombo ${CB_ADDSTRING} 0 "STR:255.255.255.0"
  SendMessage $hW1MaskCombo ${CB_ADDSTRING} 0 "STR:255.255.0.0"
  SendMessage $hW1MaskCombo ${CB_ADDSTRING} 0 "STR:255.0.0.0"
  SendMessage $hW1MaskCombo ${CB_SELECTSTRING} -1 "STR:$W1_SubnetMask"

  ${NSD_CreateLabel} 10 78 200 14 "$(STR_NETWORK_BRIDGE):"
  ${NSD_CreateText}  215 76 150 16 "$W1_BridgeAdapter"
  Pop $hW1BridgeCombo

  ${NSD_CreateLabel} 10 100 200 14 "$(STR_NETWORK_ADAPTER):"
  ${NSD_CreateComboBox} 215 98 150 80
  Pop $hW1SecondAdapterCombo
  SendMessage $hW1SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NONE)"
  SendMessage $hW1SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_BRIDGE)"
  SendMessage $hW1SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NAT)"
  SendMessage $hW1SecondAdapterCombo ${CB_SELECTSTRING} -1 "STR:$W1_SecondAdapter"

  ${NSD_CreateLabel} 10 122 200 14 "$(STR_WORKERNET_SSH_PORT):"
  ${NSD_CreateText}  215 120 150 16 "$W1_SshPort"
  Pop $hW1SshPortField

  ${If} $W1NetDefaults == "1"
    EnableWindow $hW1SubnetField 0
    EnableWindow $hW1MaskCombo 0
    EnableWindow $hW1BridgeCombo 0
    EnableWindow $hW1SecondAdapterCombo 0
    EnableWindow $hW1SshPortField 0
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function Worker1NetworkPageLeave
  ${If} $WorkerNetworkMode != "individual"
    Abort
  ${EndIf}

  ${NSD_GetState} $hW1NetDefaultsCheck $W1NetDefaults
  ${If} $W1NetDefaults != "1"
    ${NSD_GetText} $hW1SubnetField        $W1_SubnetPrefix
    ${NSD_GetText} $hW1MaskCombo          $W1_SubnetMask
    ${NSD_GetText} $hW1BridgeCombo        $W1_BridgeAdapter
    ${NSD_GetText} $hW1SecondAdapterCombo $W1_SecondAdapter
    ${NSD_GetText} $hW1SshPortField       $W1_SshPort
  ${EndIf}

  StrLen $0 $W1_SubnetPrefix
  ${If} $0 < 7
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_INVALID_SUBNET)"
    Abort
  ${EndIf}
FunctionEnd

; === 16. СТРАНИЦА: ИНДИВИДУАЛЬНАЯ СЕТЬ WORKER 2 ==============================

Function Worker2NetworkPageCreate
  ${If} $InstallMode == "quick"
    Abort
  ${EndIf}
  ${If} $WorkerNetworkMode != "individual"
    Abort
  ${EndIf}
  IntCmp $WorkerCount 2 0 +2
  Abort

  !insertmacro MUI_HEADER_TEXT "$(STR_WORKERNET_TITLE)" "Worker 2"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $W2NetDefaults == ""
    StrCpy $W2NetDefaults "1"
  ${EndIf}
  ${If} $W2_SubnetPrefix == ""
    StrCpy $W2_SubnetPrefix "192.168.58"
  ${EndIf}
  ${If} $W2_SubnetMask == ""
    StrCpy $W2_SubnetMask "255.255.255.0"
  ${EndIf}
  ${If} $W2_BridgeAdapter == ""
    StrCpy $W2_BridgeAdapter "Ethernet"
  ${EndIf}
  ${If} $W2_SecondAdapter == ""
    StrCpy $W2_SecondAdapter "$(STR_NETWORK_ADAPTER_BRIDGE)"
  ${EndIf}
  ${If} $W2_SshPort == ""
    StrCpy $W2_SshPort "2252"
  ${EndIf}

  ${NSD_CreateCheckbox} 10 10 370 16 "$(STR_USE_DEFAULTS)"
  Pop $hW2NetDefaultsCheck
  ${NSD_OnClick} $hW2NetDefaultsCheck W2NetDefaultsToggle
  ${If} $W2NetDefaults == "1"
    ${NSD_Check} $hW2NetDefaultsCheck
  ${EndIf}

  ${NSD_CreateLabel} 10 34 200 14 "$(STR_NETWORK_SUBNET):"
  ${NSD_CreateText}  215 32 150 16 "$W2_SubnetPrefix"
  Pop $hW2SubnetField

  ${NSD_CreateLabel} 10 56 200 14 "$(STR_NETWORK_MASK):"
  ${NSD_CreateComboBox} 215 54 150 80
  Pop $hW2MaskCombo
  SendMessage $hW2MaskCombo ${CB_ADDSTRING} 0 "STR:255.255.255.0"
  SendMessage $hW2MaskCombo ${CB_ADDSTRING} 0 "STR:255.255.0.0"
  SendMessage $hW2MaskCombo ${CB_ADDSTRING} 0 "STR:255.0.0.0"
  SendMessage $hW2MaskCombo ${CB_SELECTSTRING} -1 "STR:$W2_SubnetMask"

  ${NSD_CreateLabel} 10 78 200 14 "$(STR_NETWORK_BRIDGE):"
  ${NSD_CreateText}  215 76 150 16 "$W2_BridgeAdapter"
  Pop $hW2BridgeCombo

  ${NSD_CreateLabel} 10 100 200 14 "$(STR_NETWORK_ADAPTER):"
  ${NSD_CreateComboBox} 215 98 150 80
  Pop $hW2SecondAdapterCombo
  SendMessage $hW2SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NONE)"
  SendMessage $hW2SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_BRIDGE)"
  SendMessage $hW2SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NAT)"
  SendMessage $hW2SecondAdapterCombo ${CB_SELECTSTRING} -1 "STR:$W2_SecondAdapter"

  ${NSD_CreateLabel} 10 122 200 14 "$(STR_WORKERNET_SSH_PORT):"
  ${NSD_CreateText}  215 120 150 16 "$W2_SshPort"
  Pop $hW2SshPortField

  ${If} $W2NetDefaults == "1"
    EnableWindow $hW2SubnetField 0
    EnableWindow $hW2MaskCombo 0
    EnableWindow $hW2BridgeCombo 0
    EnableWindow $hW2SecondAdapterCombo 0
    EnableWindow $hW2SshPortField 0
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function Worker2NetworkPageLeave
  ${If} $WorkerNetworkMode != "individual"
    Abort
  ${EndIf}
  IntCmp $WorkerCount 2 0 +2
  Abort

  ${NSD_GetState} $hW2NetDefaultsCheck $W2NetDefaults
  ${If} $W2NetDefaults != "1"
    ${NSD_GetText} $hW2SubnetField        $W2_SubnetPrefix
    ${NSD_GetText} $hW2MaskCombo          $W2_SubnetMask
    ${NSD_GetText} $hW2BridgeCombo        $W2_BridgeAdapter
    ${NSD_GetText} $hW2SecondAdapterCombo $W2_SecondAdapter
    ${NSD_GetText} $hW2SshPortField       $W2_SshPort
  ${EndIf}

  StrLen $0 $W2_SubnetPrefix
  ${If} $0 < 7
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_INVALID_SUBNET)"
    Abort
  ${EndIf}
FunctionEnd

; === 17. СТРАНИЦА: ИНДИВИДУАЛЬНАЯ СЕТЬ WORKER 3 ==============================

Function Worker3NetworkPageCreate
  ${If} $InstallMode == "quick"
    Abort
  ${EndIf}
  ${If} $WorkerNetworkMode != "individual"
    Abort
  ${EndIf}
  IntCmp $WorkerCount 3 0 +2
  Abort

  !insertmacro MUI_HEADER_TEXT "$(STR_WORKERNET_TITLE)" "Worker 3"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $W3NetDefaults == ""
    StrCpy $W3NetDefaults "1"
  ${EndIf}
  ${If} $W3_SubnetPrefix == ""
    StrCpy $W3_SubnetPrefix "192.168.59"
  ${EndIf}
  ${If} $W3_SubnetMask == ""
    StrCpy $W3_SubnetMask "255.255.255.0"
  ${EndIf}
  ${If} $W3_BridgeAdapter == ""
    StrCpy $W3_BridgeAdapter "Ethernet"
  ${EndIf}
  ${If} $W3_SecondAdapter == ""
    StrCpy $W3_SecondAdapter "$(STR_NETWORK_ADAPTER_BRIDGE)"
  ${EndIf}
  ${If} $W3_SshPort == ""
    StrCpy $W3_SshPort "2262"
  ${EndIf}

  ${NSD_CreateCheckbox} 10 10 370 16 "$(STR_USE_DEFAULTS)"
  Pop $hW3NetDefaultsCheck
  ${NSD_OnClick} $hW3NetDefaultsCheck W3NetDefaultsToggle
  ${If} $W3NetDefaults == "1"
    ${NSD_Check} $hW3NetDefaultsCheck
  ${EndIf}

  ${NSD_CreateLabel} 10 34 200 14 "$(STR_NETWORK_SUBNET):"
  ${NSD_CreateText}  215 32 150 16 "$W3_SubnetPrefix"
  Pop $hW3SubnetField

  ${NSD_CreateLabel} 10 56 200 14 "$(STR_NETWORK_MASK):"
  ${NSD_CreateComboBox} 215 54 150 80
  Pop $hW3MaskCombo
  SendMessage $hW3MaskCombo ${CB_ADDSTRING} 0 "STR:255.255.255.0"
  SendMessage $hW3MaskCombo ${CB_ADDSTRING} 0 "STR:255.255.0.0"
  SendMessage $hW3MaskCombo ${CB_ADDSTRING} 0 "STR:255.0.0.0"
  SendMessage $hW3MaskCombo ${CB_SELECTSTRING} -1 "STR:$W3_SubnetMask"

  ${NSD_CreateLabel} 10 78 200 14 "$(STR_NETWORK_BRIDGE):"
  ${NSD_CreateText}  215 76 150 16 "$W3_BridgeAdapter"
  Pop $hW3BridgeCombo

  ${NSD_CreateLabel} 10 100 200 14 "$(STR_NETWORK_ADAPTER):"
  ${NSD_CreateComboBox} 215 98 150 80
  Pop $hW3SecondAdapterCombo
  SendMessage $hW3SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NONE)"
  SendMessage $hW3SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_BRIDGE)"
  SendMessage $hW3SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NAT)"
  SendMessage $hW3SecondAdapterCombo ${CB_SELECTSTRING} -1 "STR:$W3_SecondAdapter"

  ${NSD_CreateLabel} 10 122 200 14 "$(STR_WORKERNET_SSH_PORT):"
  ${NSD_CreateText}  215 120 150 16 "$W3_SshPort"
  Pop $hW3SshPortField

  ${If} $W3NetDefaults == "1"
    EnableWindow $hW3SubnetField 0
    EnableWindow $hW3MaskCombo 0
    EnableWindow $hW3BridgeCombo 0
    EnableWindow $hW3SecondAdapterCombo 0
    EnableWindow $hW3SshPortField 0
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function Worker3NetworkPageLeave
  ${If} $WorkerNetworkMode != "individual"
    Abort
  ${EndIf}
  IntCmp $WorkerCount 3 0 +2
  Abort

  ${NSD_GetState} $hW3NetDefaultsCheck $W3NetDefaults
  ${If} $W3NetDefaults != "1"
    ${NSD_GetText} $hW3SubnetField        $W3_SubnetPrefix
    ${NSD_GetText} $hW3MaskCombo          $W3_SubnetMask
    ${NSD_GetText} $hW3BridgeCombo        $W3_BridgeAdapter
    ${NSD_GetText} $hW3SecondAdapterCombo $W3_SecondAdapter
    ${NSD_GetText} $hW3SshPortField       $W3_SshPort
  ${EndIf}

  StrLen $0 $W3_SubnetPrefix
  ${If} $0 < 7
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_INVALID_SUBNET)"
    Abort
  ${EndIf}
FunctionEnd

; === 18. СТРАНИЦА: ИНДИВИДУАЛЬНАЯ СЕТЬ WORKER 4 ==============================

Function Worker4NetworkPageCreate
  ${If} $InstallMode == "quick"
    Abort
  ${EndIf}
  ${If} $WorkerNetworkMode != "individual"
    Abort
  ${EndIf}
  IntCmp $WorkerCount 4 0 +2
  Abort

  !insertmacro MUI_HEADER_TEXT "$(STR_WORKERNET_TITLE)" "Worker 4"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $W4NetDefaults == ""
    StrCpy $W4NetDefaults "1"
  ${EndIf}
  ${If} $W4_SubnetPrefix == ""
    StrCpy $W4_SubnetPrefix "192.168.60"
  ${EndIf}
  ${If} $W4_SubnetMask == ""
    StrCpy $W4_SubnetMask "255.255.255.0"
  ${EndIf}
  ${If} $W4_BridgeAdapter == ""
    StrCpy $W4_BridgeAdapter "Ethernet"
  ${EndIf}
  ${If} $W4_SecondAdapter == ""
    StrCpy $W4_SecondAdapter "$(STR_NETWORK_ADAPTER_BRIDGE)"
  ${EndIf}
  ${If} $W4_SshPort == ""
    StrCpy $W4_SshPort "2272"
  ${EndIf}

  ${NSD_CreateCheckbox} 10 10 370 16 "$(STR_USE_DEFAULTS)"
  Pop $hW4NetDefaultsCheck
  ${NSD_OnClick} $hW4NetDefaultsCheck W4NetDefaultsToggle
  ${If} $W4NetDefaults == "1"
    ${NSD_Check} $hW4NetDefaultsCheck
  ${EndIf}

  ${NSD_CreateLabel} 10 34 200 14 "$(STR_NETWORK_SUBNET):"
  ${NSD_CreateText}  215 32 150 16 "$W4_SubnetPrefix"
  Pop $hW4SubnetField

  ${NSD_CreateLabel} 10 56 200 14 "$(STR_NETWORK_MASK):"
  ${NSD_CreateComboBox} 215 54 150 80
  Pop $hW4MaskCombo
  SendMessage $hW4MaskCombo ${CB_ADDSTRING} 0 "STR:255.255.255.0"
  SendMessage $hW4MaskCombo ${CB_ADDSTRING} 0 "STR:255.255.0.0"
  SendMessage $hW4MaskCombo ${CB_ADDSTRING} 0 "STR:255.0.0.0"
  SendMessage $hW4MaskCombo ${CB_SELECTSTRING} -1 "STR:$W4_SubnetMask"

  ${NSD_CreateLabel} 10 78 200 14 "$(STR_NETWORK_BRIDGE):"
  ${NSD_CreateText}  215 76 150 16 "$W4_BridgeAdapter"
  Pop $hW4BridgeCombo

  ${NSD_CreateLabel} 10 100 200 14 "$(STR_NETWORK_ADAPTER):"
  ${NSD_CreateComboBox} 215 98 150 80
  Pop $hW4SecondAdapterCombo
  SendMessage $hW4SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NONE)"
  SendMessage $hW4SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_BRIDGE)"
  SendMessage $hW4SecondAdapterCombo ${CB_ADDSTRING} 0 "STR:$(STR_NETWORK_ADAPTER_NAT)"
  SendMessage $hW4SecondAdapterCombo ${CB_SELECTSTRING} -1 "STR:$W4_SecondAdapter"

  ${NSD_CreateLabel} 10 122 200 14 "$(STR_WORKERNET_SSH_PORT):"
  ${NSD_CreateText}  215 120 150 16 "$W4_SshPort"
  Pop $hW4SshPortField

  ${If} $W4NetDefaults == "1"
    EnableWindow $hW4SubnetField 0
    EnableWindow $hW4MaskCombo 0
    EnableWindow $hW4BridgeCombo 0
    EnableWindow $hW4SecondAdapterCombo 0
    EnableWindow $hW4SshPortField 0
  ${EndIf}

  nsDialogs::Show
FunctionEnd

Function Worker4NetworkPageLeave
  ${If} $WorkerNetworkMode != "individual"
    Abort
  ${EndIf}
  IntCmp $WorkerCount 4 0 +2
  Abort

  ${NSD_GetState} $hW4NetDefaultsCheck $W4NetDefaults
  ${If} $W4NetDefaults != "1"
    ${NSD_GetText} $hW4SubnetField        $W4_SubnetPrefix
    ${NSD_GetText} $hW4MaskCombo          $W4_SubnetMask
    ${NSD_GetText} $hW4BridgeCombo        $W4_BridgeAdapter
    ${NSD_GetText} $hW4SecondAdapterCombo $W4_SecondAdapter
    ${NSD_GetText} $hW4SshPortField       $W4_SshPort
  ${EndIf}

  StrLen $0 $W4_SubnetPrefix
  ${If} $0 < 7
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_INVALID_SUBNET)"
    Abort
  ${EndIf}
FunctionEnd

; === 19. СТРАНИЦА: SMOKE-ТЕСТ ================================================

Function SmokePageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_SMOKE_TITLE)" "$(STR_SMOKE_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $RunSmokeTest == ""
    StrCpy $RunSmokeTest "1"
  ${EndIf}

  ${NSD_CreateCheckbox} 10 10 370 20 "$(STR_SMOKE_RUN)"
  Pop $hSmokeCheckbox
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

; === 20. СТРАНИЦА: СВОДКА НАСТРОЕК ===========================================

Function SummaryPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_SUMMARY_TITLE)" "$(STR_SUMMARY_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog

  ; Заголовок таблицы
  ${NSD_CreateLabel} 10 5 370 14 "$(STR_SUMMARY_TREE_TITLE)"
  Pop $0

  ; Шапка таблицы
  ${NSD_CreateLabel} 10 25 70 14 "Node"
  Pop $0
  ${NSD_CreateLabel} 85 25 35 14 "CPU"
  Pop $0
  ${NSD_CreateLabel} 125 25 45 14 "RAM"
  Pop $0
  ${NSD_CreateLabel} 175 25 35 14 "HDD"
  Pop $0
  ${NSD_CreateLabel} 215 25 80 14 "Network"
  Pop $0
  ${NSD_CreateLabel} 300 25 70 14 "Bridge"
  Pop $0

  ; Разделитель
  ${NSD_CreateLabel} 10 40 370 1 "________________________________________"
  Pop $0

  ; Master-нода
  ${NSD_CreateLabel} 10 45 70 14 "$ClusterPrefix-master"
  Pop $0
  ${NSD_CreateLabel} 85 45 35 14 "$MasterCpu"
  Pop $0
  ${NSD_CreateLabel} 125 45 45 14 "$MasterRam MB"
  Pop $0
  ${NSD_CreateLabel} 175 45 35 14 "$MasterHdd GB"
  Pop $0
  ${NSD_CreateLabel} 215 45 80 14 "$MasterSubnetPrefix.10"
  Pop $0
  ${NSD_CreateLabel} 300 45 70 14 "$MasterBridgeAdapter"
  Pop $0

  ; Порты Master
  ${NSD_CreateLabel} 10 60 370 14 "  Ports: SSH=$MasterSshPort  API=$MasterApiPort  Dashboard=$MasterDashPort"
  Pop $0

  ; Разделитель
  ${NSD_CreateLabel} 10 75 370 1 "________________________________________"
  Pop $0

  ; Worker 1
  ${NSD_CreateLabel} 10 80 70 14 "$ClusterPrefix-worker1"
  Pop $0
  ${NSD_CreateLabel} 85 80 35 14 "$WorkerCpu"
  Pop $0
  ${NSD_CreateLabel} 125 80 45 14 "$WorkerRam MB"
  Pop $0
  ${NSD_CreateLabel} 175 80 35 14 "$WorkerHdd GB"
  Pop $0
  ${If} $WorkerNetworkMode == "common"
    ${NSD_CreateLabel} 215 80 80 14 "$WorkerSubnetPrefix.11"
    Pop $0
    ${NSD_CreateLabel} 300 80 70 14 "$WorkerBridgeAdapter"
    Pop $0
  ${Else}
    ${NSD_CreateLabel} 215 80 80 14 "$W1_SubnetPrefix.11"
    Pop $0
    ${NSD_CreateLabel} 300 80 70 14 "$W1_BridgeAdapter"
    Pop $0
  ${EndIf}

  ; Worker 2
  IntCmp $WorkerCount 2 showW2 skipW2 skipW2
showW2:
  ${NSD_CreateLabel} 10 95 70 14 "$ClusterPrefix-worker2"
  Pop $0
  ${NSD_CreateLabel} 85 95 35 14 "$WorkerCpu"
  Pop $0
  ${NSD_CreateLabel} 125 95 45 14 "$WorkerRam MB"
  Pop $0
  ${NSD_CreateLabel} 175 95 35 14 "$WorkerHdd GB"
  Pop $0
  ${If} $WorkerNetworkMode == "common"
    ${NSD_CreateLabel} 215 95 80 14 "$WorkerSubnetPrefix.12"
    Pop $0
    ${NSD_CreateLabel} 300 95 70 14 "$WorkerBridgeAdapter"
    Pop $0
  ${Else}
    ${NSD_CreateLabel} 215 95 80 14 "$W2_SubnetPrefix.11"
    Pop $0
    ${NSD_CreateLabel} 300 95 70 14 "$W2_BridgeAdapter"
    Pop $0
  ${EndIf}
skipW2:

  ; Worker 3
  IntCmp $WorkerCount 3 showW3 skipW3 skipW3
showW3:
  ${NSD_CreateLabel} 10 110 70 14 "$ClusterPrefix-worker3"
  Pop $0
  ${NSD_CreateLabel} 85 110 35 14 "$WorkerCpu"
  Pop $0
  ${NSD_CreateLabel} 125 110 45 14 "$WorkerRam MB"
  Pop $0
  ${NSD_CreateLabel} 175 110 35 14 "$WorkerHdd GB"
  Pop $0
  ${If} $WorkerNetworkMode == "common"
    ${NSD_CreateLabel} 215 110 80 14 "$WorkerSubnetPrefix.13"
    Pop $0
    ${NSD_CreateLabel} 300 110 70 14 "$WorkerBridgeAdapter"
    Pop $0
  ${Else}
    ${NSD_CreateLabel} 215 110 80 14 "$W3_SubnetPrefix.11"
    Pop $0
    ${NSD_CreateLabel} 300 110 70 14 "$W3_BridgeAdapter"
    Pop $0
  ${EndIf}
skipW3:

  ; Worker 4
  IntCmp $WorkerCount 4 showW4 skipW4 skipW4
showW4:
  ${NSD_CreateLabel} 10 125 70 14 "$ClusterPrefix-worker4"
  Pop $0
  ${NSD_CreateLabel} 85 125 35 14 "$WorkerCpu"
  Pop $0
  ${NSD_CreateLabel} 125 125 45 14 "$WorkerRam MB"
  Pop $0
  ${NSD_CreateLabel} 175 125 35 14 "$WorkerHdd GB"
  Pop $0
  ${If} $WorkerNetworkMode == "common"
    ${NSD_CreateLabel} 215 125 80 14 "$WorkerSubnetPrefix.14"
    Pop $0
    ${NSD_CreateLabel} 300 125 70 14 "$WorkerBridgeAdapter"
    Pop $0
  ${Else}
    ${NSD_CreateLabel} 215 125 80 14 "$W4_SubnetPrefix.11"
    Pop $0
    ${NSD_CreateLabel} 300 125 70 14 "$W4_BridgeAdapter"
    Pop $0
  ${EndIf}
skipW4:

  ; Разделитель
  ${NSD_CreateLabel} 10 140 370 1 "________________________________________"
  Pop $0

  ; Итого
  ${NSD_CreateLabel} 10 145 370 14 "Итого: 1 master + $WorkerCount worker(s) | Dir: $INSTDIR"
  Pop $0

  ${NSD_CreateLabel} 10 165 370 14 "$(STR_SUMMARY_NOTE)"
  Pop $0

  nsDialogs::Show
FunctionEnd

Function SummaryPageLeave
FunctionEnd

; === 21. СТРАНИЦА: РЕЗУЛЬТАТЫ SMOKE-ТЕСТА ====================================

Function SmokeResultsPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_SMOKE_RES_TITLE)" "$(STR_SMOKE_RES_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ${If} $RunSmokeTest == "1"
    ${If} $SmokeResult == "0"
      ${NSD_CreateLabel} 10 5 370 14 "$(STR_SMOKE_RES_PASS)"
    ${Else}
      ${NSD_CreateLabel} 10 5 370 14 "$(STR_SMOKE_RES_FAIL)"
    ${EndIf}

    ${NSD_CreateLabel} 10 30 160 14 "$(STR_SMOKE_RES_NODES)"
    ${NSD_CreateLabel} 175 30 195 40 "$SmokeNodesOutput"

    ${NSD_CreateLabel} 10 80 160 14 "$(STR_SMOKE_RES_PODS)"
    ${NSD_CreateLabel} 175 80 195 40 "$SmokePodsOutput"

    ${NSD_CreateLabel} 10 130 160 14 "$(STR_SMOKE_RES_SVC)"
    ${NSD_CreateLabel} 175 130 195 40 "$SmokeSvcOutput"

    ${NSD_CreateLabel} 10 180 160 14 "$(STR_SMOKE_RES_JOB)"
    ${NSD_CreateLabel} 175 180 195 20 "$SmokeJobOutput"
  ${Else}
    ${NSD_CreateLabel} 10 5 370 14 "$(STR_SMOKE_NO)"
  ${EndIf}

  nsDialogs::Show
FunctionEnd

; === 22. СТРАНИЦА: ФИНИШ =====================================================

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

; === 23. СЕКЦИИ УСТАНОВКИ (каждая = отдельный этап прогрессбара) =============

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
  FileWrite $0 "# Создано NSIS-визардом v3$\r$\n$\r$\n"
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
  FileWrite $0 "# Master Network$\r$\n"
  FileWrite $0 "PRIVATE_NETWORK_PREFIX=$MasterSubnetPrefix$\r$\n"
  FileWrite $0 "PRIVATE_NETWORK_GATEWAY=$MasterSubnetPrefix.1$\r$\n"
  FileWrite $0 "MASTER_PRIVATE_IP=$MasterSubnetPrefix.10$\r$\n"
  FileWrite $0 "MASTER_SSH_PORT=$MasterSshPort$\r$\n"
  FileWrite $0 "MASTER_API_PORT=$MasterApiPort$\r$\n"
  FileWrite $0 "MASTER_DASHBOARD_PORT=$MasterDashPort$\r$\n"
  FileWrite $0 "SUBNET_MASK=$MasterSubnetMask$\r$\n"
  FileWrite $0 "BRIDGE_ADAPTER=$MasterBridgeAdapter$\r$\n"
  FileWrite $0 "SECOND_ADAPTER=$MasterSecondAdapter$\r$\n$\r$\n"
  FileWrite $0 "# Worker Network Mode: $WorkerNetworkMode$\r$\n"
  FileWrite $0 "WORKER_NETWORK_MODE=$WorkerNetworkMode$\r$\n"
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Worker 1$\r$\n"
  FileWrite $0 "WORKER1_VM_NAME=$ClusterPrefix-worker1$\r$\n"
  FileWrite $0 "WORKER1_HOSTNAME=$ClusterPrefix-worker1$\r$\n"
  ${If} $WorkerNetworkMode == "common"
    FileWrite $0 "WORKER1_PRIVATE_IP=$WorkerSubnetPrefix.11$\r$\n"
    FileWrite $0 "WORKER1_SSH_PORT=$WorkerSshPortBase$\r$\n"
    FileWrite $0 "WORKER1_SUBNET_MASK=$WorkerSubnetMask$\r$\n"
    FileWrite $0 "WORKER1_BRIDGE_ADAPTER=$WorkerBridgeAdapter$\r$\n"
    FileWrite $0 "WORKER1_SECOND_ADAPTER=$WorkerSecondAdapter$\r$\n"
  ${Else}
    FileWrite $0 "WORKER1_PRIVATE_IP=$W1_SubnetPrefix.11$\r$\n"
    FileWrite $0 "WORKER1_SSH_PORT=$W1_SshPort$\r$\n"
    FileWrite $0 "WORKER1_SUBNET_MASK=$W1_SubnetMask$\r$\n"
    FileWrite $0 "WORKER1_BRIDGE_ADAPTER=$W1_BridgeAdapter$\r$\n"
    FileWrite $0 "WORKER1_SECOND_ADAPTER=$W1_SecondAdapter$\r$\n"
  ${EndIf}
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Worker 2$\r$\n"
  FileWrite $0 "WORKER2_VM_NAME=$ClusterPrefix-worker2$\r$\n"
  FileWrite $0 "WORKER2_HOSTNAME=$ClusterPrefix-worker2$\r$\n"
  ${If} $WorkerNetworkMode == "common"
    FileWrite $0 "WORKER2_PRIVATE_IP=$WorkerSubnetPrefix.12$\r$\n"
    IntOp $1 $WorkerSshPortBase + 10
    FileWrite $0 "WORKER2_SSH_PORT=$1$\r$\n"
    FileWrite $0 "WORKER2_SUBNET_MASK=$WorkerSubnetMask$\r$\n"
    FileWrite $0 "WORKER2_BRIDGE_ADAPTER=$WorkerBridgeAdapter$\r$\n"
    FileWrite $0 "WORKER2_SECOND_ADAPTER=$WorkerSecondAdapter$\r$\n"
  ${ElseIf} $WorkerCount >= 2
    FileWrite $0 "WORKER2_PRIVATE_IP=$W2_SubnetPrefix.11$\r$\n"
    FileWrite $0 "WORKER2_SSH_PORT=$W2_SshPort$\r$\n"
    FileWrite $0 "WORKER2_SUBNET_MASK=$W2_SubnetMask$\r$\n"
    FileWrite $0 "WORKER2_BRIDGE_ADAPTER=$W2_BridgeAdapter$\r$\n"
    FileWrite $0 "WORKER2_SECOND_ADAPTER=$W2_SecondAdapter$\r$\n"
  ${EndIf}
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Worker 3$\r$\n"
  FileWrite $0 "WORKER3_VM_NAME=$ClusterPrefix-worker3$\r$\n"
  FileWrite $0 "WORKER3_HOSTNAME=$ClusterPrefix-worker3$\r$\n"
  ${If} $WorkerNetworkMode == "common"
    FileWrite $0 "WORKER3_PRIVATE_IP=$WorkerSubnetPrefix.13$\r$\n"
    IntOp $1 $WorkerSshPortBase + 20
    FileWrite $0 "WORKER3_SSH_PORT=$1$\r$\n"
    FileWrite $0 "WORKER3_SUBNET_MASK=$WorkerSubnetMask$\r$\n"
    FileWrite $0 "WORKER3_BRIDGE_ADAPTER=$WorkerBridgeAdapter$\r$\n"
    FileWrite $0 "WORKER3_SECOND_ADAPTER=$WorkerSecondAdapter$\r$\n"
  ${ElseIf} $WorkerCount >= 3
    FileWrite $0 "WORKER3_PRIVATE_IP=$W3_SubnetPrefix.11$\r$\n"
    FileWrite $0 "WORKER3_SSH_PORT=$W3_SshPort$\r$\n"
    FileWrite $0 "WORKER3_SUBNET_MASK=$W3_SubnetMask$\r$\n"
    FileWrite $0 "WORKER3_BRIDGE_ADAPTER=$W3_BridgeAdapter$\r$\n"
    FileWrite $0 "WORKER3_SECOND_ADAPTER=$W3_SecondAdapter$\r$\n"
  ${EndIf}
  FileWrite $0 "$\r$\n"
  FileWrite $0 "# Worker 4$\r$\n"
  FileWrite $0 "WORKER4_VM_NAME=$ClusterPrefix-worker4$\r$\n"
  FileWrite $0 "WORKER4_HOSTNAME=$ClusterPrefix-worker4$\r$\n"
  ${If} $WorkerNetworkMode == "common"
    FileWrite $0 "WORKER4_PRIVATE_IP=$WorkerSubnetPrefix.14$\r$\n"
    IntOp $1 $WorkerSshPortBase + 30
    FileWrite $0 "WORKER4_SSH_PORT=$1$\r$\n"
    FileWrite $0 "WORKER4_SUBNET_MASK=$WorkerSubnetMask$\r$\n"
    FileWrite $0 "WORKER4_BRIDGE_ADAPTER=$WorkerBridgeAdapter$\r$\n"
    FileWrite $0 "WORKER4_SECOND_ADAPTER=$WorkerSecondAdapter$\r$\n"
  ${ElseIf} $WorkerCount >= 4
    FileWrite $0 "WORKER4_PRIVATE_IP=$W4_SubnetPrefix.11$\r$\n"
    FileWrite $0 "WORKER4_SSH_PORT=$W4_SshPort$\r$\n"
    FileWrite $0 "WORKER4_SUBNET_MASK=$W4_SubnetMask$\r$\n"
    FileWrite $0 "WORKER4_BRIDGE_ADAPTER=$W4_BridgeAdapter$\r$\n"
    FileWrite $0 "WORKER4_SECOND_ADAPTER=$W4_SecondAdapter$\r$\n"
  ${EndIf}
  FileWrite $0 "$\r$\n"
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
    "DisplayVersion" "3.0.0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Smoke-тест" SecSmokeTest
  ${If} $RunSmokeTest != "1"
    Abort
  ${EndIf}

  DetailPrint "$(STR_SMOKE_RES_RUNNING)"

  ; Deploy smoke test manifests
  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl apply -f /vagrant/smoke-tests/nginx-smoke.yaml"'
  Pop $0

  ; Wait for pods to be ready
  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl wait --for=condition=ready pod -l app=nginx-smoke -n smoke-tests --timeout=120s"'
  Pop $0

  ; Wait for job to complete
  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl wait --for=condition=complete job/nginx-smoke-check -n smoke-tests --timeout=180s"'
  Pop $1
  StrCpy $SmokeResult $1

  ; Gather results
  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl get nodes --no-headers"'
  Pop $0
  Pop $SmokeNodesOutput

  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl get pods -n smoke-tests --no-headers"'
  Pop $0
  Pop $SmokePodsOutput

  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl get svc -n smoke-tests --no-headers"'
  Pop $0
  Pop $SmokeSvcOutput

  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl get job nginx-smoke-check -n smoke-tests -o wide --no-headers"'
  Pop $0
  Pop $SmokeJobOutput
SectionEnd

; === 24. ДЕИНСТАЛЛЯТОР =======================================================

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
