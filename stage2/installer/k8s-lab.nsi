; =============================================================================
; k8s-lab.nsi — NSIS-установщик Kubernetes Cluster Lab
; =============================================================================
;
; ЧТО ТАКОЕ NSIS:
;   Nullsoft Scriptable Install System — бесплатная система создания инсталляторов
;   для Windows. Документация: https://nsis.sourceforge.io/Docs/
;
; КАК СКОМПИЛИРОВАТЬ:
;   makensis k8s-lab.nsi   →   k8s-lab-setup.exe
;
; ОБЯЗАТЕЛЬНЫЙ ПОРЯДОК СЕКЦИЙ В NSIS MUI2:
;   1. !include MUI2.nsh и другие библиотеки
;   2. !define настройки MUI
;   3. Var переменные
;   4. !insertmacro MUI_PAGE_* и Page custom  ← страницы визарда
;   5. !insertmacro MUI_LANGUAGE "..."        ← языки (ПОСЛЕ страниц!)
;   6. !include "lang\*.nsh"                 ← строки (ПОСЛЕ языков!)
;   7. Section / Function код
; =============================================================================

; === 1. ЗАГОЛОВОК ============================================================

Name "Kubernetes Cluster Lab"
OutFile "k8s-lab-setup.exe"
InstallDir "$DOCUMENTS\k8s-lab"
InstallDirRegKey HKCU "Software\K8sLab" "InstallDir"
SetCompressor /SOLID lzma

; Мета-информация для свойств EXE-файла
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "Kubernetes Cluster Lab"
VIAddVersionKey "ProductVersion" "1.0.0"
VIAddVersionKey "FileVersion" "1.0.0.0"
VIAddVersionKey "FileDescription" "Kubernetes lab installer for Windows"
VIAddVersionKey "LegalCopyright" "MIT License"

; === 2. ПОДКЛЮЧЕНИЕ БИБЛИОТЕК ================================================

; Modern UI 2 — внешний вид как у стандартных Windows-установщиков
; Документация: https://nsis.sourceforge.io/Docs/Modern%20UI%202/Readme.html
!include "MUI2.nsh"

; nsDialogs — создание страниц с полями ввода
; Документация: https://nsis.sourceforge.io/NsDialogs_Usage
!include "nsDialogs.nsh"

; Логические операторы (${If}, ${Else}, ${EndIf})
!include "LogicLib.nsh"

; === 3. НАСТРОЙКИ ВНЕШНЕГО ВИДА MUI =========================================
; ВАЖНО: все !define MUI_* должны идти ДО !insertmacro MUI_LANGUAGE

!define MUI_ABORTWARNING                  ; спрашивать подтверждение при отмене
; Заголовочное изображение (опционально):
; !define MUI_HEADERIMAGE
; !define MUI_HEADERIMAGE_BITMAP "assets\banner.bmp"

; === 4. ПЕРЕМЕННЫЕ ===========================================================

Var ClusterPrefix    ; Префикс имён ВМ (например: lab-k8s)
Var WorkerCount      ; Количество воркеров (1–4)
Var CpuCount         ; CPU на ВМ
Var RamMb            ; RAM в МБ
Var SubnetPrefix     ; Первые три октета (например: 192.168.56)

; Дескрипторы элементов диалога
Var hDialog
Var hPrefixField
Var hWorkersField
Var hCpuField
Var hRamField
Var hSubnetField
Var hDepsDialog

; === 5. СТРАНИЦЫ ВИЗАРДА (обязательно ДО !insertmacro MUI_LANGUAGE) ==========
;
; Порядок отображения:
;   Приветствие → Зависимости → Конфигурация → Папка → Сводка → Установка → Финиш

; Страница 1: Приветствие
!insertmacro MUI_PAGE_WELCOME

; Страница 2: Проверка зависимостей (пользовательская)
Page custom DepsPageCreate DepsPageLeave

; Страница 3: Конфигурация кластера (пользовательская)
Page custom ConfigPageCreate ConfigPageLeave

; Страница 4: Выбор папки установки
!insertmacro MUI_PAGE_DIRECTORY

; Страница 5: Сводка настроек (пользовательская)
Page custom SummaryPageCreate SummaryPageLeave

; Страница 6: Прогресс установки
!insertmacro MUI_PAGE_INSTFILES

; Страница 7: Завершение
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\README.md"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Open README / Открыть README"
!insertmacro MUI_PAGE_FINISH

; Деинсталлятор
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; === 6. ЯЗЫКИ (обязательно ПОСЛЕ страниц, ДО LangString-файлов) ==============
;
; Порядок определяет язык по умолчанию: первый = предпочтительный.
; MUI_LANGUAGE определяет константы LANG_RUSSIAN, LANG_ENGLISH и т.д.
; Без этих констант LangString-файлы не компилируются.

