(*
  Copyright 2015, MARS - REST Library

  Home: https://github.com/MARS-library

*)
unit MARS.Core.Application;

{$I MARS.inc}

interface

// JAX-RS Objects Life-Cycle
// https://jersey.java.net/documentation/latest/deployment.html
// https://jersey.java.net/documentation/latest/jaxrs-resources.html
// http://www.mkyong.com/webservices/jax-rs/jax-rs-path-uri-matching-example/

uses
  SysUtils
  , Classes
  , HTTPApp
  , Rtti
  , Generics.Collections
  , MARS.Core.Classes
  , MARS.Core.URL
  , MARS.Core.MessageBodyWriter
  , MARS.Core.Registry
  , MARS.Core.MediaType
  , MARS.Core.Token
  ;

type
  TAttributeArray = TArray<TCustomAttribute>;
  TArgumentArray = array of TValue;

  TMARSApplication = class
  private
    FRttiContext: TRttiContext;
    FResourceRegistry: TObjectDictionary<string, TMARSConstructorInfo>;
    FBasePath: string;
    FName: string;
    FEngine: TObject;
    FSystem: Boolean;
    function GetResources: TArray<string>;
    function GetRequest: TWebRequest;
    function GetResponse: TWebResponse;
    function GetURL: TMARSURL;
  protected
    function FindMethodToInvoke(const AURL: TMARSURL;
      const AInfo: TMARSConstructorInfo): TRttiMethod; virtual;

    function FillAnnotatedParam(AParam: TRttiParameter; const AAttrArray: TAttributeArray;
      AResourceInstance: TObject; AMethod: TRttiMethod): TValue;
    function FillNonAnnotatedParam(AParam: TRttiParameter): TValue;
    procedure FillResourceMethodParameters(AInstance: TObject; AMethod: TRttiMethod; var AArgumentArray: TArgumentArray);

    /// <summary>
    ///   Invoke the resource's method filling it's parameters (if any)
    /// </summary>
    /// <returns>
    ///   Return the object to be freed after the function goes out of scope
    /// </returns>
    procedure InvokeResourceMethod(AInstance: TObject; AMethod: TRttiMethod;
      const AWriter: IMessageBodyWriter; ARequest: TWebRequest;
      AMediaType: TMediaType); virtual;

    procedure CheckAuthorization(const AMethod: TRttiMethod; const AToken: TMARSToken);
    procedure ContextInjection(AInstance: TObject);
    function ContextInjectionByType(const AType: TClass; out AValue: TValue): Boolean;

    function ParamNameToParamIndex(AResourceInstance: TObject; const AParamName: string; AMethod: TRttiMethod): Integer;

    property Engine: TObject read FEngine;
    property Request: TWebRequest read GetRequest;
    property Response: TWebResponse read GetResponse;
    property URL: TMARSURL read GetURL;
  public
    constructor Create(const AEngine: TObject);
    destructor Destroy; override;

    function AddResource(AResource: string): Boolean;

    procedure HandleRequest(ARequest: TWebRequest; AResponse: TWebResponse; const
        AURL: TMARSURL);
    procedure CollectGarbage(const AValue: TValue);

    property Name: string read FName write FName;
    property BasePath: string read FBasePath write FBasePath;
    property System: Boolean read FSystem write FSystem;
    property Resources: TArray<string> read GetResources;
  end;

  TMARSApplicationDictionary = class(TObjectDictionary<string, TMARSApplication>)
  end;

implementation

uses
  StrUtils
  , TypInfo
  , MARS.Core.Exceptions
  , MARS.Core.Utils
  , MARS.Rtti.Utils
  , MARS.Core.Response
  , MARS.Core.Attributes
  , MARS.Core.Engine
  , MARS.Core.JSON
  ;

{ TMARSApplication }

