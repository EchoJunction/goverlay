unit prism_primitives_test_cases;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, fpcunit, testregistry, prismsettings, prismenv, prismdocument;
type
  TPrismPrimitivesTests = class(TTestCase)
  private
    function Document(const S: RawByteString): TPrismDocument;
    function Edit(const Name, Scalar: RawByteString): TPrismManagedEdit;
    procedure Roundtrip(const M: TPrismEnvMap);
    procedure EnvRefuses(const M: TPrismEnvMap; Expected: TPrismEnvError);
    procedure EditRefuses(const D: TPrismDocument;
      const Edits: array of TPrismManagedEdit; Expected: TPrismDocumentEditError);
  published
    procedure QtNormalizedFixtures;
    procedure CanonicalBool;
    procedure UnsupportedBool;
    procedure CanonicalEnv;
    procedure ControlAndUnicodeEnv;
    procedure InvalidUTF8Env;
    procedure DuplicateEnv;
    procedure EnvBounds;
    procedure ExplicitGeneralAnchor;
    procedure ReplaceOnlyScalar;
    procedure InsertBeforeNextSection;
    procedure BatchedEditsAndNoop;
    procedure EOFAndMixedEndings;
    procedure RejectInvalidEdits;
    procedure RejectForgedIndex;
    procedure StrictVersion;
    procedure EditBounds;
  end;
implementation
const Header: RawByteString = '[General]'#10'ConfigVersion=1.3'#10;
function TPrismPrimitivesTests.Document(const S: RawByteString): TPrismDocument;
var E: TPrismDocumentError;
begin
  AssertTrue('Index fixture', IndexPrismDocument(S, Result, E));
end;
function TPrismPrimitivesTests.Edit(const Name, Scalar: RawByteString): TPrismManagedEdit;
begin Result.KeyName := Name; Result.RawScalar := Scalar; end;
procedure TPrismPrimitivesTests.Roundtrip(const M: TPrismEnvMap);
var S: RawByteString; R: TPrismEnvMap; E: TPrismEnvError; I: Integer;
begin
  AssertTrue('Encode strings', EncodePrismEnv(M, S, E));
  AssertEquals(Ord(peeNone), Ord(E));
  AssertTrue('Always whole-quoted', (Length(S) >= 4) and (S[1] = '"') and (S[Length(S)] = '"'));
  AssertTrue('Within scalar bound', Length(S) <= PrismScalarMaxInputBytes);
  AssertTrue('Decode encoded map', DecodePrismEnv(S, R, E));
  AssertEquals(Length(M), Length(R));
  for I := 0 to High(M) do
  begin
    AssertEquals('Ordered key', RawByteString(M[I].Key), RawByteString(R[I].Key));
    AssertEquals('Exact value', RawByteString(M[I].Value), RawByteString(R[I].Value));
  end;
end;
procedure TPrismPrimitivesTests.EnvRefuses(const M: TPrismEnvMap; Expected: TPrismEnvError);
var S: RawByteString; E: TPrismEnvError;
begin
  S := 'previous secret output';
  AssertFalse(EncodePrismEnv(M, S, E)); AssertEquals(Ord(Expected), Ord(E));
  AssertEquals('No partial encoding', '', string(S));
end;
procedure TPrismPrimitivesTests.EditRefuses(const D: TPrismDocument;
  const Edits: array of TPrismManagedEdit; Expected: TPrismDocumentEditError);
var P: TPrismDocument; E: TPrismDocumentEditError; Before: RawByteString; K: TPrismManagedKey;
begin
  P := Document(Header); Before := D.Bytes;
  AssertFalse(EditPrismDocument(D, Edits, P, E)); AssertEquals(Ord(Expected), Ord(E));
  AssertEquals('', string(P.Bytes)); AssertEquals(0, P.GeneralInsertOffset);
  AssertEquals('', string(P.GeneralLineEnding));
  for K := Low(K) to High(K) do
  begin
    AssertFalse(P.Managed[K].Present); AssertEquals('', string(P.Managed[K].RawScalar));
    AssertEquals('', string(P.Managed[K].DecodedScalar));
    AssertEquals(0, P.Managed[K].LineSpan.Offset); AssertEquals(0, P.Managed[K].ValueSpan.Offset);
    AssertEquals(0, P.Managed[K].LineSpan.Length); AssertEquals(0, P.Managed[K].ValueSpan.Length);
  end;
  AssertEquals('Input bytes unchanged', Before, D.Bytes);
