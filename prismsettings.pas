unit prismsettings;

{$mode objfpc}{$H+}

interface

const
  PrismScalarMaxInputBytes = 256 * 1024;
  PrismScalarMaxOutputBytes = 64 * 1024;

type
  TPrismScalarError = (pseNone, pseLimitExceeded, pseMalformed,
    pseUnsupportedEncoding);
  TPrismBoolError = (pbeNone, pbeLimitExceeded, pbeMalformedScalar,
    pbeUnsupportedEncoding, pbeUnsupportedValue);

{ Pure, deliberately strict Qt IniFormat QString subset. Input is one isolated
  scalar, without INI whitespace, comments or line continuations. Supports a
  whole quoted value or an unquoted scalar, UTF-8 and Qt UTF-16 hex escapes.
  Rejects lists, QVariant types, quote fragments and unsupported escapes.
  Env JSON remains opaque. Errors contain no input data; Value is empty on any
  failure. Neither input nor application/filesystem state is modified. }
function DecodePrismScalar(const Scalar: RawByteString; out Value: UTF8String;
  out Error: TPrismScalarError): Boolean;

{ Absence/defaults belong to the caller. Only decoded canonical true/false are
  supported; present empty/numeric/case aliases are unsupported. Failure clears
  Value. Encoding always returns the canonical unquoted scalar. }
function DecodePrismBool(const Scalar: RawByteString; out Value: Boolean;
  out Error: TPrismBoolError): Boolean;
function EncodePrismBool(Value: Boolean): RawByteString;

implementation

function HexDigit(C: AnsiChar): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
    else Result := -1;
  end;
end;

function ValidUTF8(const S: RawByteString): Boolean;
var I, J, Count, B, CodePoint, Minimum: SizeInt;
begin
  Result := False; I := 1;
  while I <= Length(S) do
  begin
    B := Ord(S[I]);
    if B = 0 then Exit;
    if B < $80 then begin Inc(I); Continue; end;
    case B of
      $C2..$DF: begin Count := 1; CodePoint := B and $1F; Minimum := $80; end;
      $E0..$EF: begin Count := 2; CodePoint := B and $0F; Minimum := $800; end;
      $F0..$F4: begin Count := 3; CodePoint := B and $07; Minimum := $10000; end;
      else Exit;
    end;
    if I + Count > Length(S) then Exit;
    for J := 1 to Count do
    begin
      B := Ord(S[I + J]);
      if (B < $80) or (B > $BF) then Exit;
      CodePoint := CodePoint * 64 + (B and $3F);
    end;
    if (CodePoint < Minimum) or (CodePoint > $10FFFF) or
       ((CodePoint >= $D800) and (CodePoint <= $DFFF)) then Exit;
    Inc(I, Count + 1);
  end;
  Result := True;
end;

function DecodePrismScalar(const Scalar: RawByteString; out Value: UTF8String;
  out Error: TPrismScalarError): Boolean;
var
  I, Last, Used, N, LowUnit: SizeInt;
  Quoted: Boolean;
  C: AnsiChar;
  Buffer: RawByteString;

  function AppendByte(B: AnsiChar): Boolean;
  begin
    Result := False;
    if Used >= PrismScalarMaxOutputBytes then
    begin Error := pseLimitExceeded; Exit; end;
    Inc(Used); Buffer[Used] := B; Result := True;
  end;

  function ReadHexUnit(out CodeUnit: SizeInt): Boolean;
  var Digits, H: Integer;
  begin
    CodeUnit := 0; Digits := 0;
    while I <= Last do
    begin
      H := HexDigit(Scalar[I]);
      if H < 0 then Break;
      Inc(Digits);
      if Digits > 4 then Exit(False);
      CodeUnit := CodeUnit * 16 + H; Inc(I);
    end;
    Result := Digits > 0;
  end;

  function AppendCodePoint(CodePoint: SizeInt): Boolean;
  begin
    Result := False;
    if CodePoint = 0 then Exit;
    if CodePoint < $80 then Result := AppendByte(AnsiChar(CodePoint))
    else if CodePoint < $800 then
      Result := AppendByte(AnsiChar($C0 or (CodePoint shr 6))) and
        AppendByte(AnsiChar($80 or (CodePoint and $3F)))
    else if CodePoint < $10000 then
      Result := AppendByte(AnsiChar($E0 or (CodePoint shr 12))) and
        AppendByte(AnsiChar($80 or ((CodePoint shr 6) and $3F))) and
        AppendByte(AnsiChar($80 or (CodePoint and $3F)))
    else
      Result := AppendByte(AnsiChar($F0 or (CodePoint shr 18))) and
        AppendByte(AnsiChar($80 or ((CodePoint shr 12) and $3F))) and
        AppendByte(AnsiChar($80 or ((CodePoint shr 6) and $3F))) and
        AppendByte(AnsiChar($80 or (CodePoint and $3F)));
  end;

