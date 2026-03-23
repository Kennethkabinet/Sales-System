; Inno Setup Script for SGCO
; Build with Inno Setup 6+

#define AppName "SGCO"
#define AppVersion "1.0"
#define AppPublisher "KO"
#define AppExeName "SGCO.exe"

; Optional license file (used only if it exists next to this .iss file)
#define LicenseFile "License.txt"

[Setup]
AppId={{8D0D7A6A-1F7B-4E9B-8C1B-9A0A4C2B7B5F}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}

DefaultDirName={autopf}\KO\SGCO
DefaultGroupName=KO\SGCO

OutputBaseFilename=SGCO_Setup_{#AppVersion}
OutputDir=.

Compression=lzma2
SolidCompression=yes

PrivilegesRequired=admin

; x86 + x64 support
; (x64 is deprecated in IS6; use x64compatible)
ArchitecturesAllowed=x86 x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; UI / progress
DisableProgramGroupPage=yes
WizardStyle=modern

; Add/Remove Programs display
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}

#ifexist "{#LicenseFile}"
LicenseFile={#LicenseFile}
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Package everything under C:\SGCO into the install directory
Source: "C:\SGCO\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu shortcut under KO\SGCO
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
; Desktop shortcut named SGCO
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"

[Registry]
; Optional: register App Path so Windows can locate SGCO.exe
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#AppExeName}"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExeName}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#AppExeName}"; ValueType: string; ValueName: "Path"; ValueData: "{app}"; Flags: uninsdeletevalue

; Inno Setup automatically creates an uninstaller and registers it in Add/Remove Programs.
