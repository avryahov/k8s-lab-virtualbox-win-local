; =============================================================================
; k8s-lab.nsi — NSIS-установщик Kubernetes Cluster Lab
; =============================================================================
;
; ЧТО ТАКОЕ NSIS:
;   Nullsoft Scriptable Install System — бесплатная система создания инсталляторов
;   для Windows. Используется для создания .exe-установщиков.
;   Сайт: https://nsis.sourceforge.io/
;
; КАК СКОМПИЛИРОВАТЬ:
;   makensis k8s-lab.nsi
;   → создаст k8s-lab-setup.exe в этой же папке
;
; КАК УСТАНОВИТЬ NSIS:
;   winget install NSIS.NSIS
;   или скачай с https://nsis.sourceforge.io/Download
;
; СТРУКТУРА ЭТОГО ФАЙЛА:
;   1. Заголовок (мета-информация об установщике)
;   2. Подключение языковых файлов и плагинов
;   3. Страницы визарда (по порядку)
;   4. Секции установки (что именно делать)
;   5. Вспомогательные функции
;
; ДОКУМЕНТАЦИЯ NSIS:
;   https://nsis.sourceforge.io/Docs/
; =============================================================================

; === РАЗДЕЛ 1: ЗАГОЛОВОК =====================================================

; Имя продукта — отображается в заголовке окна и в Programs & Features
Name "Kubernetes Cluster Lab"

; Имя выходного файла
OutFile "k8s-lab-setup.exe"

; Иконка установщика (опционально, нужен .ico файл)
; Icon "assets\k8s-logo.ico"

; Каталог по умолчанию — куда будут скопированы файлы
InstallDir "$DOCUMENTS\k8s-lab"

; Запросить подтверждение при перезаписи существующей папки
InstallDirRegKey HKCU "Software\K8sLab" "InstallDir"

; Уровень сжатия (lzma = максимальное, bzip2 = быстрое)
SetCompressor /SOLID lzma

; Версия установщика (отображается в свойствах exe)
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "Kubernetes Cluster Lab"
VIAddVersionKey "ProductVersion" "1.0.0"
VIAddVersionKey "FileDescription" "Kubernetes lab installer for Windows"
VIAddVersionKey "LegalCopyright" "MIT License"

; === РАЗДЕЛ 2: ПЛАГИНЫ И ЯЗЫКИ ===============================================

; Modern UI 2 — современный интерфейс визарда (как у стандартных Windows-установщиков)
; Документация: https://nsis.sourceforge.io/Docs/Modern%20UI%202/Readme.html
!include "MUI2.nsh"

; NSD — NSIS Dialog — для создания пользовательских страниц с полями ввода
; Документация: https://nsis.sourceforge.io/NsDialogs_Usage
!include "nsDialogs.nsh"

; Логические операторы
!include "LogicLib.nsh"

; Работа со строками
!include "StrFunc.nsh"
${StrStr}

; Языковые файлы (должны идти ПОСЛЕ !include MUI2.nsh)
; LangString позволяет задать строки на разных языках.
; Во время работы программы используется текущий системный язык.
!include "lang\russian.nsh"
!include "lang\english.nsh"

; Поддерживаемые языки (порядок определяет первый предложенный)
!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

; === РАЗДЕЛ 3: НАСТРОЙКИ ВНЕШНЕГО ВИДА =======================================

; Цветовая схема заголовка (чёрный текст, белый фон)
!define MUI_HEADERIMAGE
; !define MUI_HEADERIMAGE_BITMAP "assets\banner.bmp"  ; опционально
!define MUI_ABORTWARNING
!define MUI_ABORTWARNING_TEXT "Прервать установку?"

; Кнопки навигации
!define MUI_BUTTONTEXT_NEXT "Далее >"
!define MUI_BUTTONTEXT_BACK "< Назад"
!define MUI_BUTTONTEXT_CANCEL "Отмена"
!define MUI_BUTTONTEXT_FINISH "Готово"

; === РАЗДЕЛ 4: ПЕРЕМЕННЫЕ ====================================================

