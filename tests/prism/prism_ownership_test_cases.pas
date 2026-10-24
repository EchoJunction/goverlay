unit prism_ownership_test_cases;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, SHA1, fpcunit, testregistry, prismprovider, gamecontext,
  prismdocument, prismenv, prismsnapshot, prismplan, prismownership;
type
  TPrismOwnershipTests=class(TTestCase)
  private
    function RecordFor(const G,L:RawByteString; FolderIdentity:Boolean=False):TPrismEnableProposal;
    function Sample:TPrismEnableProposal;
    procedure Refuses(const P:TPrismEnableProposal; Expected:TPrismOwnershipReason);
    procedure Valid(const P:TPrismEnableProposal);
    procedure AlterValue(var V:TPrismIndexedValue; Field:Integer);
  published
    procedure ValidCanonicalRecords;
    procedure TamperedOwnershipFlags;
    procedure TamperedAppliedValues;
    procedure TamperedBeforeValues;
    procedure TamperedGates;
    procedure TamperedDocumentIndexes;
    procedure TamperedMaps;
    procedure TamperedInputsAndBounds;
    procedure CanonicalCopyAndNoMutation;
  end;
implementation
const H:RawByteString='[General]'#10'ConfigVersion=1.3'#10;
function TPrismOwnershipTests.RecordFor(const G,L:RawByteString;
  FolderIdentity:Boolean):TPrismEnableProposal;
var I:TPrismInstance; C:TActiveProfileContext; S:TPrismSettingsSnapshot;
  R:TPrismEnableReason; AR:TPrismAssessmentReason;
