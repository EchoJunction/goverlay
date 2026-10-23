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
    peeUnsupportedScalar, peeMalformedJSON, peeDuplicateKey, peeNonStringValue);

{ Pure, bounded Qt scalar -> complete JSON object of strings. Keys are compared
  exactly after JSON escape decoding, case sensitively, without normalization.
  Values (including JSON-escaped controls) are preserved; environment-variable
  policy belongs to the caller. Entry order is preserved. No I/O, diagnostics
  containing input data, or partial output on failure. Scalar bounds also cap
  the JSON document and total decoded string storage. }
function DecodePrismEnv(const Scalar: RawByteString; out Entries: TPrismEnvMap;
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

end.