; Переменные для хранения пользовательского ввода
Var ClusterPrefix    ; Префикс имён ВМ (например: lab-k8s)
Var WorkerCount      ; Количество воркеров (1–4)
Var CpuCount         ; CPU на ВМ (1–8)
Var RamMb            ; RAM в МБ (512–16384)
Var SubnetPrefix     ; Первые три октета подсети (например: 192.168.56)

; Переменные для элементов диалога (поля ввода)
Var hDialog
Var hPrefixField
Var hWorkersField
Var hCpuField
Var hRamField
Var hSubnetField

; Переменная для страницы проверки зависимостей
Var hDepsDialog
Var hVagrantStatus
Var hVboxStatus

; === РАЗДЕЛ 5: СТРАНИЦЫ ВИЗАРДА ==============================================
;
; Порядок страниц: Welcome → Deps → License → Config → Dir → Summary → Install → Finish
;
; !insertmacro MUI_PAGE_* — стандартные страницы Modern UI
; Page custom <функция> — пользовательская страница

; Страница 1: Приветствие
!insertmacro MUI_PAGE_WELCOME

; Страница 2: Проверка зависимостей (кастомная)
Page custom DepsPageCreate DepsPageLeave

; Страница 3: Лицензия
!insertmacro MUI_PAGE_LICENSE "..\..\LICENSE"

; Страница 4: Конфигурация кластера (кастомная)
Page custom ConfigPageCreate ConfigPageLeave

; Страница 5: Выбор папки установки
!insertmacro MUI_PAGE_DIRECTORY

; Страница 6: Сводка настроек (кастомная)
Page custom SummaryPageCreate SummaryPageLeave

; Страница 7: Установка (прогресс)
!insertmacro MUI_PAGE_INSTFILES

; Страница 8: Завершение
!define MUI_FINISHPAGE_RUN "$INSTDIR\launch.bat"
!define MUI_FINISHPAGE_RUN_TEXT "Открыть папку проекта"
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\README.md"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Открыть README"
!insertmacro MUI_PAGE_FINISH

; === РАЗДЕЛ 6: СЕКЦИЯ УСТАНОВКИ ==============================================