function TMARSApplication.AddResource(AResource: string): Boolean;

  function AddResourceToApplicationRegistry(const AInfo: TMARSConstructorInfo): Boolean;
  var
    LClass: TClass;
    LResult: Boolean;
  begin
    LResult := False;
    LClass := AInfo.TypeTClass;
    FRttiContext.GetType(LClass).HasAttribute<PathAttribute>(
      procedure (AAttribute: PathAttribute)
      var
        LURL: TMARSURL;
      begin
        LURL := TMARSURL.CreateDummy(AAttribute.Value);
        try
          if not FResourceRegistry.ContainsKey(LURL.PathTokens[0]) then
          begin
            FResourceRegistry.Add(LURL.PathTokens[0], AInfo.Clone);
            LResult := True;
          end;
        finally
          LURL.Free;
        end;
      end
    );
    Result := LResult;
  end;

var
  LRegistry: TMARSResourceRegistry;
  LInfo: TMARSConstructorInfo;
  LKey: string;
begin
  Result := False;
  LRegistry := TMARSResourceRegistry.Instance;

  if IsMask(AResource) then // has wildcards and so on...
  begin
    for LKey in LRegistry.Keys.ToArray do
    begin
      if MatchesMask(LKey, AResource) then
      begin
        if LRegistry.TryGetValue(LKey, LInfo) and AddResourceToApplicationRegistry(LInfo) then
          Result := True;
      end;
    end;
  end
  else // exact match
    if LRegistry.TryGetValue(AResource, LInfo) then
      Result := AddResourceToApplicationRegistry(LInfo);
end;

procedure TMARSApplication.CheckAuthorization(const AMethod: TRttiMethod; const AToken: TMARSToken);
var
  LDenyAll, LPermitAll, LRolesAllowed: Boolean;
  LAllowedRoles: TStringList;
  LAllowed: Boolean;
  LRole: string;
begin
  LAllowed := True; // Default = True for non annotated-methods
  LDenyAll := False;
  LPermitAll := False;
  LAllowedRoles := TStringList.Create;
  try
    LAllowedRoles.Sorted := True;
    LAllowedRoles.Duplicates := TDuplicates.dupIgnore;

    AMethod.ForEachAttribute<AuthorizationAttribute>(
      procedure (AAttribute: AuthorizationAttribute)
      begin
        if AAttribute is DenyAllAttribute then
          LDenyAll := True
        else if AAttribute is PermitAllAttribute then
          LPermitAll := True
        else if AAttribute is RolesAllowedAttribute then
        begin
          LRolesAllowed := True;
          LAllowedRoles.AddStrings(RolesAllowedAttribute(AAttribute).Roles);
        end;
      end
    );

  if LDenyAll then
    LAllowed := False
  else
  begin
    if LRolesAllowed then
    begin
      LAllowed := False;
      for LRole in LAllowedRoles do
      begin
        LAllowed := AToken.UserRoles.IndexOf(LRole) <> -1;
        if LAllowed then
          Break;
      end;
    end;

    if LPermitAll then
      LAllowed := True;
  end;

  if not LAllowed then
    raise EMARSNotAuthorizedException.Create('Method call not authorized', Self.ClassName);

  finally
    LAllowedRoles.Free;
  end;
end;

procedure TMARSApplication.CollectGarbage(const AValue: TValue);
var
  LIndex: Integer;
  LValue: TValue;
begin
  case AValue.Kind of
    tkClass: AValue.AsObject.Free;

    { TODO -opaolo -c : could be dangerous?? 14/01/2015 13:18:38 }
    tkInterface: TObject(AValue.AsInterface).Free;

    tkArray,
    tkDynArray:
    begin
      for LIndex := 0 to AValue.GetArrayLength -1 do
      begin
        LValue := AValue.GetArrayElement(LIndex);
        case LValue.Kind of
          tkClass: LValue.AsObject.Free;
          tkInterface: TObject(LValue.AsInterface).Free;
          tkArray, tkDynArray: CollectGarbage(LValue); //recursion
        end;
      end;
    end;
  end;
end;

procedure TMARSApplication.ContextInjection(AInstance: TObject);
var
  LType: TRttiType;