!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

; === 7. СТРОКИ ИНТЕРФЕЙСА (обязательно ПОСЛЕ MUI_LANGUAGE) ===================
;
; Эти файлы содержат LangString определения вида:
;   LangString STR_WELCOME_TITLE ${LANG_RUSSIAN} "Kubernetes Cluster Lab"
;
; LANG_RUSSIAN / LANG_ENGLISH определяются в шаге 6.
; Порядок: сначала русский, потом английский (дублирует каждую строку).

!include "lang\russian.nsh"
!include "lang\english.nsh"

; === 8. СЕКЦИЯ УСТАНОВКИ =====================================================

Section "Kubernetes Lab" SecMain

  ; Проверяем права администратора
  UserInfo::GetAccountType
  Pop $0
  ${If} $0 != "Admin"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_NO_ADMIN)"
    Abort
  ${EndIf}

  SetOutPath "$INSTDIR"

  ; --- Копирование файлов проекта ---
  DetailPrint "$(STR_INSTALL_COPY)"
  File "..\..\.env.example"
  File "..\..\.gitignore"
  File "..\..\Vagrantfile"
  CreateDirectory "$INSTDIR\scripts"
  File /oname=scripts\common.sh "..\..\scripts\common.sh"
  File /oname=scripts\master.sh "..\..\scripts\master.sh"
  File /oname=scripts\worker.sh "..\..\scripts\worker.sh"
  File /oname=scripts\generate-node-key.ps1 "..\..\scripts\generate-node-key.ps1"
  File /oname=scripts\cleanup-node-key.ps1  "..\..\scripts\cleanup-node-key.ps1"

  ; --- Создание .env из настроек пользователя ---
  DetailPrint "$(STR_INSTALL_CONFIG)"
  FileOpen $0 "$INSTDIR\.env" w
  FileWrite $0 "# Kubernetes Cluster Lab — конфигурация$\r$\n"
  FileWrite $0 "# Создано NSIS-визардом$\r$\n$\r$\n"
  FileWrite $0 "CLUSTER_PREFIX=$ClusterPrefix$\r$\n"
  FileWrite $0 "MASTER_VM_NAME=$ClusterPrefix-master$\r$\n"
  FileWrite $0 "MASTER_HOSTNAME=$ClusterPrefix-master$\r$\n$\r$\n"
  FileWrite $0 "VM_BOX=bento/ubuntu-24.04$\r$\n"
  FileWrite $0 "VM_CPUS=$CpuCount$\r$\n"
  FileWrite $0 "VM_MEMORY_MB=$RamMb$\r$\n"
  FileWrite $0 "VM_BOOT_TIMEOUT=600$\r$\n"
  FileWrite $0 "WORKER_COUNT=$WorkerCount$\r$\n$\r$\n"
  FileWrite $0 "PRIVATE_NETWORK_PREFIX=$SubnetPrefix$\r$\n"
  FileWrite $0 "PRIVATE_NETWORK_GATEWAY=$SubnetPrefix.1$\r$\n"
  FileWrite $0 "MASTER_PRIVATE_IP=$SubnetPrefix.10$\r$\n"
  FileWrite $0 "MASTER_SSH_PORT=2232$\r$\n"
  FileWrite $0 "MASTER_API_PORT=6443$\r$\n"
  FileWrite $0 "MASTER_DASHBOARD_PORT=30443$\r$\n$\r$\n"
  FileWrite $0 "WORKER1_VM_NAME=$ClusterPrefix-worker1$\r$\n"
  FileWrite $0 "WORKER1_HOSTNAME=$ClusterPrefix-worker1$\r$\n"
  FileWrite $0 "WORKER1_PRIVATE_IP=$SubnetPrefix.11$\r$\n"
  FileWrite $0 "WORKER1_SSH_PORT=2242$\r$\n$\r$\n"
  FileWrite $0 "WORKER2_VM_NAME=$ClusterPrefix-worker2$\r$\n"
  FileWrite $0 "WORKER2_HOSTNAME=$ClusterPrefix-worker2$\r$\n"
  FileWrite $0 "WORKER2_PRIVATE_IP=$SubnetPrefix.12$\r$\n"
  FileWrite $0 "WORKER2_SSH_PORT=2252$\r$\n$\r$\n"
  FileWrite $0 "BRIDGE_ADAPTER=$\r$\n$\r$\n"
  FileWrite $0 "KUBERNETES_VERSION=1.34$\r$\n"
  FileWrite $0 "POD_CIDR=10.244.0.0/16$\r$\n"
  FileClose $0

  ; --- Генерация SSH-ключей ---
  DetailPrint "$(STR_INSTALL_KEYS)"
  CreateDirectory "$INSTDIR\.vagrant\node-keys"

  nsExec::ExecToLog 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\scripts\generate-node-key.ps1" -NodeName "$ClusterPrefix-master" -KeyDirectory "$INSTDIR\.vagrant\node-keys"'
  Pop $0

  nsExec::ExecToLog 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\scripts\generate-node-key.ps1" -NodeName "$ClusterPrefix-worker1" -KeyDirectory "$INSTDIR\.vagrant\node-keys"'
  Pop $0

  nsExec::ExecToLog 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\scripts\generate-node-key.ps1" -NodeName "$ClusterPrefix-worker2" -KeyDirectory "$INSTDIR\.vagrant\node-keys"'
  Pop $0

  ; --- Запуск vagrant up ---
  DetailPrint "$(STR_INSTALL_VAGRANT)"
  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant up"'
  Pop $0

  ${If} $0 != "0"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_VAGRANT_FAIL)"
  ${Else}
    ; Сохраняем Dashboard-токен
    nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl -n kubernetes-dashboard create token admin-user --duration=168h" > "$INSTDIR\dashboard-token.txt" 2>&1"'
    DetailPrint "$(STR_INSTALL_DONE)"
  ${EndIf}

  ; Запись в реестр
  WriteRegStr HKCU "Software\K8sLab" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "DisplayName" "Kubernetes Cluster Lab"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "DisplayVersion" "1.0.0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteUninstaller "$INSTDIR\uninstall.exe"