Section "Kubernetes Lab" SecMain

  ; Проверяем права администратора (нужны для Vagrant + VirtualBox)
  UserInfo::GetAccountType
  Pop $0
  ${If} $0 != "Admin"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_NO_ADMIN)"
    Abort
  ${EndIf}

  ; Устанавливаем папку назначения
  SetOutPath "$INSTDIR"

  DetailPrint "$(STR_INSTALL_COPY)"

  ; Копируем файлы проекта (stage2/) в папку установки
  ; File /r "../*.env.example"  ; .env.example
  File /r "..\.env.example"
  File /r "..\Vagrantfile"
  File /r "..\scripts\*"
  File /r "..\..\docs\*"
  CreateDirectory "$INSTDIR\scripts"
  CreateDirectory "$INSTDIR\docs"

  ; ------------------------------------------------------------------
  ; Создаём .env из пользовательских настроек
  ; ------------------------------------------------------------------
  DetailPrint "$(STR_INSTALL_CONFIG)"

  ; Пишем .env файл с параметрами, которые ввёл пользователь
  FileOpen $0 "$INSTDIR\.env" w
  FileWrite $0 "# Создано установщиком k8s-lab-setup.exe$\r$\n"
  FileWrite $0 "# Дата: $(NSIS_BUILD_DATETIME)$\r$\n$\r$\n"
  FileWrite $0 "# Именование кластера$\r$\n"
  FileWrite $0 "CLUSTER_PREFIX=$ClusterPrefix$\r$\n"
  FileWrite $0 "MASTER_VM_NAME=$ClusterPrefix-master$\r$\n"
  FileWrite $0 "MASTER_HOSTNAME=$ClusterPrefix-master$\r$\n$\r$\n"
  FileWrite $0 "# Образ и ресурсы$\r$\n"
  FileWrite $0 "VM_BOX=bento/ubuntu-24.04$\r$\n"
  FileWrite $0 "VM_CPUS=$CpuCount$\r$\n"
  FileWrite $0 "VM_MEMORY_MB=$RamMb$\r$\n"
  FileWrite $0 "VM_BOOT_TIMEOUT=600$\r$\n"
  FileWrite $0 "WORKER_COUNT=$WorkerCount$\r$\n$\r$\n"
  FileWrite $0 "# Сеть$\r$\n"
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
  FileWrite $0 "# Kubernetes$\r$\n"
  FileWrite $0 "KUBERNETES_VERSION=1.34$\r$\n"
  FileWrite $0 "POD_CIDR=10.244.0.0/16$\r$\n"
  FileClose $0

  ; ------------------------------------------------------------------
  ; Генерируем SSH-ключи через PowerShell
  ; ------------------------------------------------------------------
  DetailPrint "$(STR_INSTALL_KEYS)"

  ; Создаём папку для ключей
  CreateDirectory "$INSTDIR\.vagrant\node-keys"

  ; Генерируем ключи для master и воркеров
  nsExec::ExecToLog 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\scripts\generate-node-key.ps1" -NodeName "$ClusterPrefix-master" -KeyDirectory "$INSTDIR\.vagrant\node-keys"'
  Pop $0

  nsExec::ExecToLog 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\scripts\generate-node-key.ps1" -NodeName "$ClusterPrefix-worker1" -KeyDirectory "$INSTDIR\.vagrant\node-keys"'
  Pop $0

  ${If} $WorkerCount >= "2"
    nsExec::ExecToLog 'powershell.exe -ExecutionPolicy Bypass -File "$INSTDIR\scripts\generate-node-key.ps1" -NodeName "$ClusterPrefix-worker2" -KeyDirectory "$INSTDIR\.vagrant\node-keys"'
    Pop $0
  ${EndIf}

  ; ------------------------------------------------------------------
  ; Запускаем vagrant up
  ; ------------------------------------------------------------------
  DetailPrint "$(STR_INSTALL_VAGRANT)"

  ; Запускаем vagrant up в папке проекта
  ; nsExec::ExecToLog выводит вывод команды в Detail window
  SetDetailsPrint textonly
  DetailPrint "Выполняется: vagrant up (до 30 минут)..."
  SetDetailsPrint listonly

  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant up"'
  Pop $0

  ${If} $0 != "0"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(STR_ERR_VAGRANT_FAIL)"
    ; Не прерываем — пользователь увидит ошибку и может попробовать сам
  ${Else}
    ; Сохраняем токен Dashboard в файл
    nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant ssh $ClusterPrefix-master --command "kubectl -n kubernetes-dashboard create token admin-user --duration=168h" > "$INSTDIR\dashboard-token.txt"'
    DetailPrint "$(STR_INSTALL_DONE)"
  ${EndIf}

  ; Запись в реестр для Programs & Features
  WriteRegStr HKCU "Software\K8sLab" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "DisplayName" "Kubernetes Cluster Lab"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "DisplayVersion" "1.0.0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "Publisher" "k8s-lab"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab" \
    "UninstallString" '"$INSTDIR\uninstall.exe"'

  WriteUninstaller "$INSTDIR\uninstall.exe"

SectionEnd

; === РАЗДЕЛ 7: СТРАНИЦА ПРОВЕРКИ ЗАВИСИМОСТЕЙ ================================

