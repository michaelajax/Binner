#define MyAppName "Binner"
#define MyAppVersion "0.0"
#define MyAppPublisher "Binner"
#define MyAppURL "https://github.com/replaysMike/Binner/"
#define MyAppExeName "Binner.Web.exe"

[Setup]
AppId={{5B8E7506-21A8-49BB-B144-6523D0E43E34}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=..\Binner.Web\LICENSE
OutputDir=.\
OutputBaseFilename=BinnerSetup-win10x64-{#MyAppVersion}
SetupIconFile=.\binner128x128.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardImageFile=.\WizardLarge.bmp
WizardSmallImageFile=.\WizardSmall.bmp
CloseApplications=force


[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
UninstallingService=Uninstalling existing {#MyAppName} service...
InstallingService=Installing {#MyAppName} service...
InstallingCertificates=Installing certificates...
StartingApp=Starting {#MyAppName}...

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "installservice"; Description: "Install {#MyAppName} as a Windows service"

[Files]
Source: "..\Binner.Web\bin\Release\net6.0\win10-x64\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: http://localhost:8090; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: postinstall shellexec skipifsilent runhidden

[UninstallRun]
Filename: "{app}\{#MyAppExeName}"; Parameters: "uninstall -servicename {#MyAppName}"; RunOnceId: "{#MyAppName}"; Flags: runascurrentuser runhidden

[Code]
type
    SERVICE_STATUS = record
        dwServiceType               : cardinal;
        dwCurrentState              : cardinal;
        dwControlsAccepted          : cardinal;
        dwWin32ExitCode             : cardinal;
        dwServiceSpecificExitCode   : cardinal;
        dwCheckPoint                : cardinal;
        dwWaitHint                  : cardinal;
    end;
    HANDLE = cardinal;
const
    SERVICE_QUERY_CONFIG        = $1;
    SC_MANAGER_ALL_ACCESS       = $f003f;
    SERVICE_RUNNING             = $4;
    SERVICE_QUERY_STATUS        = $4;

function OpenSCManager(lpMachineName, lpDatabaseName: string; dwDesiredAccess :cardinal): HANDLE;
external 'OpenSCManagerW@advapi32.dll stdcall';

function OpenService(hSCManager :HANDLE; lpServiceName: string; dwDesiredAccess :cardinal): HANDLE;
external 'OpenServiceW@advapi32.dll stdcall';

function CloseServiceHandle(hSCObject :HANDLE): boolean;
external 'CloseServiceHandle@advapi32.dll stdcall';

function QueryServiceStatus(hService :HANDLE;var ServiceStatus :SERVICE_STATUS) : boolean;
external 'QueryServiceStatus@advapi32.dll stdcall';

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode : Integer;
begin
  // Install the service if the task was checked by the user
  if CurStep = ssPostInstall then
  begin
    Log('Post install');

    // Install the certificate as trusted before launching apps
    WizardForm.StatusLabel.Caption := CustomMessage('InstallingCertificates');
    WizardForm.StatusLabel.Show();
    Exec('powershell.exe', ExpandConstant('-ExecutionPolicy Bypass -Command Import-PfxCertificate -FilePath ""\""{app}\Certificates\Binner.pfx\"" -CertStoreLocation cert:\LocalMachine\Root -Password (ConvertTo-SecureString -String password -Force -AsPlainText)'), '', SW_SHOW, ewWaitUntilTerminated, ResultCode);

    if WizardIsTaskSelected('installservice') then
    begin
      WizardForm.StatusLabel.Caption := CustomMessage('InstallingService');
      WizardForm.StatusLabel.Show();
      Exec(ExpandConstant('{app}\{#MyAppExeName}'), ExpandConstant('install start -servicename {#MyAppName} -displayname {#MyAppName} -description {#MyAppName} --autostart'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end
    else
    begin
      WizardForm.StatusLabel.Caption := CustomMessage('StartingApp');
      WizardForm.StatusLabel.Show();
      Exec(ExpandConstant('{app}\{#MyAppExeName}'), '', '', SW_SHOW, ewNoWait, ResultCode);
    end;
  end;
end;

function OpenServiceManager() : HANDLE;
begin
    if UsingWinNT() = true then begin
        Result := OpenSCManager('','',SC_MANAGER_ALL_ACCESS);
        if Result = 0 then
            MsgBox('the servicemanager is not available', mbError, MB_OK)
    end
    else begin
            MsgBox('only nt based systems support services', mbError, MB_OK)
            Result := 0;
    end
end;

function IsServiceInstalled(ServiceName: string) : boolean;
var
    hSCM    : HANDLE;
    hService: HANDLE;
begin
    hSCM := OpenServiceManager();
    Result := false;
    if hSCM <> 0 then begin
        hService := OpenService(hSCM, ServiceName, SERVICE_QUERY_CONFIG);
        if hService <> 0 then begin
            Result := true;
            CloseServiceHandle(hService)
        end;
        CloseServiceHandle(hSCM)
    end
end;

function IsServiceRunning(ServiceName: string) : boolean;
var
    hSCM    : HANDLE;
    hService: HANDLE;
    Status  : SERVICE_STATUS;
begin
    hSCM := OpenServiceManager();
    Result := false;
    if hSCM <> 0 then begin
        hService := OpenService(hSCM, ServiceName, SERVICE_QUERY_STATUS);
        if hService <> 0 then begin
            if QueryServiceStatus(hService,Status) then begin
                Result :=(Status.dwCurrentState = SERVICE_RUNNING)
            end;
            CloseServiceHandle(hService)
            end;
        CloseServiceHandle(hSCM)
    end
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode : Integer;
  ServiceInstalled : Boolean;
  ServiceRunning : Boolean;
begin
  // uninstall the service if it's already installed
  ServiceInstalled := IsServiceInstalled(ExpandConstant('{#MyAppName}'));
  ServiceRunning := IsServiceRunning(ExpandConstant('{#MyAppName}'));
  if ServiceInstalled then
  begin
    Log('Uninstalling existing service');
    WizardForm.PreparingLabel.Caption := CustomMessage('UninstallingService');
    WizardForm.PreparingLabel.Show();
    Exec(ExpandConstant('{app}\{#MyAppExeName}'), ExpandConstant('stop -servicename {#MyAppName}'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{app}\{#MyAppExeName}'), ExpandConstant('uninstall -servicename {#MyAppName}'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;