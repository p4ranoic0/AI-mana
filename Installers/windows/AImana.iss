#define PackageDir "..\..\package"
#ifndef AppVersion
  #define AppVersion "1.2.0"
#endif
[Setup]
AppId={{8CE4A31D-450F-4B18-9825-C986137FB6DB}
AppName=AI·mana
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\AImana
DefaultGroupName=AI·mana
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename=AImana-{#AppVersion}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=AI·mana

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "InstallHelper.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\AI·mana — check setup"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoExit -NoProfile -ExecutionPolicy Bypass -File ""{app}\InstallHelper.ps1"" -Mode doctor"
Name: "{group}\AI·mana — set up again"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoExit -NoProfile -ExecutionPolicy Bypass -File ""{app}\InstallHelper.ps1"" -Mode setup-again"
Name: "{group}\Uninstall AI·mana"; Filename: "{uninstallexe}"

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\InstallHelper.ps1"" -Mode uninstall"; Flags: runhidden waituntilterminated

[Code]
var
  OptionsPage: TInputOptionWizardPage;
  FolderPage: TInputDirWizardPage;
  HasICloud, HasOneDrive: Boolean;
  ICloudIndex, OneDriveIndex, CustomIndex: Integer;
  ResultFile: String;

function Tr(const English, Spanish: String): String;
begin
  if ActiveLanguage = 'es' then Result := Spanish else Result := English;
end;

procedure InitializeWizard;
begin
  HasICloud := DirExists(AddBackslash(GetEnv('USERPROFILE')) + 'iCloudDrive');
  HasOneDrive := GetEnv('OneDrive') <> '';
  OptionsPage := CreateInputOptionPage(wpSelectDir,
    Tr('Where should AI·mana publish your usage?', '¿Dónde debe publicar AI·mana tu uso?'),
    Tr('Choose a folder synced with your phone.', 'Elige una carpeta sincronizada con tu teléfono.'),
    '', True, False);
  ICloudIndex := -1;
  OneDriveIndex := -1;
  if HasICloud then ICloudIndex := OptionsPage.Add('iCloud Drive');
  if HasOneDrive then OneDriveIndex := OptionsPage.Add('OneDrive');
  CustomIndex := OptionsPage.Add(Tr('Choose another folder', 'Elegir otra carpeta'));
  if ICloudIndex >= 0 then OptionsPage.Values[ICloudIndex] := True
  else if OneDriveIndex >= 0 then OptionsPage.Values[OneDriveIndex] := True
  else OptionsPage.Values[CustomIndex] := True;
  FolderPage := CreateInputDirPage(OptionsPage.ID,
    Tr('Publish folder', 'Carpeta de publicación'),
    Tr('The relay file will be saved in AImana inside this folder.', 'El archivo relay se guardará en AImana dentro de esta carpeta.'),
    Tr('Choose the folder your phone can access:', 'Elige la carpeta accesible desde tu teléfono:'), False, '');
  FolderPage.Add('');
  // Always start with a valid folder: the /OUTPUTDIR parameter, then iCloud Drive, OneDrive, or the user folder.
  FolderPage.Values[0] := ExpandConstant('{param:OUTPUTDIR|}');
  if FolderPage.Values[0] = '' then begin
    if HasICloud then FolderPage.Values[0] := AddBackslash(GetEnv('USERPROFILE')) + 'iCloudDrive'
    else if HasOneDrive then FolderPage.Values[0] := GetEnv('OneDrive')
    else FolderPage.Values[0] := GetEnv('USERPROFILE');
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  // A folder given on the command line (silent installs, tests) skips both folder pages.
  Result := (ExpandConstant('{param:OUTPUTDIR|}') <> '') and
            ((PageID = OptionsPage.ID) or (PageID = FolderPage.ID));
end;

procedure CurPageChanged(CurPageID: Integer);
var
  Msg: String;
  Lines: TArrayOfString;
  I: Integer;
begin
  if CurPageID = FolderPage.ID then begin
    if (ICloudIndex >= 0) and OptionsPage.Values[ICloudIndex] then
      FolderPage.Values[0] := AddBackslash(GetEnv('USERPROFILE')) + 'iCloudDrive'
    else if (OneDriveIndex >= 0) and OptionsPage.Values[OneDriveIndex] then
      FolderPage.Values[0] := GetEnv('OneDrive');
  end;
  if (CurPageID = wpFinished) and LoadStringsFromFile(ResultFile, Lines) then begin
    Msg := '';
    for I := 0 to GetArrayLength(Lines) - 1 do Msg := Msg + Lines[I] + #13#10;
    WizardForm.FinishedLabel.AutoSize := False;
    WizardForm.FinishedLabel.Height := ScaleY(240);
    WizardForm.FinishedLabel.Caption := Msg;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = FolderPage.ID then begin
    Result := Trim(FolderPage.Values[0]) <> '';
    if not Result then MsgBox(Tr('Choose a folder first.', 'Primero elige una carpeta.'), mbError, MB_OK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Base, TaskName, Params: String;
  Code: Integer;
begin
  if CurStep <> ssPostInstall then Exit;
  Base := ExpandConstant('{param:OUTPUTDIR|}');
  if Base = '' then Base := FolderPage.Values[0];
  if Base = '' then begin
    if HasICloud then Base := AddBackslash(GetEnv('USERPROFILE')) + 'iCloudDrive'
    else if HasOneDrive then Base := GetEnv('OneDrive')
    else Base := GetEnv('USERPROFILE');
  end;
  TaskName := ExpandConstant('{param:TASKNAME|}');
  ResultFile := ExpandConstant('{tmp}\aimana-install-result.txt');
  Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\InstallHelper.ps1') +
    '" -Mode setup -Language "' + ActiveLanguage + '" -OutputDir "' + Base + '" -ResultFile "' + ResultFile + '"';
  if TaskName <> '' then Params := Params + ' -TaskName "' + TaskName + '"';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params,
    '', SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then
    RaiseException(Tr('AI·mana setup failed. Run “set up again” from the Start menu.',
      'Falló la configuración de AI·mana. Ejecuta “Configurar de nuevo” desde Inicio.'));
end;