Function DepsPageCreate
  ; Создаём пользовательский диалог (страницу визарда)
  !insertmacro MUI_HEADER_TEXT "$(STR_DEPS_TITLE)" "$(STR_DEPS_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDepsDialog
  ${If} $hDepsDialog == error
    Abort
  ${EndIf}

  ; Проверяем Vagrant
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 10 370 20 "$(STR_DEPS_VAGRANT):"
  Pop $0

  ; Ищем vagrant.exe в PATH
  SearchPath $1 vagrant.exe
  ${If} $1 != ""
    StrCpy $2 "$(STR_DEPS_OK)"
  ${Else}
    StrCpy $2 "$(STR_DEPS_MISSING)"
  ${EndIf}

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 200 10 180 20 "$2"
  Pop $hVagrantStatus

  ; Проверяем VirtualBox
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 35 370 20 "$(STR_DEPS_VBOX):"
  Pop $0

  SearchPath $3 VBoxManage.exe
  ${If} $3 == ""
    ; Пробуем стандартный путь
    ${If} ${FileExists} "$PROGRAMFILES\Oracle\VirtualBox\VBoxManage.exe"
      StrCpy $3 "$PROGRAMFILES\Oracle\VirtualBox\VBoxManage.exe"
    ${EndIf}
  ${EndIf}

  ${If} $3 != ""
    StrCpy $4 "$(STR_DEPS_OK)"
  ${Else}
    StrCpy $4 "$(STR_DEPS_MISSING)"
  ${EndIf}

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 200 35 180 20 "$4"
  Pop $hVboxStatus

  ; Пояснительный текст
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 70 370 60 \
    "Если что-то не найдено — установи недостающую программу и перезапусти мастер установки."
  Pop $0

  nsDialogs::Show
FunctionEnd

Function DepsPageLeave
  ; Проверяем оба компонента — если нет хотя бы одного, предупреждаем
  SearchPath $1 vagrant.exe
  ${If} $1 == ""
    MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_DEPS_WARN_VAGRANT)$\n$\nПродолжить без Vagrant?" IDYES +2
    Abort
  ${EndIf}

  SearchPath $2 VBoxManage.exe
  ${If} $2 == ""
    ${If} ${FileExists} "$PROGRAMFILES\Oracle\VirtualBox\VBoxManage.exe"
      ; Нашли, OK
    ${Else}
      MessageBox MB_YESNO|MB_ICONEXCLAMATION "$(STR_DEPS_WARN_VBOX)$\n$\nПродолжить без VirtualBox?" IDYES +2
      Abort
    ${EndIf}
  ${EndIf}
FunctionEnd

; === РАЗДЕЛ 8: СТРАНИЦА КОНФИГУРАЦИИ =========================================

Function ConfigPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_CONFIG_TITLE)" "$(STR_CONFIG_SUBTITLE)"

  ; Устанавливаем значения по умолчанию
  StrCmp $ClusterPrefix "" 0 +2
  StrCpy $ClusterPrefix "lab-k8s"

  StrCmp $WorkerCount "" 0 +2
  StrCpy $WorkerCount "2"

  StrCmp $CpuCount "" 0 +2
  StrCpy $CpuCount "2"

  StrCmp $RamMb "" 0 +2
  StrCpy $RamMb "2048"

  StrCmp $SubnetPrefix "" 0 +2
  StrCpy $SubnetPrefix "192.168.56"

  nsDialogs::Create 1018
  Pop $hDialog
  ${If} $hDialog == error
    Abort
  ${EndIf}

  ; Поле: Префикс
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 10 230 14 "$(STR_CONFIG_PREFIX):"
  Pop $0
  nsDialogs::CreateControl EDIT ${WS_VISIBLE}|${WS_CHILD}|${WS_TABSTOP}|${WS_BORDER} 0 245 8 120 16 "$ClusterPrefix"
  Pop $hPrefixField

  ; Поле: Воркеры
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 32 230 14 "$(STR_CONFIG_WORKERS):"
  Pop $0
  nsDialogs::CreateControl EDIT ${WS_VISIBLE}|${WS_CHILD}|${WS_TABSTOP}|${WS_BORDER} 0 245 30 120 16 "$WorkerCount"
  Pop $hWorkersField

  ; Поле: CPU
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 54 230 14 "$(STR_CONFIG_CPU):"
  Pop $0
  nsDialogs::CreateControl EDIT ${WS_VISIBLE}|${WS_CHILD}|${WS_TABSTOP}|${WS_BORDER} 0 245 52 120 16 "$CpuCount"
  Pop $hCpuField

  ; Поле: RAM
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 76 230 14 "$(STR_CONFIG_RAM):"
  Pop $0
  nsDialogs::CreateControl EDIT ${WS_VISIBLE}|${WS_CHILD}|${WS_TABSTOP}|${WS_BORDER} 0 245 74 120 16 "$RamMb"
  Pop $hRamField

  ; Поле: Подсеть
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 98 230 14 "$(STR_CONFIG_SUBNET):"
  Pop $0
  nsDialogs::CreateControl EDIT ${WS_VISIBLE}|${WS_CHILD}|${WS_TABSTOP}|${WS_BORDER} 0 245 96 120 16 "$SubnetPrefix"
  Pop $hSubnetField

  ; Подсказка
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 125 360 20 "$(STR_CONFIG_TIP)"
  Pop $0

  nsDialogs::Show
