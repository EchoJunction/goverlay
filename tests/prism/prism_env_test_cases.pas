unit prism_env_test_cases;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, SysUtils, fpcunit, testregistry, prismsettings, prismenv;

type
  TPrismEnvTests = class(TTestCase)
  private
    function Scalar(const Json: RawByteString): RawByteString;
    function Decode(const Json: RawByteString): TPrismEnvMap;
    procedure Refuses(const Json: RawByteString; Expected: TPrismEnvError);
    function Fixture(const Name: string): TPrismEnvMap;
  published
    procedure QtGeneratedForms;
    procedure EmptyAndWhitespace;
    procedure ExactStringsAndOrder;
    procedure UnicodeAndControls;
    procedure DuplicateDecodedKeys;
    procedure OnlyObjectAndStrings;
    procedure CompleteDocument;
    procedure MalformedStrings;
    procedure ScalarFailures;
    procedure Bounds;
  end;

implementation

function TPrismEnvTests.Scalar(const Json: RawByteString): RawByteString;
var I: SizeInt;
begin
  Result := '"';
  for I := 1 to Length(Json) do
    case Json[I] of
      '"', '\': Result := Result + '\' + Json[I];
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      else Result := Result + Json[I];
    end;
  Result := Result + '"';
end;

function TPrismEnvTests.Decode(const Json: RawByteString): TPrismEnvMap;
var E: TPrismEnvError; Raw, Before: RawByteString;
begin
  Raw := Scalar(Json); Before := Raw;
  AssertTrue('JSON string map decodes', DecodePrismEnv(Raw, Result, E));
  AssertEquals('Success reason', Ord(peeNone), Ord(E));
  AssertEquals('Input unchanged', Before, Raw);
end;

procedure TPrismEnvTests.Refuses(const Json: RawByteString;
  Expected: TPrismEnvError);
var E: TPrismEnvError; Entries: TPrismEnvMap; Raw, Before: RawByteString;
begin
  Entries := Decode('{"previous":"output"}'); Raw := Scalar(Json); Before := Raw;
  AssertFalse('JSON fails closed', DecodePrismEnv(Raw, Entries, E));
  AssertEquals('Fixed sanitized error', Ord(Expected), Ord(E));
  AssertEquals('No partial output', 0, Length(Entries));
  AssertEquals('Input unchanged', Before, Raw);
end;

function TPrismEnvTests.Fixture(const Name: string): TPrismEnvMap;
var Lines: TStringList; I: Integer; E: TPrismEnvError;
begin
  Result := nil; Lines := TStringList.Create;
  try
    Lines.LoadFromFile('tests/prism/fixtures/' + Name);
    for I := 0 to Lines.Count - 1 do
      if Copy(Lines[I], 1, 4) = 'Env=' then
      begin
        AssertTrue('Synthetic Qt Env parses', DecodePrismEnv(Copy(Lines[I], 5, MaxInt), Result, E));
        Exit;
      end;
    Fail('Missing synthetic Env');
  finally Lines.Free; end;
end;

