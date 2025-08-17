unit unGenerica;

interface

uses
    System.SysUtils, System.SyncObjs, System.IOUtils, System.DateUtils, System.JSON;

    procedure AddOrUpdatePair(AJsonObj: TJSONObject; const AKey: string; const AValue: string); overload;
    procedure AddOrUpdatePair(AJsonObj: TJSONObject; const AKey: string; const AValue: Integer); overload;
    procedure AddOrUpdatePair(AJsonObj: TJSONObject; const AKey: string; const AValue: Double); overload;
    procedure CarregarVariaveisAmbiente;
    function GetEnv(const lsEnvVar, lsDefault: string): string;
    procedure GerarLog(lsMsg : String;  lbForca : Boolean = False);

var
    FPathAplicacao: String;

    {$IFDEF SERVICO}
        FServerIniciado: Boolean;
    {$ENDIF}

    {$IFDEF LINUX64}
        FPidFile : String;
    {$ENDIF}

    FLogLock: TCriticalSection;
    FDebug : Boolean;
    FUrl: String;
    FUrlFall: String;
    FConTimeOut: Integer;
    FReadTimeOut: Integer;
    FNumMaxWorkers: Integer;
    FNumListemQueue: Integer;
    FTempoFila: Integer;
    FNumTentativasDefault: Integer;
    FNativo: Boolean;
    FKeepAlive: Boolean;
    FMaxConnections: Integer;

implementation

function GetEnv(const lsEnvVar, lsDefault: string): string;
begin
    Result := GetEnvironmentVariable(lsEnvVar);
    if Result = '' then
        Result := lsDefault;
end;

procedure AddOrUpdatePair(AJsonObj: TJSONObject; const AKey: string; const AValue: string); overload;
var
    lPair: TJSONPair;
begin
    lPair := AJsonObj.Get(AKey);
    if Assigned(lPair) then
        lPair.JsonValue := TJSONString.Create(AValue)
    else
        AJsonObj.AddPair(AKey, AValue);
end;

procedure AddOrUpdatePair(AJsonObj: TJSONObject; const AKey: string; const AValue: Integer); overload;
var
    lPair: TJSONPair;
begin
    lPair := AJsonObj.Get(AKey);
    if Assigned(lPair) then
        lPair.JsonValue := TJSONNumber.Create(AValue)
    else
        AJsonObj.AddPair(AKey, TJSONNumber.Create(AValue));
end;

procedure AddOrUpdatePair(AJsonObj: TJSONObject; const AKey: string; const AValue: Double); overload;
var
    lPair: TJSONPair;
begin
    lPair := AJsonObj.Get(AKey);
    if Assigned(lPair) then
        lPair.JsonValue := TJSONNumber.Create(AValue)
    else
        AJsonObj.AddPair(AKey, TJSONNumber.Create(AValue));
end;

procedure GerarLog(lsMsg : String; lbForca : Boolean);
var
    lsArquivo : String;
    lsData : String;
begin
    {$IFNDEF DEBUG}
        if (not FDebug) and (not lbForca) then
            Exit;
    {$ENDIF}

    {$IFNDEF SERVICO}
        Writeln(lsMsg);
    {$ENDIF}

    FLogLock.Enter;
    try
        try
            if (trim(FPathAplicacao) = '') then
                FPathAplicacao := '/opt/rinha/';

            lsData := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(Now));
            lsArquivo := FPathAplicacao + 'Logs' + PathDelim +  'log' + FormatDateTime('ddmmyyyy', Date) + '.txt';
            TFile.AppendAllText(lsArquivo, lsData + ':' + lsMsg + sLineBreak, TEncoding.UTF8);
        except
        end;
     finally
        FLogLock.Leave;
     end;
end;

procedure CarregarVariaveisAmbiente;
begin
    FDebug := GetEnv('DEBUG', 'N') = 'S';
    FUrl := GetEnv('DEFAULT_URL', 'http://localhost:8001');
    FUrlFall := GetEnv('FALLBACK_URL', 'http://localhost:8002');
    FConTimeOut := StrToIntDef(GetEnv('CON_TIME_OUT', ''), 2500);
    FReadTimeOut := StrToIntDef(GetEnv('READ_TIME_OUT', ''), 2500);
    FNumMaxWorkers := StrToIntDef(GetEnv('NUM_WORKERS', ''), 2);
    FNumListemQueue := StrToIntDef(GetEnv('LISTEM_QUEUE', ''), 0);
    FTempoFila := StrToIntDef(GetEnv('TEMPO_FILA', ''), 500);
    FNumTentativasDefault := StrToIntDef(GetEnv('NUM_TENTATIVAS_DEFAULT', ''), 5);
    FNativo := GetEnv('NATIVO', 'N') = 'S';
    FKeepAlive := GetEnv('KEEP_ALIVE', 'N') = 'S';
    FMaxConnections := StrToIntDef(GetEnv('MAX_CONNECTIONS', ''), 0);

    if FConTimeOut < 0 then
        FConTimeOut := 3000;

    if FReadTimeOut < 0 then
        FReadTimeOut := 3000;

    if FNumMaxWorkers < 0 then
        FNumMaxWorkers := 1;

    if FNumListemQueue < 0 then
        FNumListemQueue := 0;

    if FTempoFila < 0 then
        FTempoFila := 500;

    if FNumTentativasDefault < 0 then
        FNumTentativasDefault := 1;
end;

initialization
    FLogLock := TCriticalSection.Create;

finalization
    FLogLock.Free;

end.
