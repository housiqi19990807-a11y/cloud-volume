; Inno Setup template for packaging the Flutter Windows release bundle.

#ifndef AppName
  #define AppName "云卷"
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppPublisher
  #define AppPublisher "云卷"
#endif
#ifndef AppInstallDirName
  #define AppInstallDirName "Cloud Volume"
#endif
#ifndef SourceDir
  #error SourceDir must be defined.
#endif
#ifndef OutputDir
  #error OutputDir must be defined.
#endif
#ifndef OutputBaseFilename
  #error OutputBaseFilename must be defined.
#endif
#ifndef ArchitecturesAllowed
  #define ArchitecturesAllowed "x64compatible"
#endif
#ifndef ArchitecturesInstallIn64BitMode
  #define ArchitecturesInstallIn64BitMode "x64compatible"
#endif
#ifndef WinFspMsiPath
  #define WinFspMsiPath "go\mount\embedded\winfsp.msi"
#endif
#ifndef SignTool
  #define SignTool ""
#endif
#ifndef SignPfxPath
  #define SignPfxPath ""
#endif
#ifndef SignPfxPassword
  #define SignPfxPassword ""
#endif
#ifndef SignTimestampUrl
  #define SignTimestampUrl "http://timestamp.digicert.com"
#endif
#ifndef SignSubject
  #define SignSubject ""
#endif

[Setup]
AppId={{B291B621-9AA2-4E6C-9D2A-1F7E44580757}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppInstallDirName}
; Always show the directory page so upgrades can still override the remembered path.
DisableDirPage=no
DefaultGroupName={#AppName}
ArchitecturesAllowed={#ArchitecturesAllowed}
ArchitecturesInstallIn64BitMode={#ArchitecturesInstallIn64BitMode}
DisableProgramGroupPage=yes
Compression=lzma
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
WizardStyle=modern
UninstallDisplayIcon={app}\cloud-volume.exe
; Signing configuration: callers pass either a full `SignTool` command line
; (named-tool indirection, the normal Inno Setup usage), a PFX pair, or just a
; subject name. Only one of these is expected; they are mutually exclusive.
#if SignTool != ""
  #if SignPfxPath != ""
    SignTool=signtool /f "{#SignPfxPath}" /p "{#SignPfxPassword}" /fd sha256 /tr "{#SignTimestampUrl}" /td sha256 $f
  #else
    ; Treat SignTool as a full signtool.exe command line (Inno's named-tool
    ; indirection is not used here) so CI can pass its own complete invocation.
    SignTool={#SignTool}
  #endif
#elif SignPfxPath != ""
SignTool=signtool /f "{#SignPfxPath}" /p "{#SignPfxPassword}" /fd sha256 /tr "{#SignTimestampUrl}" /td sha256 $f
#elif SignSubject != ""
SignTool=signtool /n "{#SignSubject}" /fd sha256 /tr "{#SignTimestampUrl}" /td sha256 $f
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "installwinfsp"; Description: "Install WinFsp (required for the virtual file system mount engine)"; GroupDescription: "Optional components:"; Flags: checkedonce

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Bundle the WinFsp MSI next to the app so the in-app installer can also reuse
; it if the user skips the optional install step during setup.
Source: "{#WinFspMsiPath}"; DestDir: "{app}\winfsp"; DestName: "winfsp.msi"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\cloud-volume.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\cloud-volume.exe"; Tasks: desktopicon

[Run]
; Quietly install WinFsp when the user leaves the optional task checked. The
; MSI itself may still request elevation via UAC.
Filename: "msiexec.exe"; Parameters: "/i ""{app}\winfsp\winfsp.msi"" /qn /norestart"; StatusMsg: "Installing WinFsp..."; Flags: runhidden waituntilterminated; Tasks: installwinfsp
Filename: "{app}\cloud-volume.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