begin
  I:=Default(TPrismInstance); I.DataRoot:='/synthetic/Prism'; I.Folder:='A';
  I.ConfigPath:='/external/instances/A/instance.cfg'; I.UUID:='0123456789abcdef0123456789abcdef';
  I.InstallationKey:='prism-root-'+SHA1Print(SHA1String(I.DataRoot));
  I.UsesFolderIdentity:=FolderIdentity;
  if FolderIdentity then
  begin I.UUID:=''; I.StableKey:='prism-'+SHA1Print(SHA1String(I.DataRoot+#0+'folder:/external/instances/A')); end
  else I.StableKey:='prism-'+SHA1Print(SHA1String(I.DataRoot+#0+'uuid:'+I.UUID));
  AssertTrue(PrismProfileContext(I,'/synthetic/日本語 data',C));
  S:=Default(TPrismSettingsSnapshot); S.GlobalDocument.Bytes:=H+G; S.InstanceDocument.Bytes:=H+L;
  AssertEquals(Ord(psaReady),Ord(PlanPrismEnable(I,'/synthetic/日本語 data',
    C.ConfigDir+'MangoHud.conf',S,Result,R,AR)));
end;
function TPrismOwnershipTests.Sample:TPrismEnableProposal;
var M:TPrismEnvMap; E:TPrismEnvError; Raw:RawByteString;
begin
  SetLength(M,2); M[0].Key:='KEEP'; M[0].Value:='日本語 😀'+#0#10;
  M[1].Key:='SECOND'; M[1].Value:='"quoted" \'; AssertTrue(EncodePrismEnv(M,Raw,E));
  Result:=RecordFor('EnableMangoHud=false'#10'UseDiscreteGpu=true'#10'UseZink=false'#10+
    'EnableFeralGamemode=true'#10'Env='+Raw+#10'WrapperCommand='#10,
    'OverridePerformance=false'#10'OverrideEnv=false'#10'OverrideCommands=false'#10+
    'WrapperCommand=dormant'#10'Unknown=keep'#10);
end;
procedure TPrismOwnershipTests.Valid(const P:TPrismEnableProposal);
var C:TPrismEnableProposal; R:TPrismOwnershipReason;
begin
  AssertTrue(ValidatePrismEnableRecord(P,C,R)); AssertEquals(Ord(porNone),Ord(R));
  AssertEquals(P.Instance.StableKey,C.Instance.StableKey);
  AssertEquals(P.BeforeSnapshot.GlobalDocument.Bytes,C.BeforeSnapshot.GlobalDocument.Bytes);
  AssertEquals(P.BeforeSnapshot.InstanceDocument.Bytes,C.BeforeSnapshot.InstanceDocument.Bytes);
  AssertEquals(P.ProposedInstanceDocument.Bytes,C.ProposedInstanceDocument.Bytes);
  AssertEquals(P.Selector,C.Selector); AssertEquals(P.OwnsMangoHudEnable,C.OwnsMangoHudEnable);
end;
procedure TPrismOwnershipTests.Refuses(const P:TPrismEnableProposal;
  Expected:TPrismOwnershipReason);
var C:TPrismEnableProposal; R:TPrismOwnershipReason; K:TPrismManagedKey;
  F:TPrismPerformanceFlag; Before,Applied:RawByteString;
begin
  C:=Sample; Before:=P.BeforeSnapshot.InstanceDocument.Bytes; Applied:=P.ProposedInstanceDocument.Bytes;
  AssertFalse(ValidatePrismEnableRecord(P,C,R)); AssertEquals(Ord(Expected),Ord(R));
  AssertEquals(Before,P.BeforeSnapshot.InstanceDocument.Bytes); AssertEquals(Applied,P.ProposedInstanceDocument.Bytes);
  AssertEquals('',C.Instance.StableKey); AssertEquals('',C.HostDataDir); AssertEquals('',C.Selector);
  AssertEquals('',C.BeforeSnapshot.GlobalDocument.Bytes); AssertEquals('',C.BeforeSnapshot.InstanceDocument.Bytes);
  AssertEquals('',C.ProposedInstanceDocument.Bytes); AssertEquals(0,Length(C.AppliedEnv));
  AssertEquals(0,Length(C.BeforeSnapshot.Env.Entries)); AssertFalse(C.BeforeSnapshot.AmbientEnvironmentVerified);
  AssertFalse(C.OwnsSelector); AssertFalse(C.OwnsMangoHudEnable); AssertFalse(C.SelectorOnlyAdoption);
  AssertFalse(C.PerformanceInheritanceFreeze); AssertFalse(C.EnvInheritanceFreeze);
  AssertFalse(C.AppliedPerformanceGate); AssertFalse(C.AppliedEnvGate); AssertFalse(C.AppliedCommandsGate);
  for K:=Low(K) to High(K) do
  begin
    AssertFalse(C.Touched[K]); AssertFalse(C.Owned[K]);
    AssertFalse(C.ProposedInstanceDocument.Managed[K].Present);
    AssertEquals('',C.ProposedInstanceDocument.Managed[K].RawScalar);
  end;
  for F:=Low(F) to High(F) do AssertFalse(C.AppliedPerformance[F]);
end;
procedure TPrismOwnershipTests.AlterValue(var V:TPrismIndexedValue; Field:Integer);
begin
  case Field of
    0:V.Present:=not V.Present;
    1:Inc(V.LineSpan.Offset);
    2:Inc(V.LineSpan.Length);
    3:Inc(V.ValueSpan.Offset);
    4:Inc(V.ValueSpan.Length);
    5:V.RawScalar+='secret tamper';
    6:V.DecodedScalar+='secret tamper';
  end;
end;
procedure TPrismOwnershipTests.ValidCanonicalRecords;
var P:TPrismEnableProposal;
begin
  Valid(Sample); Valid(RecordFor('','')); Valid(RecordFor('','',True));
  Valid(RecordFor('EnableMangoHud=true'#10,'EnableMangoHud=dormant invalid'#10));
  Valid(RecordFor('','OverridePerformance=true'#10'EnableMangoHud=true'#10));
  Valid(RecordFor('UseDiscreteGpu=true'#10,'OverridePerformance=true'#10));
  Valid(RecordFor('Env={}'#10,'OverrideEnv=true'#10));
  P:=RecordFor('','OverrideEnv=true'#10'Env={}'#10'OverrideLaunchCmd=true'#10'WrapperCommand='#10);
  AssertFalse(P.EnvInheritanceFreeze); Valid(P);
end;
procedure TPrismOwnershipTests.TamperedOwnershipFlags;
var P:TPrismEnableProposal; K:TPrismManagedKey; I:Integer;
begin
  for K:=Low(K) to High(K) do
  begin
    P:=Sample; P.Touched[K]:=not P.Touched[K]; Refuses(P,porOwnershipFlags);
    P:=Sample; P.Owned[K]:=not P.Owned[K]; Refuses(P,porOwnershipFlags);
  end;
  for I:=0 to 4 do
  begin
    P:=Sample;
    case I of
      0:P.OwnsSelector:=not P.OwnsSelector;
      1:P.OwnsMangoHudEnable:=not P.OwnsMangoHudEnable;
      2:P.SelectorOnlyAdoption:=not P.SelectorOnlyAdoption;
      3:P.PerformanceInheritanceFreeze:=not P.PerformanceInheritanceFreeze;
      4:P.EnvInheritanceFreeze:=not P.EnvInheritanceFreeze;
    end;
    Refuses(P,porOwnershipFlags);
  end;
end;
procedure TPrismOwnershipTests.TamperedAppliedValues;
var P:TPrismEnableProposal; F:TPrismPerformanceFlag;
begin
  P:=Sample; P.AppliedPerformanceGate:=False; Refuses(P,porAppliedValues);
  P:=Sample; P.AppliedEnvGate:=False; Refuses(P,porAppliedValues);
  P:=Sample; P.AppliedCommandsGate:=True; Refuses(P,porAppliedValues);
  for F:=Low(F) to High(F) do
  begin P:=Sample; P.AppliedPerformance[F]:=not P.AppliedPerformance[F]; Refuses(P,porAppliedValues); end;
end;
procedure TPrismOwnershipTests.TamperedBeforeValues;
var P:TPrismEnableProposal; F:TPrismPerformanceFlag; I:Integer;
begin
  for F:=Low(F) to High(F) do
  begin
    P:=Sample; P.BeforeSnapshot.Performance[F].Value:=not P.BeforeSnapshot.Performance[F].Value; Refuses(P,porBeforeSnapshot);
    P:=Sample; P.BeforeSnapshot.Performance[F].Source:=pesInstance; Refuses(P,porBeforeSnapshot);
    for I:=0 to 6 do
    begin
      P:=Sample; AlterValue(P.BeforeSnapshot.Performance[F].GlobalRaw,I); Refuses(P,porBeforeSnapshot);
      P:=Sample; AlterValue(P.BeforeSnapshot.Performance[F].InstanceRaw,I); Refuses(P,porBeforeSnapshot);
    end;
  end;
  P:=Sample; P.BeforeSnapshot.AmbientEnvironmentVerified:=True; Refuses(P,porBeforeSnapshot);
  P:=Sample; P.BeforeSnapshot.Env.Source:=pesInstance; Refuses(P,porBeforeSnapshot);
  P:=Sample; P.BeforeSnapshot.Wrapper.Source:=pesInstance; Refuses(P,porBeforeSnapshot);
  P:=Sample; P.BeforeSnapshot.Wrapper.Value:='secret'; Refuses(P,porBeforeSnapshot);
  for I:=0 to 6 do
  begin
    P:=Sample; AlterValue(P.BeforeSnapshot.Env.GlobalRaw,I); Refuses(P,porBeforeSnapshot);
    P:=Sample; AlterValue(P.BeforeSnapshot.Env.InstanceRaw,I); Refuses(P,porBeforeSnapshot);
    P:=Sample; AlterValue(P.BeforeSnapshot.Wrapper.GlobalRaw,I); Refuses(P,porBeforeSnapshot);
    P:=Sample; AlterValue(P.BeforeSnapshot.Wrapper.InstanceRaw,I); Refuses(P,porBeforeSnapshot);
  end;
end;
procedure TPrismOwnershipTests.TamperedGates;
var P:TPrismEnableProposal; G:TPrismGateSnapshot; I,J:Integer;
begin
  for I:=0 to 2 do for J:=0 to 9 do
  begin
    P:=Sample;
    case I of 0:G:=P.BeforeSnapshot.PerformanceGate; 1:G:=P.BeforeSnapshot.EnvGate; 2:G:=P.BeforeSnapshot.CommandsGate; end;
    case J of
      0..6:AlterValue(G.Raw,J);
      7:G.Key:=pmkConfigVersion;
      8:G.Source:=pesDefault;
      9:G.Value:=not G.Value;
    end;
    case I of 0:P.BeforeSnapshot.PerformanceGate:=G; 1:P.BeforeSnapshot.EnvGate:=G; 2:P.BeforeSnapshot.CommandsGate:=G; end;
    Refuses(P,porBeforeSnapshot);
  end;
end;
procedure TPrismOwnershipTests.TamperedDocumentIndexes;
var P:TPrismEnableProposal; D:TPrismDocument; K:TPrismManagedKey; I,J:Integer;
begin
  for I:=0 to 2 do
  begin
    for K:=Low(K) to High(K) do for J:=0 to 6 do
    begin
      P:=Sample;
      case I of 0:D:=P.BeforeSnapshot.GlobalDocument; 1:D:=P.BeforeSnapshot.InstanceDocument; 2:D:=P.ProposedInstanceDocument; end;
      AlterValue(D.Managed[K],J);
      case I of 0:P.BeforeSnapshot.GlobalDocument:=D; 1:P.BeforeSnapshot.InstanceDocument:=D; 2:P.ProposedInstanceDocument:=D; end;
      if I=2 then Refuses(P,porAppliedDocument) else Refuses(P,porBeforeSnapshot);
    end;
    for J:=0 to 1 do
    begin
      P:=Sample;
      case I of 0:D:=P.BeforeSnapshot.GlobalDocument; 1:D:=P.BeforeSnapshot.InstanceDocument; 2:D:=P.ProposedInstanceDocument; end;
      if J=0 then Inc(D.GeneralInsertOffset) else D.GeneralLineEnding:=#13#10;
      case I of 0:P.BeforeSnapshot.GlobalDocument:=D; 1:P.BeforeSnapshot.InstanceDocument:=D; 2:P.ProposedInstanceDocument:=D; end;
      if I=2 then Refuses(P,porAppliedDocument) else Refuses(P,porBeforeSnapshot);
    end;
  end;
  P:=Sample; P.ProposedInstanceDocument.Bytes+='secret'; Refuses(P,porAppliedDocument);
end;
procedure TPrismOwnershipTests.TamperedMaps;
var P:TPrismEnableProposal; M:TPrismEnvMap; V:TPrismEnvEntry; I,J:Integer;
begin
  for I:=0 to 1 do for J:=0 to 4 do
  begin
    P:=Sample;
    if I=0 then M:=Copy(P.BeforeSnapshot.Env.Entries) else M:=Copy(P.AppliedEnv);
    case J of
      0:M[0].Key:='SECRET';
      1:M[0].Value:='SECRET';
      2:begin V:=M[0]; M[0]:=M[1]; M[1]:=V; end;
      3:SetLength(M,Length(M)-1);
      4:begin SetLength(M,Length(M)+1); M[High(M)].Key:='NEW'; end;
    end;
    if I=0 then begin P.BeforeSnapshot.Env.Entries:=M; Refuses(P,porBeforeSnapshot); end
    else begin P.AppliedEnv:=M; Refuses(P,porAppliedValues); end;
  end;
end;
procedure TPrismOwnershipTests.TamperedInputsAndBounds;
var P:TPrismEnableProposal;
begin
  P:=Sample; P.Instance.DataRoot:='/other/root'; Refuses(P,porReconstruction);
  P:=Sample; P.Instance.StableKey:='wrong'; Refuses(P,porReconstruction);
  P:=Sample; P.Instance.ConfigPath:='/external/other/instance.cfg'; Refuses(P,porReconstruction);
  P:=Sample; P.HostDataDir+='/other'; Refuses(P,porReconstruction);
  P:=Sample; P.Selector+='/other'; Refuses(P,porReconstruction);
  P:=Sample; P.BeforeSnapshot.GlobalDocument.Bytes:='[General]'#10'ConfigVersion=1.2'#10; Refuses(P,porReconstruction);
  P:=Sample; P.BeforeSnapshot.InstanceDocument.Bytes:=H+'OverrideEnv=true'#10'Env='#10; Refuses(P,porReconstruction);
  P:=Sample; P.BeforeSnapshot.InstanceDocument.Bytes:=H+StringOfChar('x',PrismDocumentMaxBytes); Refuses(P,porReconstruction);
  P:=Sample; P.BeforeSnapshot.InstanceDocument.Bytes+= '; external change'#10; Refuses(P,porBeforeSnapshot);
end;
procedure TPrismOwnershipTests.CanonicalCopyAndNoMutation;
var P,C:TPrismEnableProposal; R:TPrismOwnershipReason; Before,Applied,Value:RawByteString;
begin
  P:=Sample; Before:=P.BeforeSnapshot.InstanceDocument.Bytes; Applied:=P.ProposedInstanceDocument.Bytes;
  Value:=P.AppliedEnv[0].Value;
  AssertTrue(ValidatePrismEnableRecord(P,C,R));
  C.AppliedEnv[0].Value:='changed output'; C.BeforeSnapshot.Env.Entries[0].Value:='changed output';
  C.ProposedInstanceDocument.Bytes:='changed output';
  AssertEquals(Value,P.AppliedEnv[0].Value); AssertEquals(Value,P.BeforeSnapshot.Env.Entries[0].Value);
  AssertEquals(Before,P.BeforeSnapshot.InstanceDocument.Bytes); AssertEquals(Applied,P.ProposedInstanceDocument.Bytes);
  Valid(P); Valid(P);
end;
initialization RegisterTest(TPrismOwnershipTests);
end.
