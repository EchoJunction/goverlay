unit prism_document_test_cases;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, fpcunit, testregistry, prismdocument;

type
  TPrismDocumentTests = class(TTestCase)
  private
    procedure Accepts(const Bytes: RawByteString; out D: TPrismDocument);
    procedure Refuses(const Bytes: RawByteString; Expected: TPrismDocumentError);
  published
    procedure PreservesBytesAndSpans;
    procedure AbsentAndEmptyManagedKeys;
    procedure GlobalAndInstanceHaveSameContract;
    procedure VersionValidation;
    procedure DuplicatesAndEncodedAliases;
    procedure MalformedDocuments;
    procedure ManagedScalarForms;
    procedure BoundsAndLineEndings;
  end;

implementation

const Header: RawByteString = '[General]'#10'ConfigVersion=1.3'#10;

procedure TPrismDocumentTests.Accepts(const Bytes: RawByteString;
  out D: TPrismDocument);
var E: TPrismDocumentError; Before: RawByteString;
begin
  Before := Bytes;
  AssertTrue('Document accepted', IndexPrismDocument(Bytes, D, E));
  AssertEquals('Success reason', Ord(pdeNone), Ord(E));
  AssertEquals('Original bytes', Before, D.Bytes);
  AssertEquals('Input untouched', Before, Bytes);
end;

procedure TPrismDocumentTests.Refuses(const Bytes: RawByteString;
  Expected: TPrismDocumentError);
var D: TPrismDocument; E: TPrismDocumentError; K: TPrismManagedKey;
    Before: RawByteString;
begin
  Accepts(Header + 'Env=old', D);
  Before := Bytes;
  AssertFalse('Document refused', IndexPrismDocument(Bytes, D, E));
  AssertEquals('Fixed reason', Ord(Expected), Ord(E));
  AssertEquals('No partial original bytes', '', string(D.Bytes));
  for K := Low(K) to High(K) do
  begin
    AssertFalse('No partial presence', D.Managed[K].Present);
    AssertEquals('No partial scalar', '', string(D.Managed[K].RawScalar));
    AssertEquals('No partial decoded scalar', '', string(D.Managed[K].DecodedScalar));
    AssertEquals('No partial line offset', 0, D.Managed[K].LineSpan.Offset);
    AssertEquals('No partial value length', 0, D.Managed[K].ValueSpan.Length);
  end;
  AssertEquals('Failed input untouched', Before, Bytes);
end;

procedure TPrismDocumentTests.PreservesBytesAndSpans;
var S, Line: RawByteString; D: TPrismDocument;
begin
  Line := #9' Env '#9'= '#9'" spaced " '#9#13#10;
  S := RawByteString(UTF8String('; comment 日本語')) + #13#10 + Header + ';second comment'#10 +
    'Unknown=@ByteArray(opaque)'#10 + 'List=one, "two,three"'#10 +
    'configversion=case-sensitive-unknown'#10 + Line +
    '[Other]'#13#10'Env=@Variant(opaque)'#10'Order=last';
  Accepts(S, D);
  AssertEquals('Full physical line', Line, Copy(D.Bytes,
    D.Managed[pmkEnv].LineSpan.Offset, D.Managed[pmkEnv].LineSpan.Length));
  AssertEquals('Exact scalar span', '" spaced "', Copy(D.Bytes,
    D.Managed[pmkEnv].ValueSpan.Offset, D.Managed[pmkEnv].ValueSpan.Length));
  AssertEquals('Raw scalar retained', '" spaced "', string(D.Managed[pmkEnv].RawScalar));
  AssertEquals('Decoded whitespace', ' spaced ', string(D.Managed[pmkEnv].DecodedScalar));
end;

procedure TPrismDocumentTests.AbsentAndEmptyManagedKeys;
var K: TPrismManagedKey; D: TPrismDocument; S: RawByteString;
begin
  Accepts(Header, D);
  for K := Succ(Low(K)) to High(K) do
  begin
    AssertFalse('Absent key', D.Managed[K].Present);
    AssertEquals('Absent offset', 0, D.Managed[K].ValueSpan.Offset);
    S := Header + RawByteString(PrismManagedKeyNames[K]) + '= '#9;
    Accepts(S, D);
    AssertTrue('Empty key present', D.Managed[K].Present);
    AssertTrue('Empty offset valid', D.Managed[K].ValueSpan.Offset > 0);
    AssertEquals('Empty length', 0, D.Managed[K].ValueSpan.Length);
    AssertEquals('Empty raw', '', string(D.Managed[K].RawScalar));
    AssertEquals('Empty decoded', '', string(D.Managed[K].DecodedScalar));
    S := Header + RawByteString(PrismManagedKeyNames[K]) + ' = "opaque"';
    Accepts(S, D);
    AssertEquals('Every key scalar span', '"opaque"', Copy(D.Bytes,
      D.Managed[K].ValueSpan.Offset, D.Managed[K].ValueSpan.Length));
    AssertEquals('Every key raw scalar', '"opaque"', string(D.Managed[K].RawScalar));
    Accepts(Header, D);
  end;
end;