begin
  LType := FRttiContext.GetType(AInstance.ClassType);
  // Context injection
  LType.ForEachFieldWithAttribute<ContextAttribute>(
    function (AField: TRttiField; AAttrib: ContextAttribute): Boolean
    var
      LFieldClassType: TClass;
      LValue: TValue;
    begin
      Result := True; // enumerate all
      if (AField.FieldType.IsInstance) then
      begin
        LFieldClassType := TRttiInstanceType(AField.FieldType).MetaclassType;

        if ContextInjectionByType(LFieldClassType, LValue) then
          AField.SetValue(AInstance, LValue);
      end;
    end
  );

  // properties
  LType.ForEachPropertyWithAttribute<ContextAttribute>(
    function (AProperty: TRttiProperty; AAttrib: ContextAttribute): Boolean
    var
      LPropertyClassType: TClass;
      LValue: TValue;
    begin
      Result := True; // enumerate all
      if (AProperty.PropertyType.IsInstance) then
      begin
        LPropertyClassType := TRttiInstanceType(AProperty.PropertyType).MetaclassType;
        if ContextInjectionByType(LPropertyClassType, LValue) then
          AProperty.SetValue(AInstance, LValue);
      end;
    end
  );
end;

function TMARSApplication.ContextInjectionByType(const AType: TClass;
  out AValue: TValue): Boolean;
begin
  Result := True;
  // Token
  if (AType.InheritsFrom(TMARSToken)) then
    AValue := TMARSTokenList.Instance.GetToken(Request)
  // HTTP request
  else if (AType.InheritsFrom(TWebRequest)) then
    AValue := Request
  // HTTP response
  else if (AType.InheritsFrom(TWebResponse)) then
    AValue := Response
  // URL info
  else if (AType.InheritsFrom(TMARSURL)) then
    AValue := URL
  // Engine
  else if (AType.InheritsFrom(TMARSEngine)) then
    AValue := Engine
  else
    Result := False;
end;

constructor TMARSApplication.Create(const AEngine: TObject);
begin
  inherited Create;
  FEngine := AEngine;
  FRttiContext := TRttiContext.Create;
  FResourceRegistry := TObjectDictionary<string, TMARSConstructorInfo>.Create([doOwnsValues]);
end;

destructor TMARSApplication.Destroy;
begin
  FResourceRegistry.Free;
  inherited;
end;

function TMARSApplication.FindMethodToInvoke(const AURL: TMARSURL;
  const AInfo: TMARSConstructorInfo): TRttiMethod;
var
  LResourceType: TRttiType;
  LMethod: TRttiMethod;
  LResourcePath: string;
  LAttribute: TCustomAttribute;
  LPrototypeURL: TMARSURL;
  LPathMatches: Boolean;
  LHttpMethodMatches: Boolean;
  LMethodPath: string;
begin
  LResourceType := FRttiContext.GetType(AInfo.TypeTClass);
  Result := nil;
  LResourcePath := '';

  LResourceType.HasAttribute<PathAttribute>(
    procedure (APathAttribute: PathAttribute)
    begin
      LResourcePath := APathAttribute.Value;
    end
  );

  for LMethod in LResourceType.GetMethods do
  begin
    LMethodPath := '';
    LHttpMethodMatches := False;

    for LAttribute in LMethod.GetAttributes do
    begin
      if LAttribute is PathAttribute then
        LMethodPath := PathAttribute(LAttribute).Value;

      if LAttribute is HttpMethodAttribute then
        LHttpMethodMatches := HttpMethodAttribute(LAttribute).Matches(Request);
    end;

    if LHttpMethodMatches then
    begin
      LPrototypeURL := TMARSURL.CreateDummy([TMARSEngine(Engine).BasePath, BasePath, LResourcePath, LMethodPath]);
      try
        LPathMatches := LPrototypeURL.MatchPath(URL);
      finally
        LPrototypeURL.Free;
      end;

      if LPathMatches and LHttpMethodMatches then
      begin
        Result := LMethod;
        Break;
      end;
    end;
  end;
end;

function TMARSApplication.GetRequest: TWebRequest;
begin
  Result := TMARSEngine(Engine).CurrentRequest;
end;

function TMARSApplication.GetResources: TArray<string>;
begin
  Result := FResourceRegistry.Keys.ToArray;
end;

function TMARSApplication.GetResponse: TWebResponse;
begin
  Result := TMARSEngine(Engine).CurrentResponse;
end;

function TMARSApplication.GetURL: TMARSURL;
begin
  Result := TMARSEngine(Engine).CurrentURL;
end;

