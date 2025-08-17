unit undmWebModule;

interface

uses System.SysUtils, System.Classes, System.JSON, Web.HTTPApp, MVCFramework, MVCFramework.Commons, MVCFramework.Logger;

type
  TdmWebModule = class(TWebModule)
    procedure WebModuleCreate(Sender: TObject);

  private
    FServidor : TMVCEngine;
  public
    { Public declarations }
  end;

var
  WebModuleClass: TComponentClass = TdmWebModule;

implementation

{$R *.dfm}

uses unAPI, unPersistencia;

procedure TdmWebModule.WebModuleCreate(Sender: TObject);
begin
    LogLevelLimit := levFatal;
    UseLoggerVerbosityLevel := TLogLevel.levFatal;

    FServidor := TMVCEngine.Create(Self,
    procedure(Config: TMVCConfig)
    begin
        Config[TMVCConfigKey.DefaultContentType] := 'application/json';
        Config[TMVCConfigKey.LoadSystemControllers] := 'false';
    end);

    FServidor.AddController(TApiController);
end;

end.
