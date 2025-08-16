unit unAPI;

interface

uses
    System.Classes, System.JSON, System.SysUtils, System.Threading, System.Generics.Collections,
    Horse, Horse.Commons, System.SyncObjs,
    System.Net.HttpClient, System.Net.URLClient, System.NetConsts,
    unRequisicaoPendente, unHealthHelper, unGenerica, unPersistencia;

type
    { TApiServer }

    TApiServer = class
    private
        procedure RegistrarRotas;
    public
        constructor Create;
        destructor Destroy; override;

        procedure HandlePayments(Req: THorseRequest; Res: THorseResponse; Next: TProc);
        procedure HandlePaymentsSummary(Req: THorseRequest; Res: THorseResponse; Next: TProc);
    end;

    { TWorkerRequisicao }

    TWorkerRequisicao = class(TThread)
    private
        FIndice: Integer;
        FClientAdd : THTTPClient;
        procedure Desempilhar;
    protected
        procedure Execute; override;
    public
        constructor Create(AIndice: Integer);
        destructor Destroy; override;
    end;

var
    FilaRequisicoes: array of TQueue<TRequisicaoPendente>;
    Workers: array of TWorkerRequisicao;
    FLocks: array of TObject;
    FIndex: Integer = 0;

implementation

procedure InicializarFilaEPool;
var
    I: Integer;
begin
    SetLength(FilaRequisicoes, FNumMaxWorkers);
    SetLength(FLocks, FNumMaxWorkers);
    SetLength(Workers, FNumMaxWorkers);

    for I := 0 to High(Workers) do
    begin
        FilaRequisicoes[I] := TQueue<TRequisicaoPendente>.Create;
        FLocks[I] := TObject.Create;

        Workers[I]:= TWorkerRequisicao.Create(I);
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

        FilaRequisicoes[i].Free;
        FLocks[i].Free;
    end;
end;

procedure AdicionarWorkerFila(ACorrelationId: String; AAmount: Double; AAttempt: Integer); overload;
var
    lRequisicao: TRequisicaoPendente;
    liIndice: Integer;
begin
    lRequisicao := TRequisicaoPendente.Create(ACorrelationId, AAmount, AAttempt);

    liIndice := TInterlocked.Increment(FIndex) mod FNumMaxWorkers;

    TMonitor.Enter(FLocks[liIndice]);
    try
        FilaRequisicoes[liIndice].Enqueue(lRequisicao);
    finally
        TMonitor.Exit(FLocks[liIndice]);
    end;
end;

procedure AdicionarWorkerFila(ARequisicao: TRequisicaoPendente); overload;
var
    liIndice: Integer;
begin
    liIndice := TInterlocked.Increment(FIndex) mod FNumMaxWorkers;

    TMonitor.Enter(FLocks[liIndice]);
    try
        FilaRequisicoes[liIndice].Enqueue(ARequisicao);
    finally
        TMonitor.Exit(FLocks[liIndice]);
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
    if (FilaRequisicoes[FIndice].Count > 0) then
        lRequisicao := FilaRequisicoes[FIndice].Dequeue
    else
        lRequisicao := nil;

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

constructor TWorkerRequisicao.Create(AIndice: Integer);
begin
    inherited Create(True);
    FIndice := AIndice;

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

    lsQuery:= '';
    if Trim(lsFrom) <> '' then
        lsQuery:= 'from=' + lsFrom;

    if Trim(lsTo) <> '' then
    begin
        if lsQuery <> '' then
            lsQuery := lsQuery + '&';
        lsQuery:= lsQuery + 'to=' + lsTo;
    end;

    if lsQuery <> '' then
        lsQuery:= '?' + lsQuery;

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

    {try
        TPersistencia.LimparMemoriaCompartilhada;
    except
        on E: Exception do
            GerarLog('Destruir armazenamento: ' + E.Message);
    end; }

    try
        Persistencia:= TPersistencia.Create;
    except
        on E: Exception do
            GerarLog('Criar armazenamento: ' + E.Message);
    end;

    IniciarHealthCk(FUrl);

    try
        InicializarFilaEPool;
    except
        on E: Exception do
            GerarLog('Criar pool: ' + E.Message);
    end;

    TTask.Run(
    procedure
    begin
        THorse.Port := 8080;
        RegistrarRotas;

        THorse.ListenQueue := FNumListemQueue;
        THorse.Listen;
    end);
end;

destructor TApiServer.Destroy;
begin
    if (THorse.IsRunning) then
        THorse.StopListen;

    FinalizarHealthCk;
    FinalizarFilaEPool;

    Persistencia.Free;

    inherited Destroy;
end;

initialization

finalization

end.
