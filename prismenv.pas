unit prismenv;

{$mode objfpc}{$H+}

interface

uses prismsettings;

const
  PrismEnvMaxEntries = 1024;

type
  TPrismEnvEntry = record
    Key, Value: UTF8String;
  end;
  TPrismEnvMap = array of TPrismEnvEntry;
  TPrismEnvError = (peeNone, peeLimitExceeded, peeMalformedScalar,
    peeUnsupportedScalar, peeMalformedJSON, peeDuplicateKey, peeNonStringValue, peeInvalidUTF8);

{ Pure, bounded Qt scalar -> complete JSON object of strings. Keys are compared
  exactly after JSON escape decoding, case sensitively, without normalization.
  Values (including JSON-escaped controls) are preserved; environment-variable
  policy belongs to the caller. Entry order is preserved. No I/O, diagnostics
  containing input data, or partial output on failure. Scalar bounds also cap
  the JSON document and total decoded string storage. }
function DecodePrismEnv(const Scalar: RawByteString; out Entries: TPrismEnvMap;
  out Error: TPrismEnvError): Boolean;

{ Ordered map -> bounded compact JSON -> always whole-quoted Qt scalar.
  Duplicate logical keys and invalid UTF-8 fail closed; JSON-escaped controls
  including NUL remain data. No Unicode normalization or environment policy. }
function EncodePrismEnv(const Entries: TPrismEnvMap; out Scalar: RawByteString;
  out Error: TPrismEnvError): Boolean;

implementation

function DecodePrismEnv(const Scalar: RawByteString; out Entries: TPrismEnvMap;
  out Error: TPrismEnvError): Boolean;
