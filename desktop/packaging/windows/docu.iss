#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

[Setup]
AppId=docu.desktop
AppName=docu
AppVersion={#MyAppVersion}
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

[Icons]
Name: "{group}\docu"; Filename: "{app}\docapp.exe"
Name: "{userdesktop}\docu"; Filename: "{app}\docapp.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional options:"

[Run]
Filename: "{app}\docapp.exe"; Description: "Launch docu"; Flags: nowait postinstall skipifsilent
