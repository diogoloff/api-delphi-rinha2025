unit unHealthHelper;

interface

uses
    System.Classes, System.SysUtils, System.SyncObjs, System.JSON, System.DateUtils,
    System.Net.HttpClient, System.Net.URLClient, System.NetConsts,
    unGenerica;

type
    { TWorkerMonitor }

    TWorkerMonitor = class(TThread)
    private
        FProc: TProc;
    protected
        procedure Execute; override;
    public
        constructor Create(AProc: TProc);
    end;

    TServiceHealthMonitor = class
    private
        FEventoVerificar: TEvent;
        FMonitorLock: TCriticalSection;
        FDefaultAtivo: Integer;
        FUltimaVerificacao: TDateTime;
        FHealthURL: string;
        FMonitoramentoAtivo: Boolean;
        FThreadMonitorar: TWorkerMonitor;
        FClient : THTTPClient;

        procedure ThreadMonitorar;
        procedure ExecutarHealthCheck;
        procedure Finalizar;
    public
        constructor Create(const AHealthURL: String);
        destructor Destroy; override;

        procedure Iniciar;
        procedure VerificarSinal;

        function GetDefaultAtivo: Boolean;
        procedure SetDefaultAtivo(const AValue: Boolean);
    end;

procedure IniciarHealthCk(const AHealthURL: String);
procedure FinalizarHealthCk;

var
    ServiceHealthMonitor: TServiceHealthMonitor;

implementation

{ TWorkerMonitor }

procedure TWorkerMonitor.Execute;
begin
    if (Assigned(FProc)) then
        FProc;
end;

constructor TWorkerMonitor.Create(AProc: TProc);
begin
    inherited Create(False);
    FreeOnTerminate:= True;
    FProc:= AProc;
end;

{ TServiceHealthMonitor }

constructor TServiceHealthMonitor.Create(const AHealthURL: String);
begin
    FEventoVerificar := TEvent.Create(nil, False, False, '');
    FMonitorLock := TCriticalSection.Create;
    FDefaultAtivo := 1;
    FUltimaVerificacao := IncSecond(Now, -6);
    FHealthURL := AHealthURL;
    FMonitoramentoAtivo := True;

    FClient := THTTPClient.Create;
    FClient.ConnectionTimeout := FConTimeOut;
    FClient.ResponseTimeout := FReadTimeOut;
    FClient.ContentType:= 'application/json';
    FClient.CustomHeaders['User-Agent'] := 'RinhaDelphi/1.0';
    FClient.CustomHeaders['Connection'] := 'keep-alive';
end;

destructor TServiceHealthMonitor.Destroy;
begin
    Finalizar;

    FEventoVerificar.Free;
    FMonitorLock.Free;
    FClient.Free;
    inherited Destroy;
end;

procedure TServiceHealthMonitor.ExecutarHealthCheck;
var
    lResJson: TJSONObject;
    lFailing: Boolean;

    lResposta: IHTTPResponse;
begin
    lFailing := False;

    try
        lResposta := FClient.Get(FHealthURL + '/payments/service-health');

        if (lResposta.StatusCode = 200) then
        begin
            lResJson := TJSONObject.ParseJSONValue(lResposta.ContentAsString) as TJSONObject;

            lFailing := (lResJson.GetValue('failing') as TJSONBool).AsBoolean;
        end
        else
            GerarLog('HealthCheck: Erro na requisição ' + IntToStr(lResposta.StatusCode));
    except
        on E: Exception do
            GerarLog('HealthCheck: Erro ' + E.Message);
    end;

    SetDefaultAtivo(not lFailing);
end;

function TServiceHealthMonitor.GetDefaultAtivo: Boolean;
begin
    Result := FDefaultAtivo <> 0;
end;

procedure TServiceHealthMonitor.SetDefaultAtivo(const AValue: Boolean);
begin
    TInterlocked.Exchange(FDefaultAtivo, Ord(AValue));
end;

procedure TServiceHealthMonitor.VerificarSinal;
begin
    FMonitorLock.Enter;
    try
        if SecondsBetween(Now, FUltimaVerificacao) >= 5 then
            FEventoVerificar.SetEvent;
    finally
        FMonitorLock.Leave;
    end;
end;

procedure TServiceHealthMonitor.Iniciar;
begin
    FThreadMonitorar := TWorkerMonitor.Create(ThreadMonitorar);
end;

procedure TServiceHealthMonitor.Finalizar;
begin
    if (not FMonitoramentoAtivo) then
        Exit;

    FMonitoramentoAtivo := False;
    FEventoVerificar.SetEvent;

    FThreadMonitorar.WaitFor;
    FThreadMonitorar.Free;
end;

procedure TServiceHealthMonitor.ThreadMonitorar;
begin
    while FMonitoramentoAtivo do
    begin
        if FEventoVerificar.WaitFor(INFINITE) = wrSignaled then
        begin
            if (not FMonitoramentoAtivo) then
                Exit;

            if SecondsBetween(Now, FUltimaVerificacao) >= 5 then
            begin
                FUltimaVerificacao := Now;
                ExecutarHealthCheck;
            end;
        end;
    end;
end;

procedure IniciarHealthCk(const AHealthURL: String);
begin
    ServiceHealthMonitor := TServiceHealthMonitor.Create(AHealthURL);
    ServiceHealthMonitor.Iniciar;
end;

procedure FinalizarHealthCk;
begin
    if Assigned(ServiceHealthMonitor) then
        ServiceHealthMonitor.Free;
end;

end.