procedure TPrismEnvTests.QtGeneratedForms;
var M: TPrismEnvMap;
begin
  M := Fixture('scalar-quoted.ini');
  AssertEquals(2, Length(M));
  AssertEquals('KEEP', string(M[0].Key));
  AssertEquals('quote" slash\ newline' + #10 + ' tab' + #9, string(M[0].Value));
  AssertEquals('MANGOHUD_CONFIGFILE', string(M[1].Key));
  AssertEquals('/tmp/Prism test/日本語,=#;\path/overlay.conf', string(M[1].Value));
  M := Fixture('scalar-unquoted.ini');
  AssertEquals(1, Length(M));
  AssertEquals('MANGOHUD_CONFIGFILE', string(M[0].Key));
  AssertEquals('/tmp/Synthetic 日本語/overlay.conf', string(M[0].Value));
end;

procedure TPrismEnvTests.EmptyAndWhitespace;
var M: TPrismEnvMap;
begin
  M := Decode('{}'); AssertEquals(0, Length(M));
  M := Decode(#9#10#13' { '#10' } '#9); AssertEquals(0, Length(M));
  M := Decode(' { "" : "" } '); AssertEquals(1, Length(M));
  AssertEquals('', string(M[0].Key)); AssertEquals('', string(M[0].Value));
end;

procedure TPrismEnvTests.ExactStringsAndOrder;
var M: TPrismEnvMap;
begin
  M := Decode('{"z":"  spaces  ","A":"=/;,#","a":"quote\" slash\\ solidus\/","é":"e\u0301"}');
  AssertEquals(4, Length(M));
  AssertEquals('z', string(M[0].Key)); AssertEquals('  spaces  ', string(M[0].Value));
  AssertEquals('A', string(M[1].Key)); AssertEquals('=/;,#', string(M[1].Value));
  AssertEquals('a', string(M[2].Key)); AssertEquals('quote" slash\ solidus/', string(M[2].Value));
  AssertEquals('é', string(M[3].Key)); AssertEquals('é', string(M[3].Value));
end;

procedure TPrismEnvTests.UnicodeAndControls;
var M: TPrismEnvMap;
begin
  M := Decode('{"\u65e5\u672c\u8a9e":"\ud83d\ude00","literal":"日本語 😀","control":"\u0000\b\f\n\r\t\u007f"}');
  AssertEquals('日本語', string(M[0].Key)); AssertEquals('😀', string(M[0].Value));
  AssertEquals('日本語 😀', string(M[1].Value));
  AssertEquals(#0#8#12#10#13#9#127, string(M[2].Value));
end;

procedure TPrismEnvTests.DuplicateDecodedKeys;
begin
  Refuses('{"secret":"one","secret":"two"}', peeDuplicateKey);
  Refuses('{"A":"one","\u0041":"two"}', peeDuplicateKey);
  Refuses('{"日本語":"one","\u65e5\u672c\u8a9e":"two"}', peeDuplicateKey);
  Refuses('{"😀":"one","\uD83D\uDE00":"two"}', peeDuplicateKey);
  Refuses('{"a/b":"one","a\/b":"two"}', peeDuplicateKey);
  Refuses('{"":"one","":"two"}', peeDuplicateKey);
end;

procedure TPrismEnvTests.OnlyObjectAndStrings;
begin
  Refuses('', peeMalformedJSON); Refuses('[]', peeMalformedJSON);
  Refuses('null', peeMalformedJSON); Refuses('"text"', peeMalformedJSON);
  Refuses('{"good":"ok","secret":null}', peeNonStringValue);
  Refuses('{"secret":true}', peeNonStringValue);
  Refuses('{"secret":false}', peeNonStringValue);
  Refuses('{"secret":123}', peeNonStringValue);
  Refuses('{"secret":{}}', peeNonStringValue);
  Refuses('{"secret":[]}', peeNonStringValue);
end;

procedure TPrismEnvTests.CompleteDocument;
begin
  Refuses('{}trailing-secret', peeMalformedJSON);
  Refuses('{} {}', peeMalformedJSON);
  Refuses('{}' + #0, peeMalformedScalar);
  Refuses('{}' + #11, peeMalformedScalar);
  Refuses('{"ok":"x",}', peeMalformedJSON);
  Refuses('{"ok":"x" "two":"y"}', peeMalformedJSON);
  Refuses('{"ok" "x"}', peeMalformedJSON);
  Refuses('{"ok":"x"', peeMalformedJSON);
end;

procedure TPrismEnvTests.MalformedStrings;
begin
  Refuses('{"a":"\q"}', peeMalformedJSON);
  Refuses('{"a":"\u123"}', peeMalformedJSON);
  Refuses('{"a":"\uxxxx"}', peeMalformedJSON);
  Refuses('{"a":"\ud800"}', peeMalformedJSON);
  Refuses('{"a":"\udc00"}', peeMalformedJSON);
  Refuses('{"a":"\ud800\u0041"}', peeMalformedJSON);
  Refuses('{"a":"\ud800\ud800"}', peeMalformedJSON);
  Refuses('{"a":"line' + #10 + 'break"}', peeMalformedJSON);
  Refuses('{"a":"unterminated}', peeMalformedJSON);
  Refuses('{"unterminated}', peeMalformedJSON);
end;

procedure TPrismEnvTests.ScalarFailures;
var M: TPrismEnvMap; E: TPrismEnvError;
begin
  M := Decode('{"old":"value"}');
  AssertFalse(DecodePrismEnv('@Variant(secret)', M, E));
  AssertEquals(Ord(peeUnsupportedScalar), Ord(E)); AssertEquals(0, Length(M));
  AssertFalse(DecodePrismEnv('"unfinished-secret', M, E));
  AssertEquals(Ord(peeMalformedScalar), Ord(E)); AssertEquals(0, Length(M));
  Refuses('{"a":"' + #$C0#$AF + '"}', peeMalformedScalar);
end;

procedure TPrismEnvTests.Bounds;
var Json: RawByteString; M: TPrismEnvMap; E: TPrismEnvError; I: Integer;
begin
  Json := '{"k":"' + StringOfChar('x', PrismScalarMaxOutputBytes - 8) + '"}';
  M := Decode(Json); AssertEquals(PrismScalarMaxOutputBytes - 8, Length(M[0].Value));
  Refuses(Json + ' ', peeLimitExceeded);
  AssertFalse(DecodePrismEnv(StringOfChar('x', PrismScalarMaxInputBytes + 1), M, E));
  AssertEquals(Ord(peeLimitExceeded), Ord(E)); AssertEquals(0, Length(M));
  Json := '{';
  for I := 1 to PrismEnvMaxEntries do
  begin
    if I > 1 then Json := Json + ',';
    Json := Json + '"k' + IntToStr(I) + '":""';
  end;
  M := Decode(Json + '}'); AssertEquals(PrismEnvMaxEntries, Length(M));
  Refuses(Json + ',"overflow":""}', peeLimitExceeded);
end;

initialization
  RegisterTest(TPrismEnvTests);
end.