function ExtractToken(const AString: string; const ATokenIndex: Integer; const ADelimiter: Char = '/'): string;
var
  LTokens: TArray<string>;
begin
  LTokens := TArray<string>(SplitString(AString, ADelimiter));

  Result := '';
  if ATokenIndex < Length(LTokens) then
    Result := LTokens[ATokenIndex]
  else
    raise EMARSServerException.Create(
      Format('ExtractToken, index: %d from %s', [ATokenIndex, AString]), 'ExtractToken');
end;


function TMARSApplication.FillAnnotatedParam(AParam: TRttiParameter;
  const AAttrArray: TAttributeArray; AResourceInstance: TObject;
  AMethod: TRttiMethod): TValue;
var
  LAttr: TCustomAttribute;
  LParamName, LParamValue: string;
  LParamIndex: Integer;
  LParamClassType: TClass;
  LContextValue: TValue;
begin
  if Length(AAttrArray) > 1 then
    raise EMARSServerException.Create('Only 1 attribute per param permitted', Self.ClassName);

  LParamName := '';
  LParamValue := '';
  LAttr := AAttrArray[0];

  // context injection
  if (LAttr is ContextAttribute) and (AParam.ParamType.IsInstance) then
  begin
    LParamClassType := TRttiInstanceType(AParam.ParamType).MetaclassType;
    if ContextInjectionByType(LParamClassType, LContextValue) then
      Result := LContextValue;
  end
  else // http values injection
  begin
    if LAttr is PathParamAttribute then
    begin
      LParamName := (LAttr as PathParamAttribute).Value;
      if LParamName = '' then
        LParamName := AParam.Name;

      LParamIndex := ParamNameToParamIndex(AResourceInstance, LParamName, AMethod);
      LParamValue := URL.PathTokens[LParamIndex];
    end
    else
    if LAttr is QueryParamAttribute then
    begin
      LParamName := (LAttr as QueryParamAttribute).Value;
      if LParamName = '' then
        LParamName := AParam.Name;

      // Prendere il valore (come stringa) dalla lista QueryFields
      LParamValue := Request.QueryFields.Values[LParamName];
    end
    else
    if LAttr is FormParamAttribute then
    begin
      LParamName := (LAttr as FormParamAttribute).Value;
      if LParamName = '' then
        LParamName := AParam.Name;

      // Prendere il valore (come stringa) dalla lista ContentFields
      LParamValue := Request.ContentFields.Values[LParamName];
    end
    else
    if LAttr is CookieParamAttribute then
    begin
      LParamName := (LAttr as CookieParamAttribute).Value;
      if LParamName = '' then
        LParamName := AParam.Name;

      // Prendere il valore (come stringa) dalla lista CookieFields
      LParamValue := Request.CookieFields.Values[LParamName];
    end
    else
    if LAttr is HeaderParamAttribute then
    begin
      LParamName := (LAttr as HeaderParamAttribute).Value;
      if LParamName = '' then
        LParamName := AParam.Name;

      // Prendere il valore (come stringa) dagli Header HTTP
      LParamValue := string(Request.GetFieldByName(AnsiString(LParamName)));
    end
    else
    if LAttr is BodyParamAttribute then
    begin
      LParamName := AParam.Name;
      LParamValue := Request.Content;
    end;

    case AParam.ParamType.TypeKind of
      tkInt64,
      tkInteger: Result := TValue.From(StrToInt(LParamValue));
      tkFloat: Result := TValue.From<Double>(StrToFloat(LParamValue));

      tkChar: Result := TValue.From(AnsiChar(LParamValue[1]));
//      tkWChar: ;
//      tkEnumeration: ;
//      tkSet: ;
      tkClass: begin
          // TODO: better error handling in case of an invalid type cast
          // TODO: add a dynamic way to create the right class
          if MatchStr(AParam.ParamType.Name, ['TJSONObject']) then
          begin
            Result := TJSONObject.ParseJSONValue(LParamValue) as TJSONObject;
          end
          else if MatchStr(AParam.ParamType.Name, ['TJSONArray']) then
          begin
            Result := TJSONObject.ParseJSONValue(LParamValue) as TJSONArray;
          end
          else if MatchStr(AParam.ParamType.Name, ['TJSONValue']) then
          begin
            Result := TJSONObject.ParseJSONValue(LParamValue) as TJSONValue;
          end
          else
            raise EMARSServerException.Create(Format('Unsupported class [%s] for param [%s]', [AParam.ParamType.Name, LParamName]), Self.ClassName);
        end;
