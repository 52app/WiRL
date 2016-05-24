(*
  Copyright 2015, MARS - REST Library

  Home: https://github.com/MARS-library

*)
unit MARS.http.Server.Indy;

interface

uses
  Classes, SysUtils
  , SyncObjs
  , IdContext, IdCustomHTTPServer, IdException, IdTCPServer, IdIOHandlerSocket
  , IdSchedulerOfThreadPool

  , MARS.Core.Engine
  , MARS.Core.Token
  ;

type
  TMARShttpServerIndy = class(TIdCustomHTTPServer)
  private
    FEngine: TMARSEngine;
    FTokenList: TMARSTokenList;
  protected
    procedure DoOnCreateSession(AContext: TIdContext;
      var VNewSession: TIdHTTPSession); override;
    procedure DoSessionEnd(Sender: TIdHTTPSession); override;
    procedure DoSessionStart(Sender: TIdHTTPSession); override;
    procedure Startup; override;
    procedure Shutdown; override;
    procedure DoCommandGet(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo); override;
    procedure DoCommandOther(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo); override;

    procedure InitComponent; override;
    procedure SetupThreadPooling(const APoolSize: Integer = 25);
  public
    constructor Create(AEngine: TMARSEngine); virtual;
    property Engine: TMARSEngine read FEngine;
  end;

implementation

uses
  StrUtils
  , idHTTPWebBrokerBridge
  , MARS.Core.Utils
  ;

{ TMARShttpServerIndy }

constructor TMARShttpServerIndy.Create(AEngine: TMARSEngine);
begin
  inherited Create(nil);
  FEngine := AEngine;
end;

procedure TMARShttpServerIndy.DoCommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  LRequest: TIdHTTPAppRequest;
  LResponse: TIdHTTPAppResponse;
  LToken: TMARSToken;
begin
  inherited;

  LRequest := TIdHTTPAppRequest.Create(AContext, ARequestInfo, AResponseInfo);
  try
    LResponse := TIdHTTPAppResponse.Create(LRequest, AContext, ARequestInfo, AResponseInfo);
    try
      // WebBroker will free it and we cannot change this behaviour
      LResponse.FreeContentStream := False;
      AResponseInfo.FreeContentStream := True;
      // skip browser requests (can be dangerous since it is a bit wide as approach)
      if not EndsText('favicon.ico', string(LRequest.PathInfo)) then
      begin
        LToken := FTokenList.GetToken(LRequest);
        if Assigned(LToken) then
          LToken.LastRequest := string(LRequest.PathInfo);

        FEngine.HandleRequest(LRequest, LResponse);
      end;
      AResponseInfo.CustomHeaders.AddStrings(LResponse.CustomHeaders);
    finally
      FreeAndNil(LResponse);
    end;
  finally
    FreeAndNil(LRequest);
  end;
end;

procedure TMARShttpServerIndy.DoCommandOther(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  inherited;
  DoCommandGet(AContext, ARequestInfo, AResponseInfo);
end;

procedure TMARShttpServerIndy.DoOnCreateSession(AContext: TIdContext;
  var VNewSession: TIdHTTPSession);
var
  LTokenID: string;
begin
  inherited;

  LTokenID := CreateCompactGuidStr;
  MARS.Core.Token._TOKEN := LTokenID;

  VNewSession := TIdHTTPSession.CreateInitialized(SessionList, LTokenID, AContext.Connection.Socket.Binding.PeerIP);
end;

procedure TMARShttpServerIndy.DoSessionEnd(Sender: TIdHTTPSession);
begin
  inherited;

  FTokenList.RemoveToken(Sender.SessionID);
end;

procedure TMARShttpServerIndy.DoSessionStart(Sender: TIdHTTPSession);
begin
  inherited;

  FTokenList.AddToken(Sender.SessionID);
  end;

procedure TMARShttpServerIndy.InitComponent;
begin
  inherited;
  FTokenList := TMARSTokenList.Instance;
end;

procedure TMARShttpServerIndy.SetupThreadPooling(const APoolSize: Integer);
var
  LScheduler: TIdSchedulerOfThreadPool;
begin
  if Assigned(Scheduler) then
  begin
    Scheduler.Free;
    Scheduler := nil;
  end;

  LScheduler := TIdSchedulerOfThreadPool.Create(Self);
  LScheduler.PoolSize := APoolSize;
  Scheduler := LScheduler;
  MaxConnections := LScheduler.PoolSize;
end;

procedure TMARShttpServerIndy.Shutdown;
begin
  inherited;
  Bindings.Clear;
end;

procedure TMARShttpServerIndy.Startup;
begin
  Bindings.Clear;
  DefaultPort := FEngine.Port;

  AutoStartSession := True;
  SessionTimeOut := FEngine.SessionTimeout;
  SessionState := True;

  inherited;
end;

end.
