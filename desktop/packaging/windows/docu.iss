#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

[Setup]
AppId=docu.desktop
AppName=docu
AppVersion={#MyAppVersion}
ChangesAssociations=yes
DefaultDirName={localappdata}\Programs\docu
DefaultGroupName=docu
OutputDir=..\..\release
OutputBaseFilename=docu-windows-x64-setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Registry]
Root: HKA; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "docu.PDF"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\docu.PDF"; ValueType: string; ValueData: "docu PDF document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\docu.PDF\DefaultIcon"; ValueType: string; ValueData: "{app}\docapp.exe,0"
Root: HKA; Subkey: "Software\Classes\docu.PDF\shell\open\command"; ValueType: string; ValueData: """{app}\docapp.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\docapp.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "docu"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\docapp.exe\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\docapp.exe\shell\open\command"; ValueType: string; ValueData: """{app}\docapp.exe"" ""%1"""

[Icons]
Name: "{group}\docu"; Filename: "{app}\docapp.exe"
Name: "{userdesktop}\docu"; Filename: "{app}\docapp.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional options:"

[Run]
Filename: "{app}\docapp.exe"; Description: "Launch docu"; Flags: nowait postinstall skipifsilent