end;
procedure TPrismPrimitivesTests.QtNormalizedFixtures;
var I: Integer; S, Name: RawByteString; F: TFileStream; D: TPrismDocument;
  M: TPrismEnvMap; E: TPrismEnvError; BE: TPrismBoolError; V: Boolean;
begin
  for I := 0 to 1 do
  begin
    if I = 0 then Name := 'primitives-global.ini' else Name := 'primitives-instance.cfg';
    F := TFileStream.Create('tests/prism/fixtures/' + string(Name), fmOpenRead);
    try SetLength(S, F.Size); F.ReadBuffer(S[1], Length(S)); finally F.Free; end;
    D := Document(S);
    AssertTrue(DecodePrismBool(D.Managed[pmkOverridePerformance].RawScalar, V, BE));
    AssertEquals(I = 1, V);
    AssertTrue(DecodePrismBool(D.Managed[pmkEnableMangoHud].RawScalar, V, BE));
    AssertEquals(I = 0, V);
    AssertTrue(DecodePrismEnv(D.Managed[pmkEnv].RawScalar, M, E));
    if I = 0 then
    begin
      AssertEquals('"', string(D.Managed[pmkEnv].RawScalar[1])); AssertEquals(2, Length(M));
      AssertEquals('KEEP', string(M[0].Key));
      AssertEquals('global "quote" \ 日本語 😀' + #0#8#9#10#12#13#127, string(M[0].Value));
      AssertEquals('', string(M[1].Key)); AssertEquals('empty key', string(M[1].Value));
    end
    else
    begin
      AssertEquals('{', string(D.Managed[pmkEnv].RawScalar[1])); AssertEquals(1, Length(M));
      AssertEquals('MANGOHUD_CONFIGFILE', string(M[0].Key));
      AssertEquals('/tmp/Synthetic 日本語/overlay.conf', string(M[0].Value));
    end;
    Roundtrip(M);
  end;
end;
procedure TPrismPrimitivesTests.CanonicalBool;
var V: Boolean; E: TPrismBoolError;
begin
  AssertEquals('true', string(EncodePrismBool(True)));
  AssertEquals('false', string(EncodePrismBool(False)));
  AssertTrue(DecodePrismBool('true', V, E)); AssertTrue(V); AssertEquals(Ord(pbeNone), Ord(E));
  AssertTrue(DecodePrismBool('false', V, E)); AssertFalse(V);
  AssertTrue(DecodePrismBool('"true"', V, E)); AssertTrue(V);
  AssertTrue(DecodePrismBool('\x74rue', V, E)); AssertTrue(V);
end;
procedure TPrismPrimitivesTests.UnsupportedBool;
const Values: array[0..7] of string = ('', '""', '0', '1', 'TRUE', 'False', 'yes', '" true "');
var S: string; V: Boolean; E: TPrismBoolError;
begin
  for S in Values do
  begin V := True; AssertFalse(DecodePrismBool(S, V, E)); AssertFalse(V);
    AssertEquals(Ord(pbeUnsupportedValue), Ord(E)); end;
  AssertFalse(DecodePrismBool('@Variant(secret)', V, E)); AssertEquals(Ord(pbeUnsupportedEncoding), Ord(E));
  AssertFalse(DecodePrismBool('"unfinished', V, E)); AssertEquals(Ord(pbeMalformedScalar), Ord(E));
  AssertFalse(DecodePrismBool(StringOfChar('x', PrismScalarMaxInputBytes + 1), V, E));
  AssertEquals(Ord(pbeLimitExceeded), Ord(E)); AssertFalse(V);
end;
procedure TPrismPrimitivesTests.CanonicalEnv;
var M: TPrismEnvMap; S: RawByteString; E: TPrismEnvError;
begin
  M := nil; Roundtrip(M); AssertTrue(EncodePrismEnv(M, S, E)); AssertEquals('"{}"', string(S));
  SetLength(M, 1); M[0].Key := 'A'; M[0].Value := ' spaced ';
  Roundtrip(M); AssertTrue(EncodePrismEnv(M, S, E));
  AssertEquals('"{\"A\":\" spaced \"}"', string(S));
  SetLength(M, 3); M[1].Key := 'a'; M[1].Value := 'different case';
  M[2].Key := ''; M[2].Value := ''; Roundtrip(M);
end;
procedure TPrismPrimitivesTests.ControlAndUnicodeEnv;
var M: TPrismEnvMap; I: Integer;
begin
  SetLength(M, 3); M[0].Key := '日本語 😀'; M[0].Value := '  é é ,;=# " \ /  ';
  M[1].Key := #0#9#127; M[1].Value := '';
  for I := 0 to 31 do M[1].Value := M[1].Value + AnsiChar(I);
  M[1].Value := M[1].Value + #127;
  M[2].Key := '\u0041'; M[2].Value := 'literal escapes stay literal \ud800'; Roundtrip(M);
end;
procedure TPrismPrimitivesTests.InvalidUTF8Env;
const Invalid: array[0..7] of RawByteString = (#$C0#$AF, #$E0#$80#$AF,
  #$ED#$A0#$80, #$F4#$90#$80#$80, #$F5#$80#$80#$80, #$80, #$E2#$82, #$C2 + 'A');
var M: TPrismEnvMap; S: RawByteString;
begin
  SetLength(M, 1);
  for S in Invalid do
  begin
    M[0].Key := UTF8String(S); M[0].Value := 'safe'; EnvRefuses(M, peeInvalidUTF8);
    M[0].Key := 'safe'; M[0].Value := UTF8String(S); EnvRefuses(M, peeInvalidUTF8);
  end;
end;
procedure TPrismPrimitivesTests.DuplicateEnv;
var M: TPrismEnvMap;
begin
  SetLength(M, 2); M[0].Key := 'A'; M[1].Key := 'A'; EnvRefuses(M, peeDuplicateKey);
  M[0].Key := '😀'; M[1].Key := UTF8String(#$F0#$9F#$98#$80); EnvRefuses(M, peeDuplicateKey);
  M[0].Key := #0; M[1].Key := #0; EnvRefuses(M, peeDuplicateKey);
end;
procedure TPrismPrimitivesTests.EnvBounds;
var M: TPrismEnvMap; I: Integer;
begin
  SetLength(M, 1); M[0].Key := 'k';
  M[0].Value := UTF8String(StringOfChar('x', PrismScalarMaxOutputBytes - 8)); Roundtrip(M);
  M[0].Value := M[0].Value + 'x'; EnvRefuses(M, peeLimitExceeded);
  M[0].Value := UTF8String(StringOfChar(#0, (PrismScalarMaxOutputBytes - 8) div 6)); Roundtrip(M);
  M[0].Value := M[0].Value + #0; EnvRefuses(M, peeLimitExceeded);
  M[0].Value := UTF8String(StringOfChar('x', PrismScalarMaxOutputBytes + 1)); EnvRefuses(M, peeLimitExceeded);
  SetLength(M, PrismEnvMaxEntries);
  for I := 0 to High(M) do begin M[I].Key := UTF8String('k' + IntToStr(I)); M[I].Value := ''; end;
  Roundtrip(M); SetLength(M, PrismEnvMaxEntries + 1); EnvRefuses(M, peeLimitExceeded);
end;
procedure TPrismPrimitivesTests.ExplicitGeneralAnchor;
var D: TPrismDocument; S: RawByteString;
begin
  S := '[Other]'#10'Unknown=first'#10 + Header + '; keep'#10'[Later]'#10'Env=opaque';
  D := Document(S); AssertEquals(Pos('[Later]', string(S)), D.GeneralInsertOffset);
  AssertEquals(#10, string(D.GeneralLineEnding));
  D := Document('[General]'#13#10'ConfigVersion=1.3');
  AssertEquals(Length(D.Bytes) + 1, D.GeneralInsertOffset); AssertEquals(#13#10, string(D.GeneralLineEnding));
end;
procedure TPrismPrimitivesTests.ReplaceOnlyScalar;
var D, P: TPrismDocument; E: TPrismDocumentEditError; S, Expected: RawByteString;
begin
  S := Header + #9' Env '#9'= '#9'"old" '#9#13#10 + '[Other]'#10'Env=unrelated';
  Expected := Header + #9' Env '#9'= '#9'"{}" '#9#13#10 + '[Other]'#10'Env=unrelated';
  D := Document(S); AssertTrue(EditPrismDocument(D, [Edit('Env', '"{}"')], P, E));
  AssertEquals(Ord(pdeeNone), Ord(E)); AssertEquals(Expected, P.Bytes); AssertEquals(S, D.Bytes);
  AssertEquals('"{}"', string(P.Managed[pmkEnv].RawScalar));
  D := Document(Header + 'Env= '#9);
  AssertTrue(EditPrismDocument(D, [Edit('Env', '{}')], P, E));
  AssertEquals(Header + 'Env={}'#32#9, P.Bytes);
end;
procedure TPrismPrimitivesTests.InsertBeforeNextSection;
var D, P: TPrismDocument; E: TPrismDocumentEditError; S: RawByteString;
begin
  S := Header + 'Unknown=@Variant(opaque)'#10'; keep'#10'[Later]'#10'EnableMangoHud=dormant';
  D := Document(S); AssertTrue(EditPrismDocument(D, [Edit('EnableMangoHud', 'true')], P, E));
  AssertEquals(Header + 'Unknown=@Variant(opaque)'#10'; keep'#10'EnableMangoHud=true'#10+
    '[Later]'#10'EnableMangoHud=dormant', P.Bytes);
  AssertEquals('true', string(P.Managed[pmkEnableMangoHud].DecodedScalar));
end;
procedure TPrismPrimitivesTests.BatchedEditsAndNoop;
var D, P: TPrismDocument; E: TPrismDocumentEditError;
begin
  D := Document(Header + 'Env="old"'#10'EnableMangoHud=false'#10'Unknown=keep');
  AssertTrue(EditPrismDocument(D, [Edit('EnableMangoHud', 'true'), Edit('OverrideEnv', 'true'),
    Edit('Env', '"{}"'), Edit('OverridePerformance', 'true')], P, E));
  AssertEquals(Header + 'Env="{}"'#10'EnableMangoHud=true'#10'Unknown=keep'#10+
    'OverrideEnv=true'#10'OverridePerformance=true', P.Bytes);
  D := P; AssertTrue(EditPrismDocument(D, [], P, E)); AssertEquals(D.Bytes, P.Bytes);
  D := Document(Header + 'Env=');
  AssertTrue(EditPrismDocument(D, [Edit('OverrideEnv', 'true'), Edit('Env', '{}')], P, E));
  AssertEquals(Header + 'Env={}'#10'OverrideEnv=true', P.Bytes);
end;
procedure TPrismPrimitivesTests.EOFAndMixedEndings;
const Endings: array[0..1] of RawByteString = (#10, #13#10);
var Ending: RawByteString; D, P: TPrismDocument; E: TPrismDocumentEditError;
begin
  for Ending in Endings do
  begin
    D := Document('[General]' + Ending + 'ConfigVersion=1.3');
    AssertTrue(EditPrismDocument(D, [Edit('OverrideEnv', 'true'), Edit('Env', '{}')], P, E));
    AssertEquals(D.Bytes + Ending + 'OverrideEnv=true' + Ending + 'Env={}', P.Bytes);
    D := Document(D.Bytes + Ending);
    AssertTrue(EditPrismDocument(D, [Edit('Env', '{}')], P, E));
    AssertEquals(D.Bytes + 'Env={}' + Ending, P.Bytes);
  end;
  D := Document('[General]'#13#10'ConfigVersion=1.3'#10'; mixed');
  AssertTrue(EditPrismDocument(D, [Edit('Env', '{}')], P, E));
  AssertEquals(D.Bytes + #13#10'Env={}', P.Bytes);
end;
procedure TPrismPrimitivesTests.RejectInvalidEdits;
var D: TPrismDocument;
begin
  D := Document(Header);
  EditRefuses(D, [Edit('JavaPath', 'secret')], pdeeUnsupportedKey);
  EditRefuses(D, [Edit('env', '{}')], pdeeUnsupportedKey);
  EditRefuses(D, [Edit('%45nv', '{}')], pdeeUnsupportedKey);
  EditRefuses(D, [Edit('Env', '{}'), Edit('Env', '{}')], pdeeDuplicateEdit);
  EditRefuses(D, [Edit('Env', '"unterminated')], pdeeInvalidScalar);
  EditRefuses(D, [Edit('Env', 'injected'#10'Unknown=write')], pdeeInvalidScalar);
end;
procedure TPrismPrimitivesTests.RejectForgedIndex;
var D: TPrismDocument;
begin
  D := Document(Header + 'Env={}'); Inc(D.Managed[pmkEnv].ValueSpan.Offset);
  EditRefuses(D, [Edit('Env', '{}')], pdeeInvalidDocument);
  D := Document(Header); Inc(D.GeneralInsertOffset);
  EditRefuses(D, [Edit('Env', '{}')], pdeeInvalidDocument);
  D := Document(Header); D.GeneralLineEnding := #13#10;
  EditRefuses(D, [], pdeeInvalidDocument);
  D := Document(Header); D.Bytes := '[General]'#10'ConfigVersion=1.2';
  EditRefuses(D, [], pdeeInvalidDocument);
end;
procedure TPrismPrimitivesTests.StrictVersion;
var D: TPrismDocument;
begin
  D := Document(Header); EditRefuses(D, [Edit('ConfigVersion', '1.2')], pdeeInvalidResult);
  D := Default(TPrismDocument); D.Bytes := '[General]'#10'Env={}';
  EditRefuses(D, [Edit('ConfigVersion', '1.3')], pdeeInvalidDocument);
end;
procedure TPrismPrimitivesTests.EditBounds;
var D, P: TPrismDocument; E: TPrismDocumentEditError; S: RawByteString;
  Many: array of TPrismManagedEdit; I: Integer;
begin
  S := Header + 'Unknown='; S := S + StringOfChar('x', PrismDocumentMaxBytes - Length(S));
  D := Document(S); AssertTrue(EditPrismDocument(D, [], P, E)); AssertEquals(S, P.Bytes);
  EditRefuses(D, [Edit('Env', '{}')], pdeeLimitExceeded);
  S := Header + 'Env=old'#10'Unknown=';
  S := S + StringOfChar('x', PrismDocumentMaxBytes - Length('OverrideEnv=true') - Length(S));
  D := Document(S);
  AssertTrue(EditPrismDocument(D, [Edit('Env', '""'), Edit('OverrideEnv', 'true')], P, E));
  AssertEquals(PrismDocumentMaxBytes, Length(P.Bytes));
  D := Document(Header + StringOfChar(#10, PrismDocumentMaxLines - 2));
  EditRefuses(D, [Edit('Env', '{}')], pdeeLimitExceeded);
  D := Document(Header);
  EditRefuses(D, [Edit('Env', StringOfChar('x', PrismScalarMaxInputBytes + 1))], pdeeLimitExceeded);
  SetLength(Many, Ord(High(TPrismManagedKey)) + 2);
  for I := 0 to High(Many) do Many[I] := Edit('Env', '{}');
  EditRefuses(D, Many, pdeeLimitExceeded);
end;
initialization RegisterTest(TPrismPrimitivesTests);
end.