//      tkMethod: ;

      tkLString,
      tkUString,
      tkWString,
      tkString: Result := TValue.From(LParamValue);

      tkVariant: Result := TValue.From(LParamValue);

//      tkArray: ;
//      tkRecord: ;
//      tkInterface: ;
//      tkDynArray: ;
//      tkClassRef: ;
//      tkPointer: ;
//      tkProcedure: ;
      else
        raise EMARSServerException.Create(Format('Unsupported data type for param [%s]', [LParamName]), Self.ClassName);
    end;
  end;
end;

function TMARSApplication.FillNonAnnotatedParam(AParam: TRttiParameter): TValue;
var
  LClass: TClass;
begin
  // 1) Valid objects (TMARSRequest, )
  if AParam.ParamType.IsInstance then
  begin
    LClass := AParam.ParamType.AsInstance.MetaclassType;
    if LClass.InheritsFrom(TWebRequest) then
      Result := TValue.From(Request)
    else
      Result := TValue.From(nil);
      //Exception.Create('Only TMARSRequest object if the method is not annotated');
  end
  else
  begin
    // 2) parameter default value
    Result := TValue.Empty;
  end;
end;

procedure TMARSApplication.FillResourceMethodParameters(AInstance: TObject; AMethod: TRttiMethod; var AArgumentArray: TArgumentArray);
var
  LParam: TRttiParameter;
  LParamArray: TArray<TRttiParameter>;
  LAttrArray: TArray<TCustomAttribute>;

  LIndex: Integer;
begin
  try
    LParamArray := AMethod.GetParameters;

    // The method has no parameters so simply call as it is
    if Length(LParamArray) = 0 then
      Exit;

    SetLength(AArgumentArray, Length(LParamArray));

    for LIndex := Low(LParamArray) to High(LParamArray) do
    begin
      LParam := LParamArray[LIndex];

      LAttrArray := LParam.GetAttributes;

      if Length(LAttrArray) = 0 then
        AArgumentArray[LIndex] := FillNonAnnotatedParam(LParam)
      else
        AArgumentArray[LIndex] := FillAnnotatedParam(LParam, LAttrArray, AInstance, AMethod);
    end;

  except
    on E: Exception do
    begin
      raise EMARSWebApplicationException.Create(E, 400,
        [
          Pair.S('issuer', Self.ClassName),
          Pair.S('method', 'FillResourceMethodParameters')
        ]);
     end;
  end;
end;

procedure TMARSApplication.HandleRequest(ARequest: TWebRequest; AResponse:
    TWebResponse; const AURL: TMARSURL);
var
  LInfo: TMARSConstructorInfo;
  LMethod: TRttiMethod;
  LInstance: TObject;
  LWriter: IMessageBodyWriter;
  LMediaType: TMediaType;
begin
  if not FResourceRegistry.TryGetValue(URL.Resource, LInfo) then
    raise EMARSNotFoundException.Create(
      Format('Resource [%s] not found', [URL.Resource]),
      Self.ClassName, 'HandleRequest'
    );

  LMethod := FindMethodToInvoke(URL, LInfo);

  if not Assigned(LMethod) then
    raise EMARSNotFoundException.Create(
      Format('Resource''s method [%s] not found to handle resource [%s]', [GetEnumName(TypeInfo(TMethodType), Ord(ARequest.MethodType)), URL.Resource + URL.SubResources.ToString]),
      Self.ClassName, 'HandleRequest'
    );

  CheckAuthorization(LMethod, TMARSTokenList.Instance.GetToken(Request));

  LInstance := LInfo.ConstructorFunc();
  try
    TMARSMessageBodyRegistry.Instance.FindWriter(LMethod, string(Request.Accept),
      LWriter, LMediaType);

    ContextInjection(LInstance);
    try
      InvokeResourceMethod(LInstance, LMethod, LWriter, ARequest, LMediaType);
    finally
      LWriter := nil;
      LMediaType.Free;
    end;

  finally
    LInstance.Free;
  end;
