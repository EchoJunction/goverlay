unit prism_removal_test_cases;
{$mode objfpc}{$H+}
interface
uses SysUtils, fpcunit, testregistry, prismdocument;
type
  TPrismRemovalTests = class(TTestCase)
  private
    function Doc(const S: RawByteString): TPrismDocument;
    procedure Removes(const Before,After: RawByteString;
      const Names: array of RawByteString);
    procedure Refuses(const D: TPrismDocument; const Names: array of RawByteString;
      Expected: TPrismDocumentEditError);
  published
    procedure SingleAndWholeLine;
    procedure MultipleAndReordered;
    procedure MissingAndEmptyRequest;
    procedure EndingsAndNoFinalLF;
    procedure KeepOtherSectionsAndComments;
    procedure RejectNames;
    procedure RejectForgedIndexes;
    procedure BoundsAndStrictVersion;
    procedure PreserveInsertedEOFSeparator;
  end;
implementation
const H: RawByteString='[General]'#10'ConfigVersion=1.3'#10;
function TPrismRemovalTests.Doc(const S: RawByteString): TPrismDocument;
var E: TPrismDocumentError;
begin AssertTrue(IndexPrismDocument(S,Result,E)); end;
procedure TPrismRemovalTests.Removes(const Before,After: RawByteString;
  const Names: array of RawByteString);
var D,P,R: TPrismDocument; E: TPrismDocumentEditError; K: TPrismManagedKey;
begin
  D:=Doc(Before); AssertTrue(RemovePrismManagedLines(D,Names,P,E));
  AssertEquals(Ord(pdeeNone),Ord(E)); AssertEquals('Exact surviving bytes',After,P.Bytes);
  AssertEquals('Input unchanged',Before,D.Bytes); R:=Doc(After);
  AssertEquals(R.GeneralInsertOffset,P.GeneralInsertOffset);
  AssertEquals(R.GeneralLineEnding,P.GeneralLineEnding);
  for K:=Low(K) to High(K) do
  begin
    AssertEquals(R.Managed[K].Present,P.Managed[K].Present);
    AssertEquals(R.Managed[K].LineSpan.Offset,P.Managed[K].LineSpan.Offset);
    AssertEquals(R.Managed[K].LineSpan.Length,P.Managed[K].LineSpan.Length);
    AssertEquals(R.Managed[K].ValueSpan.Offset,P.Managed[K].ValueSpan.Offset);
    AssertEquals(R.Managed[K].ValueSpan.Length,P.Managed[K].ValueSpan.Length);
    AssertEquals(R.Managed[K].RawScalar,P.Managed[K].RawScalar);
    AssertEquals(R.Managed[K].DecodedScalar,P.Managed[K].DecodedScalar);
  end;
end;
procedure TPrismRemovalTests.Refuses(const D:TPrismDocument;
  const Names: array of RawByteString; Expected:TPrismDocumentEditError);
