;NSIS Modern User Interface

;--------------------------------
!include "MUI2.nsh"
  
!include nsDialogs.nsh
!include Sections.nsh
!include LogicLib.nsh
;--------------------------------
;General
  
  !define PACKAGE_NAME "RCS-OCR"
  !Define /file PACKAGE_VERSION "..\config\VERSION_BUILD"

  ;Name and file
  Name "RCS-OCR"
  OutFile "rcs-ocr-${PACKAGE_VERSION}.exe"

  ;Default installation folder
  InstallDir "C:\RCS\"

  ShowInstDetails "show"
  ShowUnInstDetails "show"
  
  !include "WordFunc.nsh"

;--------------------------------

!macro _RunningX64 _a _b _t _f
  !insertmacro _LOGICLIB_TEMP
  System::Call kernel32::GetCurrentProcess()i.s
  System::Call kernel32::IsWow64Process(is,*i.s)
  Pop $_LOGICLIB_TEMP
  !insertmacro _!= $_LOGICLIB_TEMP 0 `${_t}` `${_f}`
!macroend

!define RunningX64 `"" RunningX64 ""`

;--------------------------------
;Interface Settings

  !define MUI_ABORTWARNING
  !define MUI_WELCOMEFINISHPAGE_BITMAP "HT.bmp"
  !define MUI_WELCOMEFINISHPAGE_BITMAP_NOSTRETCH
  !define MUI_ICON "RCS.ico"
  !define MUI_UNICON "RCS.ico"
  BrandingText "]HackingTeam[ ${PACKAGE_NAME} (${PACKAGE_VERSION})"

;--------------------------------
;Pages

  !insertmacro MUI_PAGE_WELCOME
  !insertmacro MUI_PAGE_INSTFILES

  ;Uninstaller pages
  !insertmacro MUI_UNPAGE_WELCOME
  !insertmacro MUI_UNPAGE_INSTFILES

;--------------------------------
;Languages

  !insertmacro MUI_LANGUAGE "English"

;--------------------------------

!macro _EnvSet
   ReadRegStr $R0 HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path"
   StrCpy $R0 "$R0;$INSTDIR\DB\ocr"
   WriteRegExpandStr HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path" "$R0"
   System::Call 'Kernel32::SetEnvironmentVariableA(t, t) i("Path", "$R0").r0'

   SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
!macroend
!define EnvSet "!insertmacro _EnvSet"

;--------------------------------
;Installer Sections

Section "Install Section" SecInstall

  SetDetailsPrint "both"

  DetailPrint "Setting up the path..."
  ${EnvSet}
  DetailPrint "done"

  DetailPrint "Stopping RCS OCR..."
  SimpleSC::StopService "RCSOCR" 1

  DetailPrint "Extracting OCR files..."
  SetDetailsPrint "textonly"
  !cd '..'
  SetOutPath "$INSTDIR\DB\ocr"
  File /r "ocr\*.*"

  SetOutPath "$INSTDIR\DB\lib"
  File "lib\rcs-ocr.rb"

  SetOutPath "$INSTDIR\DB\lib\rcs-ocr-release"
  File /r "lib\rcs-ocr-release\*.*"

  SetOutPath "$INSTDIR\DB\bin"
  File /r "bin\rcs-ocr"

  SetDetailsPrint "both"
  DetailPrint "done"

  ReadRegDWORD $R0 HKLM "Software\HT\RCS" "ocr"
  IntCmp $R0 1 alreadyinstalled

    DetailPrint "Creating service RCS OCR..."
    nsExec::Exec "$INSTDIR\DB\bin\nssm.exe install RCSOCR $INSTDIR\Ruby\bin\ruby.exe $INSTDIR\DB\bin\rcs-ocr"
    SimpleSC::SetServiceFailure "RCSOCR" "0" "" "" "1" "60000" "1" "60000" "1" "60000"
    WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\RCSOCR" "DisplayName" "RCS OCR"
    WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\RCSOCR" "Description" "Remote Control System OCR processor"
    DetailPrint "done"

    WriteRegDWORD HKLM "Software\HT\RCS" "ocr" 0x00000001

    nsExec::Exec "reg import $INSTDIR\DB\ocr\ocr-key.reg"

  alreadyinstalled:

  DetailPrint "Starting RCS OCR..."
  SimpleSC::StartService "RCSOCR" "" 30

  !cd "nsis"

  DetailPrint "Writing uninstall informations..."
  SetDetailsPrint "textonly"
  WriteUninstaller "$INSTDIR\setup\RCS-ORC-uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSOCR" "DisplayName" "RCS OCR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSOCR" "DisplayIcon" "$INSTDIR\setup\RCS.ico"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSOCR" "DisplayVersion" "${PACKAGE_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSOCR" "UninstallString" "$INSTDIR\setup\RCS-OCR-uninstall.exe"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSOCR" "NoModify" 0x00000001
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSOCR" "NoRepair" 0x00000001
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSOCR" "InstDir" "$INSTDIR"

  SetDetailsPrint "both"

SectionEnd

Section Uninstall
  DetailPrint "Stopping RCS OCR Services..."
  SimpleSC::StopService "RCSOCR" 1
  DetailPrint "done"

  DetailPrint "Removing RCS OCR Services..."
  SimpleSC::RemoveService "RCSOCR"
  DetailPrint "done"

  DetailPrint ""
  DetailPrint "Deleting files..."
  SetDetailsPrint "textonly"
  ReadRegStr $INSTDIR HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCS" "InstDir"

  RMDir /r "$INSTDIR\DB\ocr"

  SetDetailsPrint "both"
  DetailPrint "done"

  DetailPrint ""
  DetailPrint "Removing registry keys..."
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSOCR"
  DeleteRegKey HKLM "Software\HT\RCS\ocr"
  DetailPrint "done"

SectionEnd


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Function .onInit

  ${IfNot} ${RunningX64}
    MessageBox MB_OK "RCS can be installed only on 64 bit systems"
    Quit
  ${EndIf}

  ReadRegDWORD $R0 HKLM "Software\HT\RCS" "installed"

  ; RCS is not installed
  IntCmp $R0 1 +3 0 0
    MessageBox MB_OK "RCS OCR can be installed only if RCS is already installed"
    Quit

FunctionEnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
