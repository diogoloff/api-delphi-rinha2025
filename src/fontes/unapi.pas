unit unAPI;

interface

uses
    System.Classes, System.JSON, System.SysUtils, System.Threading, System.Generics.Collections,
    System.SyncObjs, System.Net.HttpClient, System.Net.URLClient, System.NetConsts,
    unRequisicaoPendente, unHealthHelper, unGenerica, unPersistencia,
    IdHTTPWebBrokerBridge, Web.HTTPApp, Web.WebReq, undmWebModule,
    MVCFramework, MVCFramework.Commons,
    Horse, Horse.Commons;

type
    { TApiServer }

    TApiServer = class
    private
        // Rotas usadas pelo modelo horse
        procedure HandlePayments(Req: THorseRequest; Res: THorseResponse; Next: TProc);
        procedure HandlePaymentsSummary(Req: THorseRequest; Res: THorseResponse; Next: TProc);
        procedure RegistrarRotas;
    public
        constructor Create;
        destructor Destroy; override;
    end;

    { TWorkerRequisicao }

    TWorkerRequisicao = class(TThread)
    private
        FClientAdd : THTTPClient;
        procedure Desempilhar;
    protected
        procedure Execute; override;
    public
        constructor Create;
        destructor Destroy; override;
    end;

    // Rotas usadas pelo modelo nativo com Indy e undmWebModule
    [MVCPath('/')]
    TApiController = class(TMVCController)
    public
      [MVCPath('/payments')]
      [MVCHTTPMethod([httpPOST])]
      procedure HandlePayments;

      [MVCPath('/payments-summary')]
      [MVCHTTPMethod([httpGET])]
      procedure HandlePaymentsSummary;
    end;

var
    FHTTPServer: TIdHTTPWebBrokerBridge;

    FilaRequisicoes: TQueue<TRequisicaoPendente>;
    FilaLock: TCriticalSection;
    Workers: array of TWorkerRequisicao;

implementation

procedure InicializarFilaEPool;
var
    I: Integer;
begin
    FilaRequisicoes := TQueue<TRequisicaoPendente>.Create;
    SetLength(Workers, FNumMaxWorkers);

    for I := 0 to High(Workers) do
    begin
        Workers[I]:= TWorkerRequisicao.Create;
        Workers[I].Start;
    end;
end;

procedure FinalizarFilaEPool;
var
    I: Integer;
begin
    for I := 0 to High(Workers) do
    begin
        Workers[I].Terminate;
        Workers[I].WaitFor;
        Workers[I].Free;
    end;

    FilaRequisicoes.Free;
end;

procedure AdicionarWorkerFila(ACorrelationId: String; AAmount: Double; AAttempt: Integer); overload;
var
    lRequisicao: TRequisicaoPendente;
begin
    lRequisicao := TRequisicaoPendente.Create(ACorrelationId, AAmount, AAttempt);

    FilaLock.Enter;
    try
        FilaRequisicoes.Enqueue(lRequisicao);
    finally
        FilaLock.Leave;
    end;
end;

procedure AdicionarWorkerFila(ARequisicao: TRequisicaoPendente); overload;
begin
    FilaLock.Enter;
    try
        FilaRequisicoes.Enqueue(ARequisicao);
    finally
        FilaLock.Leave;
    end;
end;

procedure Processar(AReq : TRequisicaoPendente; AClient : THTTPClient);
begin
    if (AReq.Processar(AClient)) then
    begin
        AReq.Free;
        Exit;
    end;

    if (AReq.attempt > 20) then
    begin
        GerarLog('Descartado: ' + AReq.CorrelationId, True);
        AReq.Free;
        Exit;
    end;

    ServiceHealthMonitor.VerificarSinal;
    AdicionarWorkerFila(AReq);
end;

{ TWorkerRequisicao }

procedure TWorkerRequisicao.Desempilhar;
var
    lRequisicao: TRequisicaoPendente;
begin
    FilaLock.Enter;
    try
        if (FilaRequisicoes.Count > 0) then
            lRequisicao := FilaRequisicoes.Dequeue
        else
            lRequisicao := nil;
    finally
        FilaLock.Leave;
    end;

    if (Assigned(lRequisicao)) then
        Processar(lRequisicao, FClientAdd)
    else
        Sleep(FTempoFila);
end;

procedure TWorkerRequisicao.Execute;
begin
    while not Terminated do
    begin
        try
            Desempilhar;
        except
            on E: Exception do
                GerarLog(E.Message, True);
        end;
    end;
end;

constructor TWorkerRequisicao.Create;
begin
    inherited Create(True);

    FClientAdd := THTTPClient.Create;
    FClientAdd.ConnectionTimeout := FConTimeOut;
    FClientAdd.ResponseTimeout := FReadTimeOut;
    FClientAdd.ContentType:= 'application/json';
    FClientAdd.CustomHeaders['User-Agent'] := 'RinhaDelphi/1.0';
    FClientAdd.CustomHeaders['Connection'] := 'keep-alive';

    FreeOnTerminate := False;
end;

destructor TWorkerRequisicao.Destroy;
begin
    FClientAdd.Free;
    inherited Destroy;
end;

{ TApiServer }

procedure TApiServer.RegistrarRotas;
begin
    THorse
        .Group
            .Route('/payments')
                .Post(HandlePayments);

    THorse
        .Group
              .Route('/payments-summary')
                  .Get(HandlePaymentsSummary)
