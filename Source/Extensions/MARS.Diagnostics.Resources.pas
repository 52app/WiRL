(*
  Copyright 2015-2016, MARS - REST Library

  Home: https://github.com/MARS-library

*)
unit MARS.Diagnostics.Resources;

{$I MARS.inc}

interface

uses
  System.Classes, System.SysUtils,

  MARS.Core.JSON,
  MARS.Core.Registry,
  MARS.Core.Classes,
  MARS.Core.Application,
  MARS.Core.Declarations,
  MARS.Core.Attributes,
  MARS.Core.MediaType,
  MARS.Core.MessageBodyWriter,
  MARS.Core.Token,
  MARS.Core.URL,
  MARS.Core.Engine,
  MARS.Diagnostics.Manager;

type
  [Path('manager')]
  TDiagnosticsResource = class
  private
  protected
    [Context] URL: TMARSURL;
  public
    [GET]
    [Produces(TMediaType.APPLICATION_JSON)]
    function RetrieveAll: TJSONObject;

    [GET][Path('app')]
    [Produces(TMediaType.APPLICATION_JSON)]
    function RetrieveApp: TJSONObject;
  end;

  [Path('resources')]
  TResourcesResource = class
  private
  protected
    [Context] Engine: TMARSEngine;
  public
    [GET]
    [Produces(TMediaType.APPLICATION_JSON)]
    function RetrieveAll: TJSONValue;
  end;

implementation

{ TDiagnosticsResource }

function TDiagnosticsResource.RetrieveAll: TJSONObject;
begin
  Result := TMARSDiagnosticsManager.Instance.ToJSON;
end;

function TDiagnosticsResource.RetrieveApp: TJSONObject;

  function ToString(const AArray: TArray<string>): string;
  var
    LString: string;
  begin
    Result := '';
    for LString in AArray do
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + LString;
    end;
  end;

var
  LObj: TJSONObject;
  LAppName: string;
begin
  if URL.HasSubResources then
    LAppName := URL.SubResources[0]
  else
    raise Exception.Create('No app name provided');

  LObj := nil;
  TMARSDiagnosticsManager.Instance.RetrieveAppInfo(LAppName,
    procedure(AInfo: TMARSDiagnosticAppInfo)
    begin
      LObj := AInfo.ToJSON;
    end
  );

  LObj.AddPair('app', LAppName);
  Result := LObj;
end;

{ TResourcesResource }

function TResourcesResource.RetrieveAll: TJSONValue;
var
  LApplications: TJSONArray;
begin
  LApplications := TJSONArray.Create;
  Engine.EnumerateApplications(
    procedure(AName: string; AApplication: TMARSApplication)
    var
      LObj: TJSONObject;
      LResources: TJSONArray;
      LResource: string;
    begin
      LResources := TJSONArray.Create;

      for LResource in AApplication.Resources do
        LResources.Add(LResource);

      LObj := TJSONObject.Create;
      LObj.AddPair(AName, LResources);
      LApplications.AddElement(LObj);
    end
  );

  Result := LApplications;
end;

initialization
  TMARSResourceRegistry.Instance.RegisterResource<TDiagnosticsResource>(nil);
  TMARSResourceRegistry.Instance.RegisterResource<TResourcesResource>(nil);

end.
