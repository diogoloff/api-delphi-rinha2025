unit unRequisicaoPendente;

interface

uses
    System.Classes, System.SysUtils, System.JSON, System.DateUtils,
    System.Net.HttpClient, System.Net.URLClient, System.NetConsts,
    unGenerica, unHealthHelper, unPersistencia;

type
    { TRequisicaoPendente }

    TRequisicaoPendente = class
    private
        FCorrelationId: String;
        FAmount: Double;
        FAttempt: Integer;
	      FRequestedAt: String;
        FJsonObj: TJSONObject;

	      procedure AjustarDataHora;
    public
        constructor Create(const AId: String; AAmount: Double; AAttempt: Integer);
        destructor Destroy; override;

	      function Processar(AClient : THTTPClient): Boolean;

        property CorrelationId: String read FCorrelationId;
        property Amount: Double read FAmount;
        property Attempt: Integer read FAttempt write FAttempt;
    end;

implementation

{ TRequisicaoPendente }

constructor TRequisicaoPendente.Create(const AId: String; AAmount: Double; AAttempt: Integer);
begin
    FCorrelationId:= AId;
    FAmount:= AAmount;
    FAttempt:= AAttempt;

    FJsonObj:= TJSONObject.Create;

    FJsonObj.AddPair('correlationId', FCorrelationId);
    FJsonObj.AddPair('amount', TJSONNumber.Create(FAmount));
end;

destructor TRequisicaoPendente.Destroy;
begin
    inherited Destroy;
end;

procedure TRequisicaoPendente.AjustarDataHora;
begin
    FRequestedAt:= DateToISO8601(Now);

    AddOrUpdatePair(FJsonObj, 'requestedAt', FRequestedAt);
end;

function TRequisicaoPendente.Processar(AClient : THTTPClient): Boolean;
var
    lbDefault: Boolean;
    lsURL: String;
    lResposta: IHTTPResponse;
    JsonStream: TStringStream;
begin
    try
        lbDefault:= True;
        if (FAttempt > FNumTentativasDefault) then
            lbDefault:= ServiceHealthMonitor.GetDefaultAtivo;

        if lbDefault then
            lsURL:= FUrl
        else
            lsURL:= FUrlFall;

        AjustarDataHora;

        JsonStream := TStringStream.Create(FJsonObj.ToString, TEncoding.UTF8);
        lResposta := AClient.Post(lsURL + '/payments', JsonStream);

        if (lResposta.StatusCode = 200) then
        begin
            if (lbDefault) then
                AddOrUpdatePair(FJsonObj, 'service', 0)
            else
                AddOrUpdatePair(FJsonObj, 'service', 1);

            Persistencia.AdicionarRegistro(TRegistro.Create(FJsonObj));

            if (FAttempt <= FNumTentativasDefault) and (not ServiceHealthMonitor.GetDefaultAtivo) then
                ServiceHealthMonitor.SetDefaultAtivo(True);

            Result:= True;
            Exit;
        end;
    except
        on E: Exception do
            GerarLog('Erro Processar: ' + E.Message, True);
    end;

    Inc(FAttempt);
    Result:= False;
end;

end.