end;

procedure TMARSApplication.InvokeResourceMethod(AInstance: TObject;
  AMethod: TRttiMethod; const AWriter: IMessageBodyWriter;
  ARequest: TWebRequest; AMediaType: TMediaType);
var
  LMethodResult: TValue;
  LArgument :TValue;
  LArgumentArray: TArgumentArray;
  LMARSResponse: TMARSResponse;
  LStream: TStringStream;
  LContentType: AnsiString;
begin
  // The returned object MUST be initially nil (needs to be consistent with the Free method)
  LMethodResult := nil;
  try
    LContentType := Response.ContentType;
    FillResourceMethodParameters(AInstance, AMethod, LArgumentArray);
    LMethodResult := AMethod.Invoke(AInstance, LArgumentArray);

    if LMethodResult.IsInstanceOf(TMARSResponse) then // Response Object
    begin
      LMARSResponse := TMARSResponse(LMethodResult.AsObject);
      LMARSResponse.CopyTo(Response);
    end
    else if Assigned(AWriter) then // MessageBodyWriters mechanism
    begin
      {
        If the ContentType has been already changed (i.e., using the Context DI mechanism),
        we should not override the new value.
        This means the application developer has more power than the MBW developer in order
        to determine the ContentType.
        
        Andrea Magni, 19/11/2015
      }
      if Response.ContentType = LContentType then
        Response.ContentType := AnsiString(AMediaType.ToString);

      LStream := TStringStream.Create();
      try
        AWriter.WriteTo(LMethodResult, AMethod.GetAttributes, AMediaType, Response.CustomHeaders, LStream);
        LStream.Position := 0;

        Response.Content := LStream.DataString;
      finally
        LStream.Free;
      end;
    end
    else // fallback (no MBW, no TMARSResponse)
    begin
      // handle result
      case LMethodResult.Kind of

        tkString, tkLString, tkUString, tkWString // string types
        , tkInteger, tkInt64, tkFloat, tkVariant: // Threated as string, nothing more
        begin
          Response.Content := LMethodResult.AsString;
          if (Response.ContentType = LContentType) then
            Response.ContentType := TMediaType.TEXT_PLAIN; // or check Produces of method!
          Response.StatusCode := 200;
        end;

        tkUnknown : ; // it's a procedure, not a function!

        //tkRecord: ;
        //tkInterface: ;
        //tkDynArray: ;
        else
          raise EMARSNotSupportedException.Create('Resource''s returned type not supported', Self.ClassName);
      end;
    end;
  finally
    // ResultIsReference is for compatibility only
    if (not AMethod.HasAttribute<SingletonAttribute>) and
       (not AMethod.HasAttribute<ResultIsReference>) then
      CollectGarbage(LMethodResult);
    for LArgument in LArgumentArray do
      CollectGarbage(LArgument);
  end;
end;

function TMARSApplication.ParamNameToParamIndex(AResourceInstance: TObject;
  const AParamName: string; AMethod: TRttiMethod): Integer;
var
  LParamIndex: Integer;
  LAttrib: TCustomAttribute;
  LSubResourcePath: string;
begin
  LParamIndex := -1;

  LSubResourcePath := '';
  for LAttrib in AMethod.GetAttributes do
  begin
    if LAttrib is PathAttribute then
    begin
      LSubResourcePath := PathAttribute(LAttrib).Value;
      Break;
    end;
  end;

  FRttiContext.GetType(AResourceInstance.ClassType).HasAttribute<PathAttribute>(
  procedure (AResourcePathAttrib: PathAttribute)
  var
    LResURL: TMARSURL;
    LPair: TPair<Integer, string>;
  begin
    LResURL := TMARSURL.CreateDummy([TMARSEngine(Engine).BasePath, BasePath, AResourcePathAttrib.Value, LSubResourcePath]);
    try
      LParamIndex := -1;
      for LPair in LResURL.PathParams do
      begin
        if SameText(AParamName, LPair.Value) then
        begin
          LParamIndex := LPair.Key;
          Break;
        end;
      end;
    finally
      LResURL.Free;
    end;
  end);

  Result := LParamIndex;
end;

end.
