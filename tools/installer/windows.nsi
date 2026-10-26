; Bunny Beat Down: the Windows installer (NSIS 3), built by the release
; workflow next to the portable zip:
;
;   makensis -DVERSION=0.9.2 -DEXE=/abs/BunnyBeatDown.exe -DOUT=/abs/BunnyBeatDown-Setup.exe tools/installer/windows.nsi
;
; Installs for the current user (no admin prompt) into
; %LOCALAPPDATA%\Programs\Bunny Beat Down, puts "Bunny Beat Down" on the
; desktop and in the Start menu (with Bun as the icon), and registers an
; uninstaller in Settings > Apps. Installing a newer version over an older one
; just replaces the game. Saves and settings live in %APPDATA%\Godot and are
; never touched, not even by the uninstaller.

Unicode true
!include "MUI2.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef EXE
  !error "pass -DEXE=<path to BunnyBeatDown.exe>"
!endif
!ifndef OUT
  !define OUT "BunnyBeatDown-Setup.exe"
!endif
!define APP "Bunny Beat Down"
!define KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\BunnyBeatDown"
!ifndef ICON
  !define ICON "bunny-beat-down.ico"   ; (makensis runs in this folder)
!endif

Name "${APP}"
Caption "${APP} ${VERSION} setup"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "Software\${APP}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${APP} ${VERSION}"

; (Windows version info wants four numbers: 0.9.2 -> 0.9.2.0)
!searchparse /noerrors "${VERSION}.0.0.0" "" V1 "." V2 "." V3 "." V4 "."
VIProductVersion "${V1}.${V2}.${V3}.${V4}"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APP} setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "CompanyName" "Zachary Connor"
VIAddVersionKey "LegalCopyright" "MIT (code); assets under their own licenses (see Credits)"

!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "This puts ${APP} on your computer, with a shortcut on your desktop and in the Start menu.$\r$\n$\r$\nA bunny in an acorn helmet against 49 woodland critters who remember you. Carrot guns included."
!define MUI_FINISHPAGE_RUN "$INSTDIR\BunnyBeatDown.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Play ${APP} now"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$INSTDIR"
  File "/oname=BunnyBeatDown.exe" "${EXE}"
  File "/oname=bunny-beat-down.ico" "${ICON}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; the desktop launcher and the Start menu
  CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\BunnyBeatDown.exe" "" "$INSTDIR\bunny-beat-down.ico" 0 SW_SHOWNORMAL "" "Play ${APP}"
  CreateDirectory "$SMPROGRAMS\${APP}"
  CreateShortcut "$SMPROGRAMS\${APP}\${APP}.lnk" "$INSTDIR\BunnyBeatDown.exe" "" "$INSTDIR\bunny-beat-down.ico" 0
  CreateShortcut "$SMPROGRAMS\${APP}\Uninstall ${APP}.lnk" "$INSTDIR\Uninstall.exe"

  ; Settings > Apps
  WriteRegStr HKCU "Software\${APP}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${KEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${KEY}" "Publisher" "Zachary Connor"
  WriteRegStr HKCU "${KEY}" "DisplayIcon" "$INSTDIR\bunny-beat-down.ico"
  WriteRegStr HKCU "${KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegStr HKCU "${KEY}" "URLInfoAbout" "https://github.com/zconnor100-debug/bunny-beat-down"
  WriteRegDWORD HKCU "${KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APP}.lnk"
  RMDir /r "$SMPROGRAMS\${APP}"
  Delete "$INSTDIR\BunnyBeatDown.exe"
  Delete "$INSTDIR\bunny-beat-down.ico"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "${KEY}"
  DeleteRegKey HKCU "Software\${APP}"
SectionEnd
