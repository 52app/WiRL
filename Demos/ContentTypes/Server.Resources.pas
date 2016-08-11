(*
  Copyright 2015-2016, MARS - REST Library

  Home: https://github.com/MARS-library

*)
unit Server.Resources;

interface

uses
  SysUtils, Classes, DB,

  FireDAC.Comp.Client,

  MARS.Core.Attributes,
  MARS.Core.MediaType,

  MARS.Core.JSON;

type
  [Path('helloworld')]
  THelloWorldResource = class
  private
  protected
  public
    [GET, Produces(TMediaType.TEXT_PLAIN)]
    function SayHelloWorld: string;

    [GET, Path('/html'), Produces(TMediaType.TEXT_HTML)]
    function HtmlDocument: string;

    [GET, Path('/json'), Produces(TMediaType.APPLICATION_JSON)]
    function JSON1: TJSONObject;

    [GET, Path('/jpeg'), Produces('image/jpg')]
    function JpegImage: TStream;

    [GET, Path('/pdf'), Produces('application/pdf')]
    function PdfDocument: TStream;

    [
      GET, Path('/dataset1'),
      Produces(TMediaType.APPLICATION_XML),
      Produces(TMediaType.APPLICATION_JSON)
    ]
    function DataSet1: TDataSet;

    [
      GET, Path('/dataset2'),
      Produces(TMediaType.APPLICATION_XML),
      Produces(TMediaType.APPLICATION_JSON)
    ]
    function DataSet2: TFDMemTable;

    [
      GET, Path('/dataset3'),
      Produces(TMediaType.APPLICATION_JSON)
    ]
    function DataSet3: TDataset;

  end;

implementation

uses
  MARS.Core.Registry, DBClient;


{ THelloWorldResource }

function THelloWorldResource.DataSet1: TDataSet;
var
  LCDS: TClientDataSet;
begin
  LCDS := TClientDataSet.Create(nil);
  LCDS.FieldDefs.Add('Name', ftString, 100);
  LCDS.FieldDefs.Add('Surname', ftString, 100);
  LCDS.CreateDataSet;
  LCDS.Open;

  Result := LCDS;
  Result.AppendRecord(['Andrea', 'Magni']);
  Result.AppendRecord(['Paolo', 'Rossi']);
  Result.AppendRecord(['Mario', 'Bianchi']);
end;

function THelloWorldResource.DataSet2: TFDMemTable;
begin
  Result := TFDMemTable.Create(nil);
  Result.FieldDefs.Add('Name', ftString, 100);
  Result.FieldDefs.Add('Surname', ftString, 100);
  Result.CreateDataSet;
  Result.AppendRecord(['Andrea', 'Magni']);
  Result.AppendRecord(['Paolo', 'Rossi']);
  Result.AppendRecord(['Mario', 'Bianchi']);
end;

function THelloWorldResource.DataSet3: TDataset;
begin
  Result := DataSet2;
end;

function THelloWorldResource.HtmlDocument: string;
begin
  Result := '<html><body>'
    + '<h2>Hello World!</h2>'
    + '<p>This is only a test.</p>'
    + '</body></html>';
end;

function THelloWorldResource.JpegImage: TStream;
begin
  Result := TFileStream.Create('image.jpg', fmOpenRead or fmShareDenyWrite);
end;

function THelloWorldResource.JSON1: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('Hello', 'World');
end;

function THelloWorldResource.PdfDocument: TStream;
begin
  Result := TFileStream.Create('document.pdf', fmOpenRead or fmShareDenyWrite);
end;

function THelloWorldResource.SayHelloWorld: string;
begin
  Result := 'Hello World!';
end;

initialization
  TMARSResourceRegistry.Instance.RegisterResource<THelloWorldResource>;

end.
