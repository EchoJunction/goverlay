unit prism_settings_test_cases;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses Classes, SysUtils, fpcunit, testregistry, prismsettings;

type
  TPrismScalarTests = class(TTestCase)
  private
    procedure Decodes(const Raw: RawByteString; const Expected: UTF8String);
    procedure Refuses(const Raw: RawByteString; Expected: TPrismScalarError);
    function FixtureEnv(const Name: string): RawByteString;
  published
    procedure QtGeneratedEnvForms;
    procedure UnicodeAndEscapes;
    procedure EmptyAndLiteralAt;
    procedure MalformedAndUnsupported;
    procedure InvalidUnicode;
    procedure Bounds;
  end;

implementation

procedure TPrismScalarTests.Decodes(const Raw: RawByteString;
  const Expected: UTF8String);
var V: UTF8String; E: TPrismScalarError; Before: RawByteString;
begin
  Before := Raw;
  AssertTrue('Scalar should decode', DecodePrismScalar(Raw, V, E));
  AssertEquals('Success reason', Ord(pseNone), Ord(E));
  AssertEquals('Exact decoded bytes', RawByteString(Expected), RawByteString(V));
  AssertEquals('Input preserved', Before, Raw);
end;

procedure TPrismScalarTests.Refuses(const Raw: RawByteString;
  Expected: TPrismScalarError);
var V: UTF8String; E: TPrismScalarError; Before: RawByteString;
begin
  Before := Raw; V := 'previous output';
  AssertFalse('Scalar should fail closed', DecodePrismScalar(Raw, V, E));
  AssertEquals('Fixed failure reason', Ord(Expected), Ord(E));
  AssertEquals('No partial output', '', string(V));
  AssertEquals('Input preserved', Before, Raw);
end;

function TPrismScalarTests.FixtureEnv(const Name: string): RawByteString;
var Lines: TStringList; I: Integer;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile('tests/prism/fixtures/' + Name);
    for I := 0 to Lines.Count - 1 do
      if Copy(Lines[I], 1, 4) = 'Env=' then Exit(Copy(Lines[I], 5, MaxInt));
    Fail('Missing synthetic fixture Env');
  finally Lines.Free; end;
end;

procedure TPrismScalarTests.QtGeneratedEnvForms;
begin
  Decodes(FixtureEnv('scalar-quoted.ini'),
    '{"KEEP":"quote\" slash\\ newline\n tab\t","MANGOHUD_CONFIGFILE":"/tmp/Prism test/日本語,=#;\\path/overlay.conf"}');
  Decodes(FixtureEnv('scalar-unquoted.ini'),
    '{"MANGOHUD_CONFIGFILE":"/tmp/Synthetic 日本語/overlay.conf"}');
  { JSON semantics belong to a later layer: malformed JSON is still a scalar. }
  Decodes('{broken JSON}', '{broken JSON}');
end;

procedure TPrismScalarTests.UnicodeAndEscapes;
begin
  Decodes('日本語 😀', '日本語 😀');
  Decodes('\x65e5\x672c\x8a9e \xd83d\xde00', '日本語 😀');
  Decodes('"punctuation ,=#; and \"quote\" \\ slash"',
    'punctuation ,=#; and "quote" \ slash');
  Decodes('\a\b\f\n\r\t\v\''\?', #7#8#12#10#13#9#11 + '''?');
  Decodes('\x1\x7f\x80\x800\xffff', #1#127 + UTF8String(#$C2#$80#$E0#$A0#$80#$EF#$BF#$BF));
end;

procedure TPrismScalarTests.EmptyAndLiteralAt;
begin
  Decodes('', '');
  Decodes('""', '');
  Decodes('"  spaced  "', '  spaced  ');
  Decodes('@@literal', '@literal');
  Decodes('"@@Variant(fake)"', '@Variant(fake)');
  Decodes('@@@', '@@');
end;

procedure TPrismScalarTests.MalformedAndUnsupported;
begin
  Refuses('"unfinished', pseMalformed);
  Refuses('trailing"', pseMalformed);
  Refuses('"a"junk', pseMalformed);
  Refuses('"a""b"', pseMalformed);
  Refuses('before"fragment"after', pseMalformed);
  Refuses('prefix\', pseMalformed);
  Refuses('prefix\x', pseMalformed);
  Refuses('\x12345', pseMalformed);
  Refuses('prefix\q', pseUnsupportedEncoding);
  Refuses('\123', pseUnsupportedEncoding);
  Refuses('\u1234', pseUnsupportedEncoding);
  Refuses('@Variant(secret)', pseUnsupportedEncoding);
  Refuses('"@ByteArray(secret)"', pseUnsupportedEncoding);
  Refuses('@Invalid()', pseUnsupportedEncoding);
  Refuses('one,two', pseUnsupportedEncoding);
  Refuses('"one", "two"', pseMalformed);
  Refuses('scalar;comment', pseUnsupportedEncoding);
  Refuses(' value', pseMalformed);
  Refuses('value ', pseMalformed);
  Refuses('prefix' + #10 + 'suffix', pseMalformed);
  Refuses('prefix' + #0, pseMalformed);
  Refuses('\x0', pseMalformed);
end;

procedure TPrismScalarTests.InvalidUnicode;
begin
  Refuses('\xd800', pseMalformed);
  Refuses('\xdc00', pseMalformed);
  Refuses('\xd800\x0041', pseMalformed);
  Refuses('\xd800\xd800', pseMalformed);
  Refuses('\xd800\x', pseMalformed);
  Refuses(#$C0#$AF, pseMalformed);
  Refuses(#$E0#$80#$AF, pseMalformed);
  Refuses(#$ED#$A0#$80, pseMalformed);
  Refuses(#$F4#$90#$80#$80, pseMalformed);
  Refuses(#$F5#$80#$80#$80, pseMalformed);
  Refuses(#$80, pseMalformed);
  Refuses(#$E2#$82, pseMalformed);
  Refuses(#$E2 + 'AB', pseMalformed);
  Refuses(#$C2 + '\x80', pseMalformed);
end;

procedure TPrismScalarTests.Bounds;
var S: RawByteString; I: SizeInt;
begin
  S := StringOfChar('a', PrismScalarMaxOutputBytes);
  Decodes(S, UTF8String(S));
  Refuses(S + 'a', pseLimitExceeded);
  Refuses(StringOfChar('a', PrismScalarMaxInputBytes + 1), pseLimitExceeded);
  { Exact input bound with a full output bound after escape decoding. }
  SetLength(S, PrismScalarMaxInputBytes);
  for I := 0 to PrismScalarMaxOutputBytes - 1 do
  begin
    S[I * 4 + 1] := '\'; S[I * 4 + 2] := 'x';
    S[I * 4 + 3] := '4'; S[I * 4 + 4] := '1';
  end;
  Decodes(S, UTF8String(StringOfChar('A', PrismScalarMaxOutputBytes)));
  S := StringOfChar('a', PrismScalarMaxOutputBytes - 1) + '\x800';
  Refuses(S, pseLimitExceeded);
end;

initialization
  RegisterTest(TPrismScalarTests);
end.
