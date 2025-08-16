unit undmServer;

interface

uses System.SysUtils, System.Classes, unGenerica, unConstantes, unAPI;

type
    TdmServer = class(TDataModule)
        procedure DataModuleCreate(Sender: TObject);
        procedure DataModuleDestroy(Sender: TObject);
    private
        procedure IniciarAPI;

      { Private declarations }
    public

    end;

    procedure RunDSServer;
    procedure StopServer;

var
    dmServer: TdmServer;
    FServerHttp: TApiServer;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

procedure TdmServer.IniciarAPI;
begin
    try
        FServerHttp:= TApiServer.Create;
    except
        on E : Exception do
            GerarLog(E.message, True);
    end;
end;

procedure TdmServer.DataModuleCreate(Sender: TObject);
begin
    CarregarVariaveisAmbiente;

    IniciarAPI;
end;

procedure TdmServer.DataModuleDestroy(Sender: TObject);
begin
    FServerHttp.Free;
end;

procedure WriteCommands;
begin
    GerarLog(sCommands);
    GerarLog(cArrow, False);
end;

procedure StartServer;
begin
    if (dmServer = nil) then
        dmServer := TdmServer.Create(nil)
    else
        GerarLog(sServerRunning);

    GerarLog('Configuração do Ambiente');
    GerarLog('==================================');
    GerarLog('(DEBUG) Debug Ativo: ' + BoolToStr(FDebug, True));
    GerarLog('(DEFAULT_URL) Url Default: ' + FUrl);
    GerarLog('(FALLBACK_URL) Url Fallback: ' + FUrlFall);
    GerarLog('(CON_TIME_OUT) Timeout Conexão: ' + IntToStr(FConTimeOut));
    GerarLog('(READ_TIME_OUT) Timeout Retorno: ' + IntToStr(FReadTimeOut));
    GerarLog('(NUM_WORKERS) Quantidade de Workers na Fila: ' + IntToStr(FNumMaxWorkers));
    GerarLog('(LISEM_QUEUE) Tamanho da Fila do Socket: ' + IntToStr(FNumListemQueue));
    GerarLog('(TEMPO_FILA) Tempo Descarga de Fila: ' + IntToStr(FTempoFila));
    GerarLog('(NUM_TENTATIVAS_DEFAULT) Numero de Tentativas Default: ' + IntToStr(FNumTentativasDefault));

    GerarLog(cArrow);
end;

procedure StopServer;
begin
    if (Assigned(dmServer)) then
    begin
        GerarLog(sStoppingServer);

        dmServer.Free;

        GerarLog(sServerStopped);
    end
    else
        GerarLog(sServerNotRunning);

    GerarLog(cArrow);
end;

procedure RunDSServer;
    procedure ModoConsole;
    var
        LResponse: string;
    begin
        // Modelo Console
        WriteCommands;
        while True do
        begin
            Readln(LResponse);
            LResponse := LowerCase(LResponse);
            if sametext(LResponse, cCommandStart) then
                StartServer
            else if sametext(LResponse, cCommandStop) then
                StopServer
            else if sametext(LResponse, cCommandHelp) then
                WriteCommands
            else if sametext(LResponse, cCommandExit) then
                if (Assigned(dmServer)) then
                begin
                    StopServer;
                    break
                end
                else
                    break
            else
            begin
                Writeln(sInvalidCommand);
                Write(cArrow);
            end;
        end;
    end;
begin
    {$IFDEF SERVICO}
        FServerIniciado := False;
    {$ENDIF}

    {$IFNDEF LINUX64}
        FPathAplicacao := ExtractFilePath(ParamStr(0));
    {$ENDIF}

    {$IFNDEF SERVICO}
        ModoConsole;
    {$ELSE}
        try
            StartServer;

            FServerIniciado := True;
        except
            on E : Exception do
            begin
                GerarLog(E.Message);
            end;
        end;
    {$ENDIF}
end;

initialization


finalization


end.