end;

procedure TApiServer.HandlePayments(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
    lReqJson: TJSONObject;
    lCorrelationId: String;
    lAmount: Double;
begin
    lReqJson := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    try
        lCorrelationId := lReqJson.GetValue('correlationId').Value;
        lAmount := StrToFloat(lReqJson.GetValue('amount').Value);

        Res.ContentType('application/json');
        Res.Send('{}').Status(THTTPStatus.Ok);

        AdicionarWorkerFila(lCorrelationId, lAmount, 0);
    finally
        lReqJson.Free;
    end;
end;

procedure TApiServer.HandlePaymentsSummary(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
    lsFrom: String;
    lsTo: String;
    lsQuery: String;
    lResposta: TJSONObject;
begin
    lsFrom := Req.Query.Field('from').AsString;
    lsTo := Req.Query.Field('to').AsString;

    Res.ContentType('application/json');

    try
        lResposta := Persistencia.ConsultarDados(lsFrom, lsTo);

        Res.Send(lResposta.ToString).Status(THTTPStatus.Ok)
    except
        on E: Exception do
            Res.Send(E.Message).Status(THTTPStatus.InternalServerError);
    end;
end;

constructor TApiServer.Create;
begin
    inherited Create;

    FilaLock:= TCriticalSection.Create;

    try
        Persistencia:= TPersistencia.Create;
    except
        on E: Exception do
        begin
            GerarLog('Criar armazenamento: ' + E.Message);
        end;
    end;

    IniciarHealthCk(FUrl);

    try
        InicializarFilaEPool;
    except
        on E: Exception do
        begin
            GerarLog('Criar pool: ' + E.Message);
        end;
    end;

    if (FNativo) then
    begin
        WebRequestHandler.WebModuleClass := WebModuleClass;

        FHTTPServer := TIdHTTPWebBrokerBridge.Create(nil);
        FHTTPServer.DefaultPort := 8080;
        FHTTPServer.KeepAlive := FKeepAlive;

        WebRequestHandler.MaxConnections:= FMaxConnections;
        FHTTPServer.MaxConnections := FMaxConnections;
        FHTTPServer.ListenQueue := FNumListemQueue;
        FHTTPServer.Active := True;
    end
    else
    begin
        TTask.Run(
        procedure
        begin
            RegistrarRotas;

            THorse.Port := 8080;
            THorse.KeepConnectionAlive := FKeepAlive;
            THorse.MaxConnections := FMaxConnections;
            THorse.ListenQueue := FNumListemQueue;
            THorse.Listen;
        end);

    end;
end;

destructor TApiServer.Destroy;
begin
    try
        Writeln('Parando Server');
        if (FNativo) then
        begin
            if FHTTPServer.Active then
                FHTTPServer.Active := False;
        end
        else
        begin
            if (THorse.IsRunning) then
                THorse.StopListen;
        end;

        Writeln('Server Parado');
    except
        on E: Exception do
            Writeln('Erro ao Parar Server: ' + E.Message);
    end;

    try
        Writeln('Finalizando Health');
        FinalizarHealthCk;
        Writeln('Health Finalizado');
    except
        on E: Exception do
            Writeln('Erro ao Finalizar Health: ' + E.Message);
    end;

    try
        Writeln('Finalizando Fila e Pool');
        FinalizarFilaEPool;
        FilaLock.Free;
        Writeln('Fila e Pool Finalizado');
    except
        on E: Exception do
            Writeln('Erro ao Finalizar Fila e Pool: ' + E.Message);
    end;

    try
        Writeln('Finalizando HttpServer');
        FHTTPServer.Free;
        Writeln('HttpServer Finalizado');
    except
        on E: Exception do
            Writeln('Erro ao Finalizar HttpServer: ' + E.Message);
    end;

    try
        Writeln('Finalizando Persistencia');
        Persistencia.Free;
        Writeln('Persistencia Finalizado');
    except
        on E: Exception do
            Writeln('Erro ao Finalizar Persistencia: ' + E.Message);
    end;

    Writeln('Finalizando Memoria');
    TPersistencia.LimparMemoriaCompartilhada;
    Writeln('Memoria Finalizado');

    inherited Destroy;
end;

{ TApiController }

procedure TApiController.HandlePayments;
var
    lReqJson: TJSONObject;
    lCorrelationId: string;
    lAmount: Double;
begin
    lReqJson := TJSONObject.ParseJSONValue(Context.Request.Body) as TJSONObject;
    try
        lCorrelationId := lReqJson.GetValue('correlationId').Value;
        lAmount := StrToFloat(lReqJson.GetValue('amount').Value);

        AdicionarWorkerFila(lCorrelationId, lAmount, 0);

        Render('');
    finally
      lReqJson.Free;
    end;
end;

procedure TApiController.HandlePaymentsSummary;
var
    lsFrom: String;
    lsTo: String;
    lResposta: TJSONObject;
begin
    try
        lsFrom := Context.Request.QueryParams['from']
    except
        lsFrom := '';
    end;

    try
        lsTo := Context.Request.QueryParams['to']
    except
        lsTo := '';
    end;

    try
        try
            lResposta := Persistencia.ConsultarDados(lsFrom, lsTo);
        except
            on E: Exception do
                Writeln('Erro ' + E.message);
        end;

        Render(lResposta.ToString);
    except
        on E: Exception do
            Render(500, E.Message);
    end;
end;

initialization

finalization

end.
