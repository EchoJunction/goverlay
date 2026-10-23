unit prismdocument;

{$mode objfpc}{$H+}

interface

const
  PrismDocumentMaxBytes = 1024 * 1024;
  PrismDocumentMaxLines = 32768;

type
  TPrismManagedKey = (pmkConfigVersion, pmkOverridePerformance,
    pmkEnableMangoHud, pmkUseDiscreteGpu, pmkUseZink, pmkEnableFeralGamemode,
    pmkOverrideEnv, pmkEnv, pmkOverrideCommands, pmkOverrideLaunchCmd,
    pmkWrapperCommand);
  TPrismDocumentError = (pdeNone, pdeLimitExceeded, pdeMalformed,
    pdeUnsupportedEncoding, pdeDuplicate, pdeUnsupportedVersion);
  { All offsets are 1-based byte offsets into Bytes. Length is a byte count.
    LineSpan includes its LF/CRLF terminator, if present. ValueSpan excludes
    surrounding ASCII space/tab only; quoted interior whitespace is retained.
    Absent entries have zero spans and empty strings. Present empty entries
    have a valid ValueSpan.Offset and Length=0. }
  TPrismByteSpan = record
    Offset, Length: SizeInt;
  end;
  TPrismIndexedValue = record
    Present: Boolean;
    LineSpan, ValueSpan: TPrismByteSpan;
    RawScalar: RawByteString;
    DecodedScalar: UTF8String;
  end;
  TPrismDocument = record
    Bytes: RawByteString;
    Managed: array[TPrismManagedKey] of TPrismIndexedValue;
  end;

const
  PrismManagedKeyNames: array[TPrismManagedKey] of ShortString = (
    'ConfigVersion', 'OverridePerformance', 'EnableMangoHud', 'UseDiscreteGpu',
    'UseZink', 'EnableFeralGamemode', 'OverrideEnv', 'Env', 'OverrideCommands',
    'OverrideLaunchCmd', 'WrapperCommand');

{ Pure, read-only supported Qt INI subset, for either global or instance bytes.
  Requires exactly one canonical [General] and ConfigVersion scalar 1.3.
  Section/key names support ASCII letters/digits/underscore/dot/hyphen only;
  General case aliases and whitespace inside headers are refused. Unknown
  values (including lists/QVariant) remain opaque, with quote/continuation
  boundary checks only. No BOM, root assignments, encoded names, multiline
  values, hash-prefixed lines, inline managed semicolon comments or quote
  fragments. Only semicolon starts a whole-line comment. Managed values
  use DecodePrismScalar; JSON/bool/override semantics are deliberately absent.
  Errors are fixed enums; failure clears the entire output. No filesystem use. }
function IndexPrismDocument(const Bytes: RawByteString;
  out Document: TPrismDocument; out Error: TPrismDocumentError): Boolean;

implementation

uses SysUtils, prismsettings;

function ValidBytes(const S: RawByteString): Boolean;
var I, J, B, N, CP, Minimum: SizeInt;
begin
  Result := False; I := 1;
  while I <= Length(S) do
  begin
    B := Ord(S[I]);
    if B < $80 then
    begin
      if ((B < 32) and not (B in [9, 10, 13])) or (B = 127) then Exit;
      Inc(I); Continue;
    end;
    case B of
      $C2..$DF: begin N := 1; CP := B and $1F; Minimum := $80; end;
      $E0..$EF: begin N := 2; CP := B and $0F; Minimum := $800; end;
      $F0..$F4: begin N := 3; CP := B and $07; Minimum := $10000; end;
      else Exit;
    end;
    if I + N > Length(S) then Exit;
    for J := 1 to N do
    begin
      B := Ord(S[I + J]);
      if (B < $80) or (B > $BF) then Exit;
      CP := CP * 64 + (B and $3F);
    end;
    if (CP < Minimum) or (CP > $10FFFF) or
      ((CP >= $D800) and (CP <= $DFFF)) then Exit;
    Inc(I, N + 1);
  end;
  Result := True;
end;

function CanonicalName(const S: RawByteString): Boolean;
var I: SizeInt;
begin
  Result := False;
  if S = '' then Exit;
  for I := 1 to Length(S) do
    if not (S[I] in ['a'..'z', 'A'..'Z', '0'..'9', '_', '.', '-']) then Exit;
  Result := True;
end;

function SafeValueBoundary(const S: RawByteString): Boolean;
var I: SizeInt; Quoted: Boolean;
begin
  I := 1; Quoted := False;
  while I <= Length(S) do
  begin
    case S[I] of
      '\': begin Inc(I); if I > Length(S) then Exit(False); end;
      '"': Quoted := not Quoted;
      ';': if not Quoted then Exit(True);
    end;
    Inc(I);
  end;
  Result := not Quoted;
end;

function IndexPrismDocument(const Bytes: RawByteString;
  out Document: TPrismDocument; out Error: TPrismDocumentError): Boolean;