procedure TPrismDocumentTests.GlobalAndInstanceHaveSameContract;
var D: TPrismDocument;
begin
  Accepts(Header + 'Env={}', D); { No InstanceType required globally or here. }
  Accepts(Header + 'InstanceType=OneSix'#10'Env={}', D);
  Accepts(Header + 'InstanceType=opaque-future-type', D);
  Accepts('[Other]'#10'ConfigVersion=wrong'#10 + Header, D);
end;

procedure TPrismDocumentTests.VersionValidation;
var D: TPrismDocument;
begin
  Accepts('[General]'#10'ConfigVersion="1.3"', D);
  Accepts('[General]'#10'ConfigVersion=\x31.3', D);
  Refuses('', pdeUnsupportedVersion);
  Refuses('[Other]'#10'ConfigVersion=1.3', pdeUnsupportedVersion);
  Refuses('[General]'#10'Env={}', pdeUnsupportedVersion);
  Refuses('[General]'#10'configversion=1.3', pdeUnsupportedVersion);
  Refuses('[General]'#10'ConfigVersion=', pdeUnsupportedVersion);
  Refuses('[General]'#10'ConfigVersion=1.2', pdeUnsupportedVersion);
  Refuses('[General]'#10'ConfigVersion=1.3junk', pdeUnsupportedVersion);
end;

procedure TPrismDocumentTests.DuplicatesAndEncodedAliases;
var K: TPrismManagedKey; Name: RawByteString;
begin
  Refuses(Header + '[General]', pdeDuplicate);
  Refuses(Header + '[general]', pdeUnsupportedEncoding);
  Refuses(Header + '[GENERAL]', pdeUnsupportedEncoding);
  Refuses(Header + '[ General ]', pdeUnsupportedEncoding);
  Refuses(Header + '[%General]', pdeUnsupportedEncoding);
  Refuses(Header + '[%47eneral]', pdeUnsupportedEncoding);
  Refuses(Header + '[Other/Sub]', pdeUnsupportedEncoding);
  Refuses(Header + '[Other\Sub]', pdeUnsupportedEncoding);
  Refuses(Header + '%45nv=hidden', pdeUnsupportedEncoding);
  Refuses(Header + 'En%76=hidden', pdeUnsupportedEncoding);
  Refuses(Header + 'E\nv=hidden', pdeUnsupportedEncoding);
  for K := Low(K) to High(K) do
  begin
    Name := RawByteString(PrismManagedKeyNames[K]);
    if K = pmkConfigVersion then Refuses(Header + Name + '=1.3', pdeDuplicate)
    else Refuses(Header + Name + '='#10 + Name + '=', pdeDuplicate);
  end;
end;

procedure TPrismDocumentTests.MalformedDocuments;
begin
  Refuses('ConfigVersion=1.3'#10 + Header, pdeMalformed);
  Refuses(Header + 'not an assignment', pdeMalformed);
  Refuses(Header + '#comment', pdeMalformed);
  Refuses(Header + '#comment\'#10'Env=hidden', pdeMalformed);
  Refuses(Header + '#comment"'#10'Env=hidden', pdeMalformed);
  Refuses(Header + '#comment=value'#10'Env=visible', pdeUnsupportedEncoding);
  Refuses(Header + '=empty-key', pdeUnsupportedEncoding);
  Refuses(Header + '[unfinished', pdeMalformed);
  Refuses(Header + '[Other]trailing', pdeMalformed);
  Refuses(Header + '[Other]]', pdeUnsupportedEncoding);
  Refuses(Header + 'Env=one;comment', pdeUnsupportedEncoding);
  Refuses(Header + 'Env="a"fragment', pdeMalformed);
  Refuses(Header + 'Unknown="unterminated'#10'Env=hidden', pdeMalformed);
  Refuses(Header + 'Unknown=continued\'#10'Env=hidden', pdeMalformed);
  Refuses(Header + 'Unknown=abc'#13'Env=hidden', pdeMalformed);
  Refuses(Header + #0, pdeMalformed);
  Refuses(Header + #$C0#$AF, pdeMalformed);
  Refuses(Header + #$ED#$A0#$80, pdeMalformed);
  Refuses(Header + #$F4#$90#$80#$80, pdeMalformed);
  Refuses(Header + #$E2#$82, pdeMalformed);
  Refuses(#$EF#$BB#$BF + Header, pdeUnsupportedEncoding);
end;

procedure TPrismDocumentTests.ManagedScalarForms;
var D: TPrismDocument;
begin
  Accepts(Header + 'Env={\"KEY\":\"value\"}', D);
  AssertEquals('Unquoted JSON remains opaque', '{"KEY":"value"}', string(D.Managed[pmkEnv].DecodedScalar));
  Accepts(Header + 'Env="{\"KEY\":\"value,;#\"}"', D);
  AssertEquals('Quoted JSON remains opaque', '{"KEY":"value,;#"}', string(D.Managed[pmkEnv].DecodedScalar));
  Accepts(Header + 'Env={broken JSON}'#10'EnableMangoHud=not-a-bool', D);
  Accepts(Header + 'Env=hash#literal'#10'Unknown=one;ignored " comment', D);
  Accepts(Header + 'Unknown=ends-with-paired\\', D);
  Refuses(Header + 'Env=@ByteArray(opaque)', pdeUnsupportedEncoding);
  Refuses(Header + 'Env=one,two', pdeUnsupportedEncoding);
end;

procedure TPrismDocumentTests.BoundsAndLineEndings;
var D: TPrismDocument; S: RawByteString;
begin
  Accepts('[General]'#13#10'ConfigVersion=1.3', D);
  AssertEquals('No final newline span', Length('ConfigVersion=1.3'),
    D.Managed[pmkConfigVersion].LineSpan.Length);
  S := Header + 'Unknown=';
  S := S + StringOfChar('x', PrismDocumentMaxBytes - Length(S));
  Accepts(S, D);
  Refuses(S + 'x', pdeLimitExceeded);
  Refuses(Header + 'Env=' + StringOfChar('x', 64 * 1024 + 1), pdeLimitExceeded);
  S := Header + StringOfChar(#10, PrismDocumentMaxLines - 2);
  Accepts(S, D);
  Refuses(S + #10, pdeLimitExceeded);
end;

initialization
  RegisterTest(TPrismDocumentTests);
end.
