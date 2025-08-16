unit unPersistencia;

interface

uses
    Posix.SysMman, Posix.Unistd, Posix.Fcntl, Posix.String_, Posix.Stdlib, Posix.Semaphore,
    System.SysUtils, System.Generics.Collections, System.JSON, System.DateUtils, unGenerica;

type
    TRegistro = packed record
        CorrelationId: array[0..35] of AnsiChar;
        Amount: Double;
        RequestedAt: array[0..23] of AnsiChar;
        Service: Integer;
    public
        constructor Create(const AJson: TJSONObject);
    end;

    TPersistencia = class
    private
        FPtr: Pointer;
        FFD: Integer;
        FSem: PSem_t;

    public
        constructor Create;
        destructor Destroy; override;
        procedure AdicionarRegistro(const AReg: TRegistro);
        function LerTodos: TArray<TRegistro>;
        function ConsultarDados(const AFrom, ATo: string): TJSONObject;

        class procedure LimparMemoriaCompartilhada;
    end;

var
    Persistencia: TPersistencia;

const
    SHM_PATH = '/dev/shm/bloco_memoria';
    SHM_SIZE = 20 * 1024 * 1024; // 20 MB
    REG_SIZE = SizeOf(TRegistro);
    MAX_REGISTROS = SHM_SIZE div REG_SIZE;

implementation

function CriarSemaforo: PSem_t;
begin
    Result := sem_open('/semaforo_memoria', O_CREAT, 0666, 1);
    if Result = SEM_FAILED then
        raise Exception.Create('Erro ao criar semáforo');
end;

{ TRegistro }

constructor TRegistro.Create(const AJson: TJSONObject);
begin
    StrPCopy(CorrelationId, AJson.GetValue<string>('correlationId'));
    Amount := AJson.GetValue<Double>('amount');
    StrPCopy(RequestedAt, AJson.GetValue<string>('requestedAt'));
    Service := AJson.GetValue<Integer>('service');
end;

{ TPersistencia }

class procedure TPersistencia.LimparMemoriaCompartilhada;
begin
    try
        if FileExists(SHM_PATH) then
        begin
            DeleteFile(SHM_PATH);
            GerarLog('Memória compartilhada removida.');
        end;
    except
        on E: Exception do
            GerarLog('Erro ao remover memória: ' + E.Message);
    end;

    try
        sem_unlink('/semaforo_memoria');
        GerarLog('Semáforo removido.');
    except
        on E: Exception do
            GerarLog('Erro ao remover semáforo: ' + E.Message);
    end;
end;

procedure TPersistencia.AdicionarRegistro(const AReg: TRegistro);
var
    I: Integer;
    lPReg: ^TRegistro;
    lbAdicionado: Boolean;
begin
    lbAdicionado := False;
    sem_wait(FSem^); // trava
    try
        for I := 0 to MAX_REGISTROS - 1 do
        begin
            lPReg := Ptr(UIntPtr(FPtr) + UIntPtr(I * REG_SIZE));
            if lPReg^.CorrelationId[0] = #0 then // campo vazio
            begin
                lPReg^ := AReg;
                lbAdicionado := True;
                Break;
            end;
        end;
    finally
        sem_post(FSem^); // libera
    end;

    if not lbAdicionado then
        raise Exception.Create('Memória cheia: não foi possível adicionar o registro');
end;

constructor TPersistencia.Create;
begin
    FFD := open(SHM_PATH, O_CREAT or O_RDWR, 0666);
    if FFD = -1 then
        raise Exception.Create('Erro ao abrir memória');

    if ftruncate(FFD, SHM_SIZE) = -1 then
        raise Exception.Create('Erro ao definir tamanho');

    FPtr := mmap(nil, SHM_SIZE, PROT_READ or PROT_WRITE, MAP_SHARED, FFD, 0);
    if FPtr = MAP_FAILED then
        raise Exception.Create('Erro ao mapear memória');

    FSem := CriarSemaforo;
end;

destructor TPersistencia.Destroy;
begin
    munmap(FPtr, SHM_SIZE);
    __close(FFD);
    sem_close(FSem^);
    inherited;
end;

function TPersistencia.LerTodos: TArray<TRegistro>;
var
    I: Integer;
    lPReg: ^TRegistro;
    lLista: TList<TRegistro>;
begin
    lLista := TList<TRegistro>.Create;
    try
        sem_wait(FSem^); // trava

        for I := 0 to MAX_REGISTROS - 1 do
        begin
            lPReg := Ptr(UIntPtr(FPtr) + UIntPtr(I * REG_SIZE));
            if lPReg^.CorrelationId[0] <> #0 then
                lLista.Add(lPReg^);
        end;

        sem_post(FSem^); // libera

        Result := lLista.ToArray;
    finally
        lLista.Free;
    end;
end;

function TPersistencia.ConsultarDados(const AFrom, ATo: string): TJSONObject;
var
    lReg: TRegistro;
    ldReg: TDateTime;
    ldFrom: TDateTime;
    ldTo: TDateTime;
    TotalDefault: Integer;
    TotalFallback: Integer;
    AmountDefault: Double;
    AmountFallback: Double;
    lDefault: TJSONObject;
    lFallback: TJSONObject;
    lResultado: TJSONObject;
    lTodos: TArray<TRegistro>;
begin
    TotalDefault := 0;
    TotalFallback := 0;
    AmountDefault := 0;
    AmountFallback := 0;

    ldFrom := ISO8601ToDate(AFrom, True);
    ldTo := ISO8601ToDate(ATo, True);

    lTodos := LerTodos;

    for lReg in lTodos do
    begin
        ldReg := ISO8601ToDate(string(lReg.RequestedAt), True);

        if (ldReg >= ldFrom) and (ldReg <= ldTo) then
        begin
            if lReg.Service = 0 then
            begin
                Inc(TotalDefault);
                AmountDefault := AmountDefault + lReg.Amount;
            end
            else
            begin
                Inc(TotalFallback);
                AmountFallback := AmountFallback + lReg.Amount;
            end;
        end;
    end;

    lDefault := TJSONObject.Create;
    lDefault.AddPair('totalRequests', TJSONNumber.Create(TotalDefault));
    lDefault.AddPair('totalAmount', FormatFloat('0.00', AmountDefault));

    lFallback := TJSONObject.Create;
    lFallback.AddPair('totalRequests', TJSONNumber.Create(TotalFallback));
    lFallback.AddPair('totalAmount', FormatFloat('0.00', AmountFallback));

    lResultado := TJSONObject.Create;
    lResultado.AddPair('default', lDefault);
    lResultado.AddPair('fallback', lFallback);

    Result := lResultado;
end;

end.