SectionEnd

; === 9. СТРАНИЦА: ПРОВЕРКА ЗАВИСИМОСТЕЙ ======================================

Function DepsPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_DEPS_TITLE)" "$(STR_DEPS_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDepsDialog
  ${If} $hDepsDialog == error
    Abort
  ${EndIf}

  ; Заголовок
  ${NSD_CreateLabel} 10 5 370 14 "$(STR_DEPS_SUBTITLE):"

  ; Строка: Vagrant
  ${NSD_CreateLabel} 10 28 200 14 "$(STR_DEPS_VAGRANT):"
  ; Проверяем Vagrant через nsExec
  nsExec::ExecToStack 'cmd.exe /C "vagrant --version"'
  Pop $0  ; exit code
  Pop $1  ; output
  ${If} $0 == "0"
    ${NSD_CreateLabel} 215 28 155 14 "$(STR_DEPS_OK)"
  ${Else}
    ${NSD_CreateLabel} 215 28 155 14 "$(STR_DEPS_MISSING)"
  ${EndIf}

  ; Строка: VirtualBox
  ${NSD_CreateLabel} 10 48 200 14 "$(STR_DEPS_VBOX):"
  nsExec::ExecToStack 'cmd.exe /C "VBoxManage --version"'
  Pop $2
  Pop $3
  ${If} $2 == "0"
    ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_OK)"
  ${Else}
    ; Пробуем стандартный путь
    ${If} ${FileExists} "$PROGRAMFILES\Oracle\VirtualBox\VBoxManage.exe"
      ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_OK)"
      StrCpy $2 "0"
    ${Else}
      ${NSD_CreateLabel} 215 48 155 14 "$(STR_DEPS_MISSING)"
    ${EndIf}
  ${EndIf}

  ; Подсказка
  ${NSD_CreateLabel} 10 78 370 30 "$(STR_DEPS_HINT)"

  nsDialogs::Show
FunctionEnd

Function DepsPageLeave
  ; Проверяем Vagrant
  nsExec::ExecToStack 'cmd.exe /C "vagrant --version"'
  Pop $0
  Pop $1
  ${If} $0 != "0"
    MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_DEPS_WARN_VAGRANT)" IDYES +2
    Abort
  ${EndIf}

  ; Проверяем VirtualBox
  nsExec::ExecToStack 'cmd.exe /C "VBoxManage --version"'
  Pop $0
  Pop $1
  ${If} $0 != "0"
    ${If} ${FileExists} "$PROGRAMFILES\Oracle\VirtualBox\VBoxManage.exe"
      ; OK — найден в стандартном месте
    ${Else}
      MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_DEPS_WARN_VBOX)" IDYES +2
      Abort
    ${EndIf}
  ${EndIf}
FunctionEnd

; === 10. СТРАНИЦА: КОНФИГУРАЦИЯ КЛАСТЕРА =====================================