var P:TPrismDocument; E:TPrismDocumentEditError; K:TPrismManagedKey; Before:RawByteString;
begin
  Before:=D.Bytes; P:=Doc(H+'Env={}'#10);
  AssertFalse(RemovePrismManagedLines(D,Names,P,E)); AssertEquals(Ord(Expected),Ord(E));
  AssertEquals(Before,D.Bytes); AssertEquals('',P.Bytes);
  AssertEquals(0,P.GeneralInsertOffset); AssertEquals('',P.GeneralLineEnding);
  for K:=Low(K) to High(K) do
  begin
    AssertFalse(P.Managed[K].Present); AssertEquals('',P.Managed[K].RawScalar);
    AssertEquals('',P.Managed[K].DecodedScalar);
    AssertEquals(0,P.Managed[K].LineSpan.Offset); AssertEquals(0,P.Managed[K].LineSpan.Length);
    AssertEquals(0,P.Managed[K].ValueSpan.Offset); AssertEquals(0,P.Managed[K].ValueSpan.Length);
  end;
end;
procedure TPrismRemovalTests.SingleAndWholeLine;
begin
  Removes(H+' '#9'Env = "{}" '#9#10'Held=opaque'#10,H+'Held=opaque'#10,['Env']);
  Removes(H+'Env= '#9#10,H,['Env']);
  Removes(H+'EnableMangoHud="true"'#10,H,['EnableMangoHud']);
end;
procedure TPrismRemovalTests.MultipleAndReordered;
var S:RawByteString;
begin
  S:=H+'OverridePerformance=true'#10'EnableMangoHud=true'#10+
    'UseDiscreteGpu=false'#10'UseZink=true'#10'EnableFeralGamemode=false'#10+
    'OverrideEnv=true'#10'Env={}'#10'OverrideCommands=false'#10+
    'OverrideLaunchCmd=false'#10'WrapperCommand='#10;
  Removes(S,H,['Env','WrapperCommand','UseZink','OverrideCommands','EnableMangoHud',
    'OverrideEnv','OverridePerformance','UseDiscreteGpu','EnableFeralGamemode','OverrideLaunchCmd']);
  Removes(H+'Env={}'#10'UseZink=true'#10, H,['UseZink','Env']);
end;
procedure TPrismRemovalTests.MissingAndEmptyRequest;
begin
  Removes(H,H,['Env']); Removes(H+'Unknown=opaque'#10,H+'Unknown=opaque'#10,[]);
  Removes(H+'UseZink=false'#10,H,['Env','UseZink']);
end;
procedure TPrismRemovalTests.EndingsAndNoFinalLF;
const C:RawByteString='[General]'#13#10'ConfigVersion=1.3'#13#10;
begin
  Removes(C+'Env={}'#13#10'Unknown=kept'#13#10,C+'Unknown=kept'#13#10,['Env']);
  Removes(H+'Env={}'#13#10'Unknown=kept'#10'UseZink=true',H+'Unknown=kept'#10,['UseZink','Env']);
  Removes(H+'Env={}',H,['Env']);
  Removes(H+'Env={}'#10'Unknown=kept',H+'Unknown=kept',['Env']);
  Removes(C+'Env={}',C,['Env']);
end;
procedure TPrismRemovalTests.KeepOtherSectionsAndComments;
const Tail:RawByteString='; untouched comment'#10#10'[Other]'#10'Env=opaque'#10'UseZink=opaque';
begin
  Removes(H+'Env={}'#10+Tail,H+Tail,['Env','UseZink']);
  Removes('[First]'#10'Env=opaque'#10+H+'Env={}'#10+Tail,
    '[First]'#10'Env=opaque'#10+H+Tail,['Env']);
end;
procedure TPrismRemovalTests.RejectNames;
var D:TPrismDocument;
begin
  D:=Doc(H+'Env={}'#10);
  Refuses(D,['Env','Env'],pdeeDuplicateEdit);
  Refuses(D,['UseZink','UseZink'],pdeeDuplicateEdit);
  Refuses(D,['Unknown'],pdeeUnsupportedKey); Refuses(D,['env'],pdeeUnsupportedKey);
  Refuses(D,[''],pdeeUnsupportedKey); Refuses(D,['ConfigVersion'],pdeeUnsupportedKey);
  Refuses(D,['Env','ConfigVersion'],pdeeUnsupportedKey);
end;
procedure TPrismRemovalTests.RejectForgedIndexes;
var D:TPrismDocument;
begin
  D:=Doc(H+'Env={}'#10); Inc(D.Managed[pmkEnv].LineSpan.Length); Refuses(D,['Env'],pdeeInvalidDocument);
  D:=Doc(H); D.Managed[pmkEnv].Present:=True; Refuses(D,['Env'],pdeeInvalidDocument);
  D:=Doc(H+'Env={}'#10); D.Managed[pmkEnv].RawScalar:='forged'; Refuses(D,['Env'],pdeeInvalidDocument);
  D:=Doc(H+'Env={}'#10); D.Managed[pmkEnv].DecodedScalar:='forged'; Refuses(D,[],pdeeInvalidDocument);
  D:=Doc(H+'Env={}'#10); Inc(D.Managed[pmkEnv].ValueSpan.Offset); Refuses(D,['Env'],pdeeInvalidDocument);
  D:=Doc(H); Inc(D.GeneralInsertOffset); Refuses(D,[],pdeeInvalidDocument);
  D:=Doc(H); D.GeneralLineEnding:=#13#10; Refuses(D,[],pdeeInvalidDocument);
  D:=Doc(H+'Env={}'#10); D.Bytes:=H+'Env=changed'#10; Refuses(D,['Env'],pdeeInvalidDocument);
end;
procedure TPrismRemovalTests.BoundsAndStrictVersion;
var D:TPrismDocument; Names:array of RawByteString; I:Integer; S:RawByteString;
begin
  D:=Default(TPrismDocument); D.Bytes:='[General]'#10'Env={}'#10;
  Refuses(D,['Env'],pdeeInvalidDocument);
  D.Bytes:='[General]'#10'ConfigVersion=1.2'#10; Refuses(D,[],pdeeInvalidDocument);
  D.Bytes:=H+StringOfChar('x',PrismDocumentMaxBytes); Refuses(D,['Env'],pdeeLimitExceeded);
  D.Bytes:=H+StringOfChar(#10,PrismDocumentMaxLines); Refuses(D,[],pdeeLimitExceeded);
  D:=Doc(H); SetLength(Names,Ord(High(TPrismManagedKey))+2);
  for I:=0 to High(Names) do Names[I]:='Env'; Refuses(D,Names,pdeeLimitExceeded);
  S:=H+'Env={}'#10';'+StringOfChar('x',PrismDocumentMaxBytes-Length(H)-Length('Env={}'#10)-1);
  Removes(S,H+';'+StringOfChar('x',PrismDocumentMaxBytes-Length(H)-Length('Env={}'#10)-1),['Env']);
end;
procedure TPrismRemovalTests.PreserveInsertedEOFSeparator;
var Before:RawByteString; D,P:TPrismDocument; Edits:array[0..0] of TPrismManagedEdit;
  E:TPrismDocumentEditError;
begin
  Before:='[General]'#10'ConfigVersion=1.3'; D:=Doc(Before);
  Edits[0].KeyName:='Env'; Edits[0].RawScalar:='{}';
  AssertTrue(EditPrismDocument(D,Edits,P,E));
  AssertEquals(Before+#10'Env={}',P.Bytes);
  { Physical removal owns no separator preceding the removed line. }
  Removes(P.Bytes,Before+#10,['Env']);
end;
initialization RegisterTest(TPrismRemovalTests);
end.