var
  Candidate: TPrismDocument;
  Position, Start, Finish, NextLine, Left, Right, EqualAt, KeyEnd,
    ValueStart, ValueEnd, LineCount: SizeInt;
  Name, Scalar: RawByteString;
  SeenSection, InGeneral, SeenGeneral: Boolean;
  Key, FoundKey: TPrismManagedKey;
  Found: Boolean;
  Decoded: UTF8String;
  ScalarError: TPrismScalarError;
begin
  Document := Default(TPrismDocument); Candidate := Default(TPrismDocument);
  Result := False; Error := pdeMalformed;
  if Length(Bytes) > PrismDocumentMaxBytes then
  begin Error := pdeLimitExceeded; Exit; end;
  if not ValidBytes(Bytes) then Exit;
  if Copy(Bytes, 1, 3) = #$EF#$BB#$BF then
  begin Error := pdeUnsupportedEncoding; Exit; end;
  SeenSection := False; SeenGeneral := False; InGeneral := False;
  Position := 1; LineCount := 0;
  while Position <= Length(Bytes) do
  begin
    Inc(LineCount);
    if LineCount > PrismDocumentMaxLines then
    begin Error := pdeLimitExceeded; Exit; end;
    Start := Position;
    while (Position <= Length(Bytes)) and not (Bytes[Position] in [#10, #13]) do
      Inc(Position);
    Finish := Position - 1;
    if Position <= Length(Bytes) then
    begin
      if Bytes[Position] = #13 then
      begin
        Inc(Position);
        if (Position > Length(Bytes)) or (Bytes[Position] <> #10) then Exit;
      end;
      Inc(Position);
    end;
    NextLine := Position;
    Left := Start; Right := Finish;
    while (Left <= Right) and (Bytes[Left] in [' ', #9]) do Inc(Left);
    while (Right >= Left) and (Bytes[Right] in [' ', #9]) do Dec(Right);
    if (Left > Right) or (Bytes[Left] = ';') then Continue;
    if Bytes[Left] = '[' then
    begin
      if Bytes[Right] <> ']' then Exit;
      Name := Copy(Bytes, Left + 1, Right - Left - 1);
      if not CanonicalName(Name) then
      begin Error := pdeUnsupportedEncoding; Exit; end;
      if (CompareText(string(Name), 'General') = 0) and (Name <> 'General') then
      begin Error := pdeUnsupportedEncoding; Exit; end;
      SeenSection := True; InGeneral := Name = 'General';
      if InGeneral then
      begin
        if SeenGeneral then begin Error := pdeDuplicate; Exit; end;
        SeenGeneral := True;
      end;
      Continue;
    end;
    if not SeenSection then Exit;
    EqualAt := Left;
    while (EqualAt <= Right) and (Bytes[EqualAt] <> '=') do Inc(EqualAt);
    if EqualAt > Right then Exit;
    KeyEnd := EqualAt - 1;
    while (KeyEnd >= Left) and (Bytes[KeyEnd] in [' ', #9]) do Dec(KeyEnd);
    Name := Copy(Bytes, Left, KeyEnd - Left + 1);
    if not CanonicalName(Name) then
    begin Error := pdeUnsupportedEncoding; Exit; end;
    ValueStart := EqualAt + 1; ValueEnd := Right;
    while (ValueStart <= ValueEnd) and (Bytes[ValueStart] in [' ', #9]) do Inc(ValueStart);
    Scalar := Copy(Bytes, ValueStart, ValueEnd - ValueStart + 1);
    if not SafeValueBoundary(Scalar) then Exit;
    Found := False; FoundKey := pmkConfigVersion;
    if InGeneral then
      for Key := Low(TPrismManagedKey) to High(TPrismManagedKey) do
        if Name = PrismManagedKeyNames[Key] then
        begin Found := True; FoundKey := Key; Break; end;
    if not Found then Continue;
    if Candidate.Managed[FoundKey].Present then
    begin Error := pdeDuplicate; Exit; end;
    if not DecodePrismScalar(Scalar, Decoded, ScalarError) then
    begin
      if ScalarError = pseLimitExceeded then Error := pdeLimitExceeded
      else if ScalarError = pseUnsupportedEncoding then Error := pdeUnsupportedEncoding;
      Exit;
    end;
    with Candidate.Managed[FoundKey] do
    begin
      Present := True;
      LineSpan.Offset := Start; LineSpan.Length := NextLine - Start;
      ValueSpan.Offset := ValueStart; ValueSpan.Length := Length(Scalar);
      RawScalar := Scalar; DecodedScalar := Decoded;
    end;
  end;
  if not SeenGeneral or not Candidate.Managed[pmkConfigVersion].Present or
    (Candidate.Managed[pmkConfigVersion].DecodedScalar <> '1.3') then
  begin Error := pdeUnsupportedVersion; Exit; end;
  Candidate.Bytes := Bytes; Document := Candidate;
  Error := pdeNone; Result := True;
end;

end.
