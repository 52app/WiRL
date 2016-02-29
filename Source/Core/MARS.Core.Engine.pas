(*
  Copyright 2015, MARS - REST Library

  Home: https://github.com/MARS-library

*)
unit MARS.Core.Engine;

interface

uses
  SysUtils, HTTPApp, Classes, Generics.Collections
  , SyncObjs
  , Diagnostics

  , MARS.Core.Classes
  , MARS.Core.Registry
  , MARS.Core.Application
  , MARS.Core.URL
;

{$M+}

type
  TMARSEngine = class;

  IMARSHandleRequestEventListener = interface
    procedure BeforeHandleRequest(const ASender: TMARSEngine; const AApplication: TMARSApplication);
    procedure AfterHandleRequest(const ASender: TMARSEngine; const AApplication: TMARSApplication; const AStopWatch: TStopWatch);
  end;

  TMARSEngine = class
  private
    FApplications: TMARSApplicationDictionary;
    FSubscribers: TList<IMARSHandleRequestEventListener>;
    FCriticalSection: TCriticalSection;
    FBasePath: string;
    FSessionTimeOut: Integer;
    FPort: Integer;
    FThreadPoolSize: Integer;
    FName: string;
  class threadvar
    FWebRequest: TWebRequest;
    FWebResponse: TWebResponse;
    FURL: TMARSURL;

    function GetCurrentRequest: TWebRequest;
    function GetCurrentResponse: TWebResponse;
    function GetURL: TMARSURL;
  protected
    procedure DoBeforeHandleRequest(const AApplication: TMARSApplication); virtual;
    procedure DoAfterHandleRequest(const AApplication: TMARSApplication; const AStopWatch: TStopWatch); virtual;
  public
    constructor Create;
    destructor Destroy; override;

    function HandleRequest(ARequest: TWebRequest; AResponse: TWebResponse): Boolean;

    function AddApplication(const AName, ABasePath: string; const AResources: array of string): TMARSApplication; virtual;
    procedure AddSubscriber(const ASubscriber: IMARSHandleRequestEventListener);
    procedure RemoveSubscriber(const ASubscriber: IMARSHandleRequestEventListener);

    procedure EnumerateApplications(const ADoSomething: TProc<string, TMARSApplication>);

    property Applications: TMARSApplicationDictionary read FApplications;
    property BasePath: string read FBasePath write FBasePath;
    property Name: string read FName write FName;
    property Port: Integer read FPort write FPort;
    property SessionTimeOut: Integer read FSessionTimeOut write FSessionTimeOut;
    property ThreadPoolSize: Integer read FThreadPoolSize write FThreadPoolSize;

    // Transient properties
    property CurrentURL: TMARSURL read GetURL;
    property CurrentRequest: TWebRequest read GetCurrentRequest;
    property CurrentResponse: TWebResponse read GetCurrentResponse;
  end;

implementation

uses
  MARS.Core.Utils
  ;

function TMARSEngine.AddApplication(const AName, ABasePath: string;
  const AResources: array of string): TMARSApplication;
var
  LResource: string;
begin
  Result := TMARSApplication.Create(Self);
  try
    Result.Name := AName;
    Result.BasePath := ABasePath;
    for LResource in AResources do
      Result.AddResource(LResource);

    Applications.Add(
      TMARSURL.CombinePath([BasePath, ABasePath])
      , Result
    );
  except
    Result.Free;
    raise
  end;
end;

procedure TMARSEngine.AddSubscriber(
  const ASubscriber: IMARSHandleRequestEventListener);
begin
  FSubscribers.Add(ASubscriber);
end;

constructor TMARSEngine.Create;
begin
  FApplications := TMARSApplicationDictionary.Create([doOwnsValues]);
  FCriticalSection := TCriticalSection.Create;
  FSubscribers := TList<IMARSHandleRequestEventListener>.Create;
  FSessionTimeOut := 1200000;
  FPort := 8080;
  FThreadPoolSize := 75;
  FBasePath := '/rest';
  FName := 'MARS Engine';

  inherited Create;
end;

destructor TMARSEngine.Destroy;
begin
  FCriticalSection.Free;
  FApplications.Free;
  FSubscribers.Free;
  inherited;
end;

procedure TMARSEngine.DoAfterHandleRequest(const AApplication: TMARSApplication;
  const AStopWatch: TStopWatch);
var
  LSubscriber: IMARSHandleRequestEventListener;
begin
  for LSubscriber in FSubscribers do
    LSubscriber.AfterHandleRequest(Self, AApplication, AStopWatch);
end;

procedure TMARSEngine.DoBeforeHandleRequest(const AApplication: TMARSApplication);
var
  LSubscriber: IMARSHandleRequestEventListener;
begin
  for LSubscriber in FSubscribers do
    LSubscriber.BeforeHandleRequest(Self, AApplication);
end;

procedure TMARSEngine.EnumerateApplications(
  const ADoSomething: TProc<string, TMARSApplication>);
var
  LPair: TPair<string, TMARSApplication>;
begin
  if Assigned(ADoSomething) then
  begin
    FCriticalSection.Enter;
    try
      for LPair in FApplications do
        ADoSomething(LPair.Key, LPair.Value);
    finally
      FCriticalSection.Leave;
    end;
  end;
end;

function TMARSEngine.HandleRequest(ARequest: TWebRequest; AResponse: TWebResponse): Boolean;
var
  LApplication: TMARSApplication;
  LURL: TMARSURL;
  LApplicationPath: string;
  LStopWatch: TStopWatch;
begin
  Result := False;

  LURL := TMARSURL.Create(ARequest);
  try
    LApplicationPath := TMARSURL.CombinePath([LURL.PathTokens[0]]);
    if (BasePath <> '') and (BasePath <> TMARSURL.URL_PATH_SEPARATOR) then
    begin
        if not LURL.MatchPath(BasePath + TMARSURL.URL_PATH_SEPARATOR) then
        raise Exception.CreateFmt('[Engine] Requested URL [%s] does not match base engine URL [%s]', [LURL.URL, BasePath]);
      LApplicationPath := TMARSURL.CombinePath([LURL.PathTokens[0], LURL.PathTokens[1]]);
    end;

    if FApplications.TryGetValue(LApplicationPath, LApplication) then
    begin
      LURL.BasePath := LApplicationPath;
      FWebRequest := ARequest;
      FWebResponse := AResponse;
      FURL := LURL;
      DoBeforeHandleRequest(LApplication);
      LStopWatch := TStopwatch.StartNew;
      LApplication.HandleRequest(ARequest, AResponse, LURL);
      LStopWatch.Stop;
      DoAfterHandleRequest(LApplication, LStopWatch);

      Result := True;
    end
    else
      raise Exception.CreateFmt('[Engine] Requested URL [%s] belongs to an unknown application [%s]', [LURL.URL, LApplicationPath]);
  finally
    LURL.Free;
  end;
end;

procedure TMARSEngine.RemoveSubscriber(
  const ASubscriber: IMARSHandleRequestEventListener);
begin
  FSubscribers.Remove(ASubscriber);
end;

function TMARSEngine.GetCurrentRequest: TWebRequest;
begin
  Result := FWebRequest;
end;

function TMARSEngine.GetCurrentResponse: TWebResponse;
begin
  Result := FWebResponse;
end;

function TMARSEngine.GetURL: TMARSURL;
begin
  Result := FURL;
end;

end.