var
  Json: UTF8String;
  ScalarError: TPrismScalarError;
  Parsed: TPrismEnvMap;
  I, Count, J: SizeInt;
  Key, Value: UTF8String;

  procedure Whitespace;
  begin
    while (I <= Length(Json)) and (Json[I] in [#9, #10, #13, ' ']) do Inc(I);
  end;

  function Take(C: AnsiChar): Boolean;
  begin
    Result := (I <= Length(Json)) and (Json[I] = C);
    if Result then Inc(I);
  end;

  function HexUnit(out N: Cardinal): Boolean;
  var K, H: Integer;
  begin
    Result := False; N := 0;
    if I + 3 > Length(Json) then Exit;
    for K := 1 to 4 do
    begin
      case Json[I] of
        '0'..'9': H := Ord(Json[I]) - Ord('0');
        'a'..'f': H := Ord(Json[I]) - Ord('a') + 10;
        'A'..'F': H := Ord(Json[I]) - Ord('A') + 10;
        else Exit;
      end;
      N := N * 16 + Cardinal(H); Inc(I);
    end;
    Result := True;
  end;

  function ReadString(out S: UTF8String): Boolean;
  var Buffer: UTF8String; Used: SizeInt; C: AnsiChar; N, Low: Cardinal;

    procedure Add(B: AnsiChar);
    begin
      Inc(Used); Buffer[Used] := B;
    end;

    procedure AddCodePoint(P: Cardinal);
    begin
      if P < $80 then Add(AnsiChar(P))
      else if P < $800 then
      begin Add(AnsiChar($C0 or (P shr 6))); Add(AnsiChar($80 or (P and $3F))); end
      else if P < $10000 then
      begin
        Add(AnsiChar($E0 or (P shr 12)));
        Add(AnsiChar($80 or ((P shr 6) and $3F)));
        Add(AnsiChar($80 or (P and $3F)));
      end
      else
      begin
        Add(AnsiChar($F0 or (P shr 18)));
        Add(AnsiChar($80 or ((P shr 12) and $3F)));
        Add(AnsiChar($80 or ((P shr 6) and $3F)));
        Add(AnsiChar($80 or (P and $3F)));
      end;
    end;

  begin
    Result := False; S := '';
    if not Take('"') then Exit;
    { UTF-8 output cannot exceed the remaining JSON source byte count. }
    SetLength(Buffer, Length(Json) - I + 1); Used := 0;
    while I <= Length(Json) do
    begin
      C := Json[I]; Inc(I);
      if C = '"' then
      begin SetLength(Buffer, Used); S := Buffer; Exit(True); end;
      if Ord(C) < 32 then Exit;
      if C <> '\' then begin Add(C); Continue; end;
      if I > Length(Json) then Exit;
      C := Json[I]; Inc(I);
      case C of
        '"', '\', '/': Add(C);
        'b': Add(#8);
        'f': Add(#12);
        'n': Add(#10);
        'r': Add(#13);
        't': Add(#9);
        'u': begin
          if not HexUnit(N) then Exit;
          if (N >= $D800) and (N <= $DBFF) then
          begin
            if not Take('\') or not Take('u') or not HexUnit(Low) then Exit;
            if (Low < $DC00) or (Low > $DFFF) then Exit;
            N := $10000 + (N - $D800) * $400 + Low - $DC00;
          end
          else if (N >= $DC00) and (N <= $DFFF) then Exit;
          AddCodePoint(N);
        end;
        else Exit;
      end;
    end;
  end;

begin
  Result := False; Entries := nil; Error := peeMalformedJSON;
  if not DecodePrismScalar(Scalar, Json, ScalarError) then
  begin
    case ScalarError of
      pseLimitExceeded: Error := peeLimitExceeded;
      pseUnsupportedEncoding: Error := peeUnsupportedScalar;
      else Error := peeMalformedScalar;
    end;
    Exit;
  end;
  I := 1; Count := 0; Whitespace;
  if not Take('{') then Exit;
  Whitespace;
  if not Take('}') then
  begin
    SetLength(Parsed, PrismEnvMaxEntries);
    repeat
      if Count >= PrismEnvMaxEntries then
      begin Error := peeLimitExceeded; Exit; end;
      if not ReadString(Key) then Exit;
      for J := 0 to Count - 1 do
        if Parsed[J].Key = Key then
        begin Error := peeDuplicateKey; Exit; end;
      Whitespace;
      if not Take(':') then Exit;
      Whitespace;
      if (I <= Length(Json)) and (Json[I] <> '"') then
      begin Error := peeNonStringValue; Exit; end;
      if not ReadString(Value) then Exit;
      Parsed[Count].Key := Key; Parsed[Count].Value := Value; Inc(Count);
      Whitespace;
      if Take('}') then Break;
      if not Take(',') then Exit;
      Whitespace;
    until False;
  end;
  Whitespace;
  if I <= Length(Json) then Exit;
  SetLength(Parsed, Count); Entries := Parsed;
  Error := peeNone; Result := True;
end;

function ValidEnvUTF8(const S: UTF8String): Boolean;
var I, J, B, N, CP, Minimum: SizeInt;
begin
  Result := False; I := 1;
  while I <= Length(S) do
  begin
    B := Ord(S[I]);
    if B < $80 then begin Inc(I); Continue; end;
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

function EncodePrismEnv(const Entries: TPrismEnvMap; out Scalar: RawByteString;
  out Error: TPrismEnvError): Boolean;
const Hex: string = '0123456789abcdef';
var Json, Quoted: RawByteString; Used, I, J, Total, QUsed: SizeInt;

  function Add(C: AnsiChar): Boolean;
  begin
    Result := Used < PrismScalarMaxOutputBytes;
    if Result then begin Inc(Used); Json[Used] := C; end;
  end;

  function AddText(const S: RawByteString): Boolean;
  var K: SizeInt;
  begin
    Result := False;
    for K := 1 to Length(S) do if not Add(S[K]) then Exit;
    Result := True;
  end;

  function AddString(const S: UTF8String): Boolean;
  var K, B: SizeInt;
  begin
    Result := False;
    if not Add('"') then Exit;
    for K := 1 to Length(S) do
    begin
      B := Ord(S[K]);
      case S[K] of
        '"': if not AddText('\"') then Exit;
        '\': if not AddText('\\') then Exit;
        #8: if not AddText('\b') then Exit;
        #9: if not AddText('\t') then Exit;
        #10: if not AddText('\n') then Exit;
        #12: if not AddText('\f') then Exit;
        #13: if not AddText('\r') then Exit;
        else
          if (B < 32) or (B = 127) then
          begin
            if not AddText('\u00') or not Add(Hex[B div 16 + 1]) or
              not Add(Hex[B mod 16 + 1]) then Exit;
          end
          else if not Add(S[K]) then Exit;
      end;
    end;
    Result := Add('"');
  end;

begin
  Result := False; Scalar := ''; Error := peeLimitExceeded;
  if Length(Entries) > PrismEnvMaxEntries then Exit;
  Total := 0;
  for I := 0 to High(Entries) do
  begin
    if (Length(Entries[I].Key) > PrismScalarMaxOutputBytes - Total) then Exit;
    Inc(Total, Length(Entries[I].Key));
    if (Length(Entries[I].Value) > PrismScalarMaxOutputBytes - Total) then Exit;
    Inc(Total, Length(Entries[I].Value));
  end;
  for I := 0 to High(Entries) do
  begin
    if not ValidEnvUTF8(Entries[I].Key) or not ValidEnvUTF8(Entries[I].Value) then
    begin Error := peeInvalidUTF8; Exit; end;
    for J := 0 to I - 1 do
      if Entries[I].Key = Entries[J].Key then
      begin Error := peeDuplicateKey; Exit; end;
  end;
  SetLength(Json, PrismScalarMaxOutputBytes); Used := 0;
  if not Add('{') then Exit;
  for I := 0 to High(Entries) do
  begin
    if (I > 0) and not Add(',') then Exit;
    if not AddString(Entries[I].Key) or not Add(':') or
      not AddString(Entries[I].Value) then Exit;
  end;
  if not Add('}') then Exit;
  { JSON has no raw scalar controls. Qt adds one escape byte before each JSON
    quote/backslash; this upper bound stays inside the scalar input bound. }
  if Used > (PrismScalarMaxInputBytes - 2) div 2 then Exit;
  SetLength(Quoted, Used * 2 + 2); Quoted[1] := '"'; QUsed := 1;
  for I := 1 to Used do
  begin
    if Json[I] in ['"', '\'] then
    begin Inc(QUsed); Quoted[QUsed] := '\'; end;
    Inc(QUsed); Quoted[QUsed] := Json[I];
  end;
  Inc(QUsed); Quoted[QUsed] := '"'; SetLength(Quoted, QUsed);
  Scalar := Quoted; Error := peeNone; Result := True;
end;

end.
