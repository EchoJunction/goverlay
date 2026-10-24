program primitives_oracle;
{$mode objfpc}{$H+}{$codepage utf8}
uses Classes, SysUtils, BaseUnix, prismsettings, prismenv, prismdocument;
var DirectoryPath, Mode: string; Number: Integer;

procedure Require(OK: Boolean; const MessageText: string);
begin if not OK then raise Exception.Create(MessageText); end;

function ExpectedMap(Instance: Boolean): TPrismEnvMap;
begin
  Result := nil;
  if Instance then
  begin
    SetLength(Result, 1); Result[0].Key := 'MANGOHUD_CONFIGFILE';
    Result[0].Value := '/tmp/Synthetic 日本語/overlay.conf';
  end
  else
  begin
    SetLength(Result, 2); Result[0].Key := 'KEEP';
    Result[0].Value := 'global "quote" \ 日本語 😀' + #0#8#9#10#12#13#127;
    Result[1].Key := ''; Result[1].Value := 'empty key';
  end;
end;

procedure RunFixture(Instance: Boolean);
var M, ReadMap: TPrismEnvMap; S, Original, Name: RawByteString;
  D, P: TPrismDocument; DE: TPrismDocumentError; EE: TPrismEnvError;
  EditError: TPrismDocumentEditError; Edits: array[0..2] of TPrismManagedEdit;
  B: Boolean; BE: TPrismBoolError; I, Fd: Integer;
  FileStream: TFileStream; OutputStream: THandleStream;
begin
  if Instance then Name := 'instance.cfg' else Name := 'global.ini';
  M := ExpectedMap(Instance);
  if Mode = 'create' then
  begin
    if Instance then Original := '[Other]'#10'Unknown=keep'#10'[General]'#10+
      'ConfigVersion=1.3'#10'InstanceType=OneSix'
    else Original := '; synthetic global'#13#10'[General]'#13#10'ConfigVersion=1.3'#13#10+
      'Unknown=opaque'#13#10'[Other]'#13#10'Env=leave-this-section'#13#10;
    Require(IndexPrismDocument(Original, D, DE), 'Original synthetic document');
    Require(EncodePrismEnv(M, S, EE), 'Env encode');
    Edits[0].KeyName := 'Env'; Edits[0].RawScalar := S;
    Edits[1].KeyName := 'OverridePerformance'; Edits[1].RawScalar := EncodePrismBool(Instance);
    Edits[2].KeyName := 'EnableMangoHud'; Edits[2].RawScalar := EncodePrismBool(not Instance);
    Require(EditPrismDocument(D, Edits, P, EditError), 'Pure fixture edit');
    Require(D.Bytes = Original, 'Input changed');
    Fd := fpOpen(PChar(DirectoryPath + string(Name)), O_WRONLY or O_CREAT or O_EXCL or O_NOFOLLOW, &600);
    Require(Fd >= 0, 'Require new synthetic fixture output');
    try
      OutputStream := THandleStream.Create(Fd);
      try OutputStream.WriteBuffer(P.Bytes[1], Length(P.Bytes)); finally OutputStream.Free; end;
    finally fpClose(Fd); end;
  end
  else
  begin
    FileStream := TFileStream.Create(DirectoryPath + 'normalized-' + string(Name), fmOpenRead);
    try SetLength(S, FileStream.Size); if S <> '' then FileStream.ReadBuffer(S[1], Length(S));
    finally FileStream.Free; end;
    Require(IndexPrismDocument(S, D, DE), 'Qt-normalized strict document');
    Require(DecodePrismBool(D.Managed[pmkOverridePerformance].RawScalar, B, BE), 'Normalized bool');
    Require(B = Instance, 'Normalized override bool parity');
    Require(DecodePrismBool(D.Managed[pmkEnableMangoHud].RawScalar, B, BE), 'Normalized enable bool');
    Require(B = not Instance, 'Normalized enable bool parity');
    Require(DecodePrismEnv(D.Managed[pmkEnv].RawScalar, ReadMap, EE), 'Normalized Env');
    Require(Length(M) = Length(ReadMap), 'Normalized Env count');
    for I := 0 to High(M) do
      Require((M[I].Key = ReadMap[I].Key) and (M[I].Value = ReadMap[I].Value), 'Normalized ordered Env parity');
  end;
end;

begin
  try
    Require(ParamCount = 2, 'Expected create/verify and synthetic temporary directory');
    Mode := ParamStr(1); DirectoryPath := IncludeTrailingPathDelimiter(ParamStr(2));
    Require((Mode = 'create') or (Mode = 'verify'), 'Expected create/verify');
    Require(DirectoryExists(DirectoryPath), 'Synthetic directory missing');
    for Number := 0 to 1 do RunFixture(Number = 1);
    WriteLn('PASS: 2 synthetic global/instance ', Mode, ' probes');
  except on E: Exception do begin WriteLn(StdErr, 'FAIL: ', E.Message); Halt(1); end; end;
end.