begin
  Result := False; Value := ''; Error := pseMalformed;
  if Length(Scalar) > PrismScalarMaxInputBytes then
  begin Error := pseLimitExceeded; Exit; end;
  if not ValidUTF8(Scalar) then Exit;
  I := 1; Last := Length(Scalar); Used := 0;
  Quoted := (Last > 0) and (Scalar[1] = '"');
  if Quoted then
  begin
    if (Last < 2) or (Scalar[Last] <> '"') then Exit;
    Inc(I); Dec(Last);
  end
  else if (Last > 0) and ((Scalar[1] = ' ') or (Scalar[Last] = ' ')) then Exit;
  SetLength(Buffer, PrismScalarMaxOutputBytes);
  while I <= Last do
  begin
    C := Scalar[I]; Inc(I);
    if (Ord(C) < 32) or (C = #127) or (C = '"') then Exit;
    if not Quoted and (C in [',', ';']) then
    begin Error := pseUnsupportedEncoding; Exit; end;
    if C <> '\' then
    begin if not AppendByte(C) then Exit; Continue; end;
    if I > Last then Exit;
    C := Scalar[I]; Inc(I);
    case C of
      'a': C := #7;
      'b': C := #8;
      'f': C := #12;
      'n': C := #10;
      'r': C := #13;
      't': C := #9;
      'v': C := #11;
      '"', '\', '''', '?': ;
      'x': begin
        if not ReadHexUnit(N) then Exit;
        if (N >= $D800) and (N <= $DBFF) then
        begin
          if (I + 1 > Last) or (Scalar[I] <> '\') or
             (Scalar[I + 1] <> 'x') then Exit;
          Inc(I, 2);
          if not ReadHexUnit(LowUnit) or (LowUnit < $DC00) or
             (LowUnit > $DFFF) then Exit;
          N := $10000 + (N - $D800) * $400 + LowUnit - $DC00;
        end
        else if (N >= $DC00) and (N <= $DFFF) then Exit;
        if not AppendCodePoint(N) then Exit;
        Continue;
      end;
      else begin Error := pseUnsupportedEncoding; Exit; end;
    end;
    if not AppendByte(C) then Exit;
  end;
  SetLength(Buffer, Used);
  if not ValidUTF8(Buffer) then Exit;
  if (Used > 0) and (Buffer[1] = '@') then
  begin
    if (Used < 2) or (Buffer[2] <> '@') then
    begin Error := pseUnsupportedEncoding; Exit; end;
    Delete(Buffer, 1, 1);
  end;
  Value := UTF8String(Buffer);
  Error := pseNone; Result := True;
end;

function DecodePrismBool(const Scalar: RawByteString; out Value: Boolean;
  out Error: TPrismBoolError): Boolean;
var Text: UTF8String; ScalarError: TPrismScalarError;
begin
  Result := False; Value := False; Error := pbeUnsupportedValue;
  if not DecodePrismScalar(Scalar, Text, ScalarError) then
  begin
    case ScalarError of
      pseLimitExceeded: Error := pbeLimitExceeded;
      pseUnsupportedEncoding: Error := pbeUnsupportedEncoding;
      else Error := pbeMalformedScalar;
    end;
    Exit;
  end;
  if (Text <> 'true') and (Text <> 'false') then Exit;
  Value := Text = 'true'; Error := pbeNone; Result := True;
end;

function EncodePrismBool(Value: Boolean): RawByteString;
begin
  if Value then Result := 'true' else Result := 'false';
end;

end.