FunctionEnd

Function ConfigPageLeave
  ; Читаем значения из полей ввода
  ${NSD_GetText} $hPrefixField  $ClusterPrefix
  ${NSD_GetText} $hWorkersField $WorkerCount
  ${NSD_GetText} $hCpuField     $CpuCount
  ${NSD_GetText} $hRamField     $RamMb
  ${NSD_GetText} $hSubnetField  $SubnetPrefix

  ; Базовая валидация
  StrLen $0 $ClusterPrefix
  ${If} $0 < 2
    MessageBox MB_OK|MB_ICONEXCLAMATION "Префикс должен быть не короче 2 символов."
    Abort
  ${EndIf}

  IntCmp $WorkerCount 1 +3
  IntCmp $WorkerCount 4 +2
  ${If} $WorkerCount > "4"
    MessageBox MB_OK|MB_ICONEXCLAMATION "Количество воркеров: от 1 до 4."
    Abort
  ${EndIf}
FunctionEnd

; === РАЗДЕЛ 9: СТРАНИЦА СВОДКИ ===============================================

Function SummaryPageCreate
  !insertmacro MUI_HEADER_TEXT "$(STR_SUMMARY_TITLE)" "$(STR_SUMMARY_SUBTITLE)"

  nsDialogs::Create 1018
  Pop $hDialog

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 5 360 14 "$(STR_SUMMARY_HEADER)"
  Pop $0

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 25 180 14 "$(STR_SUMMARY_PREFIX)"
  Pop $0
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 195 25 175 14 "$ClusterPrefix"
  Pop $0

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 42 180 14 "$(STR_SUMMARY_WORKERS)"
  Pop $0
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 195 42 175 14 "$WorkerCount"
  Pop $0

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 59 180 14 "$(STR_SUMMARY_CPU)"
  Pop $0
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 195 59 175 14 "$CpuCount"
  Pop $0

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 76 180 14 "$(STR_SUMMARY_RAM)"
  Pop $0
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 195 76 175 14 "$RamMb MB"
  Pop $0

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 93 180 14 "$(STR_SUMMARY_SUBNET)"
  Pop $0
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 195 93 175 14 "$SubnetPrefix.0/24"
  Pop $0

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 110 180 14 "$(STR_SUMMARY_DIR)"
  Pop $0
  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 195 110 175 14 "$INSTDIR"
  Pop $0

  nsDialogs::CreateControl STATIC ${WS_VISIBLE}|${WS_CHILD} 0 10 138 360 28 "$(STR_SUMMARY_NOTE)"
  Pop $0

  nsDialogs::Show
FunctionEnd

Function SummaryPageLeave
  ; Ничего не делаем — пользователь подтвердил, идём к установке
FunctionEnd

; === РАЗДЕЛ 10: ДЕИНСТАЛЛЯТОР ================================================

Section "Uninstall"
  ; Останавливаем и удаляем ВМ
  nsExec::ExecToLog 'cmd.exe /C "cd /d "$INSTDIR" && vagrant destroy -f"'

  ; Удаляем файлы
  RMDir /r "$INSTDIR\.vagrant"
  RMDir /r "$INSTDIR\scripts"
  RMDir /r "$INSTDIR\docs"
  Delete "$INSTDIR\.env"
  Delete "$INSTDIR\Vagrantfile"
  Delete "$INSTDIR\dashboard-token.txt"
  Delete "$INSTDIR\uninstall.exe"

  ; Удаляем записи реестра
  DeleteRegKey HKCU "Software\K8sLab"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\K8sLab"

  RMDir "$INSTDIR"
SectionEnd
