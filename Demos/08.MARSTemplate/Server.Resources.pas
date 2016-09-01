(*
  Copyright 2015-2016, MARS - REST Library

  Home: https://github.com/MARS-library

*)
unit Server.Resources;

interface

uses
  SysUtils, Classes,

  MARS.Core.Attributes,
  MARS.Core.MediaType,
  MARS.Core.Request,
  MARS.Core.Response;

type
  [Path('helloworld')]
  THelloWorldResource = class
  private
  protected
    [Context] Req: TMARSRequest;
  public

    [GET, Produces(TMediaType.TEXT_PLAIN)]
    function SayHelloWorld: string;

  end;

implementation

uses
    MARS.Core.Registry
  ;


{ THelloWorldResource }

function THelloWorldResource.SayHelloWorld: string;
begin
  Result := 'Hello World!';
end;

initialization
  TMARSResourceRegistry.Instance.RegisterResource<THelloWorldResource>;


end.