Function ConfigPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_CONFIG_TITLE)" "$(STR_CONFIG_SUBTITLE)"

  ; Значения по умолчанию
  ${If} $ClusterPrefix == ""
    StrCpy $ClusterPrefix "lab-k8s"
  ${EndIf}
  ${If} $WorkerCount == ""
    StrCpy $WorkerCount "2"
  ${EndIf}
  ${If} $CpuCount == ""
    StrCpy $CpuCount "2"
  ${EndIf}
  ${If} $RamMb == ""
    StrCpy $RamMb "2048"
  ${EndIf}
  ${If} $SubnetPrefix == ""
    StrCpy $SubnetPrefix "192.168.56"
  ${EndIf}

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ; Поле: Префикс
  ${NSD_CreateLabel} 10 10 200 14 "$(STR_CONFIG_PREFIX):"
  ${NSD_CreateText}  215 8  150 16 "$ClusterPrefix"
  Pop $hPrefixField

  ; Поле: Воркеры
  ${NSD_CreateLabel} 10 32 200 14 "$(STR_CONFIG_WORKERS):"
  ${NSD_CreateText}  215 30 150 16 "$WorkerCount"
  Pop $hWorkersField

  ; Поле: CPU
  ${NSD_CreateLabel} 10 54 200 14 "$(STR_CONFIG_CPU):"
  ${NSD_CreateText}  215 52 150 16 "$CpuCount"
  Pop $hCpuField

  ; Поле: RAM
  ${NSD_CreateLabel} 10 76 200 14 "$(STR_CONFIG_RAM):"
  ${NSD_CreateText}  215 74 150 16 "$RamMb"
  Pop $hRamField

  ; Поле: Подсеть
  ${NSD_CreateLabel} 10 98 200 14 "$(STR_CONFIG_SUBNET):"
  ${NSD_CreateText}  215 96 150 16 "$SubnetPrefix"
  Pop $hSubnetField

  ; Подсказка
  ${NSD_CreateLabel} 10 126 370 20 "$(STR_CONFIG_TIP)"

  nsDialogs::Show
FunctionEnd

Function ConfigPageLeave
  ${NSD_GetText} $hPrefixField  $ClusterPrefix
  ${NSD_GetText} $hWorkersField $WorkerCount
  ${NSD_GetText} $hCpuField     $CpuCount
  ${NSD_GetText} $hRamField     $RamMb
  ${NSD_GetText} $hSubnetField  $SubnetPrefix

  ; Валидация префикса
  StrLen $0 $ClusterPrefix
  ${If} $0 < 2
    MessageBox MB_OK|MB_ICONEXCLAMATION "Префикс слишком короткий (минимум 2 символа)."
    Abort
  ${EndIf}

  ; Валидация числа воркеров
  IntCmp $WorkerCount 1 +3 +3 0
  IntCmp $WorkerCount 4 0 0 +2
  Goto +3
  MessageBox MB_OK|MB_ICONEXCLAMATION "Количество воркеров: от 1 до 4."
  Abort
FunctionEnd

; === 11. СТРАНИЦА: СВОДКА НАСТРОЕК ===========================================

Function SummaryPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_SUMMARY_TITLE)" "$(STR_SUMMARY_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog

  ${NSD_CreateLabel} 10 5  370 14 "$(STR_SUMMARY_HEADER)"
  ${NSD_CreateLabel} 10 25 160 14 "$(STR_SUMMARY_PREFIX)"
  ${NSD_CreateLabel} 175 25 195 14 "$ClusterPrefix"
  ${NSD_CreateLabel} 10 42 160 14 "$(STR_SUMMARY_WORKERS)"
  ${NSD_CreateLabel} 175 42 195 14 "$WorkerCount"
  ${NSD_CreateLabel} 10 59 160 14 "$(STR_SUMMARY_CPU)"
  ${NSD_CreateLabel} 175 59 195 14 "$CpuCount"
  ${NSD_CreateLabel} 10 76 160 14 "$(STR_SUMMARY_RAM)"
  ${NSD_CreateLabel} 175 76 195 14 "$RamMb MB"
  ${NSD_CreateLabel} 10 93 160 14 "$(STR_SUMMARY_SUBNET)"
  ${NSD_CreateLabel} 175 93 195 14 "$SubnetPrefix.0/24"
  ${NSD_CreateLabel} 10 110 160 14 "$(STR_SUMMARY_DIR)"
  ${NSD_CreateLabel} 175 110 195 14 "$INSTDIR"
  ${NSD_CreateLabel} 10 138 370 30 "$(STR_SUMMARY_NOTE)"

  nsDialogs::Show
FunctionEnd

Function SummaryPageLeave
  ; Пользователь подтвердил — ничего не делаем
FunctionEnd

; === 12. ДЕИНСТАЛЛЯТОР =======================================================

Section "Uninstall"
  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant destroy -f"'

  RMDir /r "$INSTDIR\.vagrant"
  RMDir /r "$INSTDIR\scripts"
  Delete "$INSTDIR\.env"
  Delete "$INSTDIR\.env.example"
  Delete "$INSTDIR\.gitignore"
  Delete "$INSTDIR\Vagrantfile"
  Delete "$INSTDIR\dashboard-token.txt"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\uninstall.exe"

  DeleteRegKey HKCU "Software\K8sLab"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab"

  RMDir "$INSTDIR"
SectionEnd
