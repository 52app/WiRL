(*
  Copyright 2015-2016, MARS - REST Library

  Home: https://github.com/MARS-library

*)
unit MARS.Data.MessageBodyWriters;

interface

uses
  Classes, SysUtils, Rtti

  , MARS.Core.Attributes
  , MARS.Core.Declarations
  , MARS.Core.MediaType
  , MARS.Core.MessageBodyWriter
  ;

type
  [Produces(TMediaType.APPLICATION_JSON)]
  TDataSetWriterJSON = class(TInterfacedObject, IMessageBodyWriter)
    procedure WriteTo(const AValue: TValue; const AAttributes: TAttributeArray;
      AMediaType: TMediaType; AResponseHeaders: TStrings; AOutputStream: TStream);
  end;

  [Produces(TMediaType.APPLICATION_JSON)]
  TArrayDataSetWriter = class(TInterfacedObject, IMessageBodyWriter)
    procedure WriteTo(const AValue: TValue; const AAttributes: TAttributeArray;
      AMediaType: TMediaType; AResponseHeaders: TStrings; AOutputStream: TStream);
  end;

  [Produces(TMediaType.APPLICATION_XML)]
  TDataSetWriterXML = class(TInterfacedObject, IMessageBodyWriter)
    procedure WriteTo(const AValue: TValue; const AAttributes: TAttributeArray;
      AMediaType: TMediaType; AResponseHeaders: TStrings; AOutputStream: TStream);
  end;

implementation

uses
  DB, DBClient
  , MARS.Core.JSON
  , MARS.Data.Utils
  , MARS.Rtti.Utils
  ;

{ TDataSetWriterJSON }

procedure TDataSetWriterJSON.WriteTo(const AValue: TValue;
  const AAttributes: TAttributeArray; AMediaType: TMediaType;
  AResponseHeaders: TStrings; AOutputStream: TStream);
var
  LStreamWriter: TStreamWriter;
  LResult: TJSONArray;
begin
  LStreamWriter := TStreamWriter.Create(AOutputStream);
  try
    LResult := TDataUtils.DataSetToJSONArray(AValue.AsObject as TDataSet);
    try
      LStreamWriter.Write(TJSONHelper.ToJSON(LResult));
    finally
      LResult.Free;
    end;
  finally
    LStreamWriter.Free;
  end;
end;

{ TDataSetWriterXML }

procedure TDataSetWriterXML.WriteTo(const AValue: TValue;
  const AAttributes: TAttributeArray; AMediaType: TMediaType;
  AResponseHeaders: TStrings; AOutputStream: TStream);
var
  LStreamWriter: TStreamWriter;
begin
  LStreamWriter := TStreamWriter.Create(AOutputStream);
  try
    if AValue.AsObject is TClientDataSet then // CDS
      LStreamWriter.Write(TClientDataSet(AValue.AsObject).XMLData)
    else // default
      LStreamWriter.Write(TDataUtils.DataSetToXML(Avalue.AsObject as TDataSet));
  finally
    LStreamWriter.Free;
  end;
end;

{ TArrayDataSetWriter }

procedure TArrayDataSetWriter.WriteTo(const AValue: TValue;
  const AAttributes: TAttributeArray; AMediaType: TMediaType;
  AResponseHeaders: TStrings; AOutputStream: TStream);
var
  LStreamWriter: TStreamWriter;
  LResult: TJSONObject;
  LData: TArray<TDataSet>;
  LCurrent: TDataSet;
begin
  LStreamWriter := TStreamWriter.Create(AOutputStream);
  try
    LData := AValue.AsType<TArray<TDataSet>>;
    LResult := TJSONObject.Create;
    try
      for LCurrent in LData do
        LResult.AddPair(LCurrent.Name, TDataUtils.DataSetToJSONArray(LCurrent));

      LStreamWriter.Write(TJSONHelper.ToJSON(LResult));
    finally
      LResult.Free;
    end;
  finally
    LStreamWriter.Free;
  end;
end;

procedure RegisterWriters;
begin
  TMARSMessageBodyRegistry.Instance.RegisterWriter(
    TDataSetWriterJSON
    , function (AType: TRttiType; const AAttributes: TAttributeArray; AMediaType: string): Boolean
      begin
        Result := Assigned(AType) and  TRttiHelper.IsObjectOfType<TDataSet>(AType); // and AMediaType = application/json
      end
    , function (AType: TRttiType; const AAttributes: TAttributeArray; AMediaType: string): Integer
      begin
        Result := TMARSMessageBodyRegistry.AFFINITY_LOW;
      end
  );

  TMARSMessageBodyRegistry.Instance.RegisterWriter(
    TArrayDataSetWriter
    , function (AType: TRttiType; const AAttributes: TAttributeArray; AMediaType: string): Boolean
      begin
        Result := Assigned(AType) and TRttiHelper.IsDynamicArrayOf<TDataSet>(AType); // and AMediaType = application/json
      end
    , function (AType: TRttiType; const AAttributes: TAttributeArray; AMediaType: string): Integer
      begin
        Result := TMARSMessageBodyRegistry.AFFINITY_LOW
      end
  );

  TMARSMessageBodyRegistry.Instance.RegisterWriter(
    TDataSetWriterXML
    , function (AType: TRttiType; const AAttributes: TAttributeArray; AMediaType: string): Boolean
      begin
        Result := Assigned(AType) and TRttiHelper.IsObjectOfType<TDataSet>(AType); // and AMediaType = application/xml
      end
    , function (AType: TRttiType; const AAttributes: TAttributeArray; AMediaType: string): Integer
      begin
        Result := TMARSMessageBodyRegistry.AFFINITY_LOW;
      end
  );
end;

initialization
  RegisterWriters;

end.
