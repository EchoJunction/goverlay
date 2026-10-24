unit prism_plan_test_cases;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, SHA1, fpcunit, testregistry, prismprovider, gamecontext,
  prismdocument, prismsettings, prismenv, prismsnapshot, prismplan;
type
  TPrismPlanTests = class(TTestCase)
  private
    function Instance(const Folder: string = 'A'): TPrismInstance;
    function Selector(const I: TPrismInstance): string;
    function RawSnapshot(const G,L: RawByteString): TPrismSettingsSnapshot;
    function Plan(const G,L: RawByteString): TPrismEnableProposal;
    procedure Refuses(const I: TPrismInstance; const Host,Target: string;
      const S: TPrismSettingsSnapshot; Status: TPrismAssessmentStatus;
      Reason: TPrismEnableReason; AR: TPrismAssessmentReason = psrNone);
  published
    procedure DefaultsFreezeAndProvenance;
    procedure PreserveAllInheritedSiblings;
    procedure EnabledGateChangesOnlyMangoHud;
    procedure AlreadyEnabledAdoption;
    procedure EnvGateAndOrder;
    procedure DormantAndAbsentFallback;
    procedure RawBytesAndTerminators;
    procedure ReassessForgedSnapshot;
    procedure IdentityAndSelectorRefusals;
    procedure CollisionRefusals;
    procedure BoundsAndClearedOutput;
    procedure SameJavaSeparateSelectors;
  end;
implementation
const H: RawByteString = '[General]'#10'ConfigVersion=1.3'#10;
  Host = '/synthetic/日本語 data';
function TPrismPlanTests.Instance(const Folder: string): TPrismInstance;
begin
  Result := Default(TPrismInstance); Result.DataRoot := '/synthetic/Prism';
  Result.Folder := Folder; Result.ConfigPath := '/external/instances/'+Folder+'/instance.cfg';
  Result.UUID := '0123456789abcdef0123456789abcdef';
  if Folder='B' then Result.UUID := '1123456789abcdef0123456789abcdef';
  Result.InstallationKey := 'prism-root-'+SHA1Print(SHA1String(Result.DataRoot));
  Result.StableKey := 'prism-'+SHA1Print(SHA1String(Result.DataRoot+#0+'uuid:'+Result.UUID));
end;
function TPrismPlanTests.Selector(const I: TPrismInstance): string;
var C: TActiveProfileContext;
begin AssertTrue(PrismProfileContext(I,Host,C)); Result := C.ConfigDir+'MangoHud.conf'; end;
function TPrismPlanTests.RawSnapshot(const G,L: RawByteString): TPrismSettingsSnapshot;
begin
  Result := Default(TPrismSettingsSnapshot);
  Result.GlobalDocument.Bytes := G; Result.InstanceDocument.Bytes := L;
end;
function TPrismPlanTests.Plan(const G,L: RawByteString): TPrismEnableProposal;
var S: TPrismSettingsSnapshot; I: TPrismInstance; R: TPrismEnableReason; AR: TPrismAssessmentReason;
begin
  I := Instance; S := RawSnapshot(H+G,H+L);
  AssertEquals(Ord(psaReady),Ord(PlanPrismEnable(I,Host,Selector(I),S,Result,R,AR)));
  AssertEquals(Ord(perNone),Ord(R)); AssertEquals(Ord(psrNone),Ord(AR));
  AssertEquals(H+G,S.GlobalDocument.Bytes); AssertEquals(H+L,S.InstanceDocument.Bytes);
  AssertEquals(H+G,Result.BeforeSnapshot.GlobalDocument.Bytes);
  AssertEquals(H+L,Result.BeforeSnapshot.InstanceDocument.Bytes);
  AssertEquals(Selector(I),Result.Selector); AssertEquals(I.StableKey,Result.Instance.StableKey);
  AssertFalse(Result.BeforeSnapshot.AmbientEnvironmentVerified);
end;
procedure TPrismPlanTests.Refuses(const I: TPrismInstance; const Host,Target: string;
  const S: TPrismSettingsSnapshot; Status: TPrismAssessmentStatus;
  Reason: TPrismEnableReason; AR: TPrismAssessmentReason);
var P: TPrismEnableProposal; R: TPrismEnableReason; A: TPrismAssessmentReason;
  K: TPrismManagedKey; F: TPrismPerformanceFlag; G,L: RawByteString;
begin
  P := Plan('',''); G := S.GlobalDocument.Bytes; L := S.InstanceDocument.Bytes;
  AssertEquals(Ord(Status),Ord(PlanPrismEnable(I,Host,Target,S,P,R,A)));
  AssertEquals(Ord(Reason),Ord(R)); AssertEquals(Ord(AR),Ord(A));
  AssertEquals(G,S.GlobalDocument.Bytes); AssertEquals(L,S.InstanceDocument.Bytes);
  AssertEquals('',P.Instance.StableKey); AssertEquals('',P.Selector); AssertEquals('',P.HostDataDir);
  AssertEquals('',P.BeforeSnapshot.GlobalDocument.Bytes); AssertEquals('',P.BeforeSnapshot.InstanceDocument.Bytes);
  AssertEquals('',P.ProposedInstanceDocument.Bytes); AssertEquals(0,Length(P.AppliedEnv));
  AssertFalse(P.OwnsSelector); AssertFalse(P.OwnsMangoHudEnable); AssertFalse(P.SelectorOnlyAdoption);
  AssertFalse(P.PerformanceInheritanceFreeze); AssertFalse(P.EnvInheritanceFreeze);
  AssertFalse(P.AppliedPerformanceGate); AssertFalse(P.AppliedEnvGate); AssertFalse(P.AppliedCommandsGate);
  for K := Low(K) to High(K) do
  begin AssertFalse(P.Touched[K]); AssertFalse(P.Owned[K]); AssertFalse(P.ProposedInstanceDocument.Managed[K].Present); end;
  for F := Low(F) to High(F) do AssertFalse(P.AppliedPerformance[F]);
end;
procedure TPrismPlanTests.DefaultsFreezeAndProvenance;
var P: TPrismEnableProposal; F: TPrismPerformanceFlag;
begin
  P := Plan('',''); AssertTrue(P.OwnsSelector); AssertTrue(P.OwnsMangoHudEnable);
  AssertFalse(P.SelectorOnlyAdoption); AssertTrue(P.PerformanceInheritanceFreeze); AssertTrue(P.EnvInheritanceFreeze);
  AssertTrue(P.AppliedPerformanceGate); AssertTrue(P.AppliedEnvGate); AssertFalse(P.AppliedCommandsGate);
  for F := Low(F) to High(F) do
  begin
    AssertTrue(P.Touched[PrismPerformanceManagedKeys[F]]); AssertTrue(P.Owned[PrismPerformanceManagedKeys[F]]);
    AssertEquals(F=ppfMangoHud,P.AppliedPerformance[F]);
    AssertEquals(Ord(pesDefault),Ord(P.BeforeSnapshot.Performance[F].Source));
  end;
  AssertTrue(P.Owned[pmkOverridePerformance]); AssertTrue(P.Owned[pmkOverrideEnv]); AssertTrue(P.Owned[pmkEnv]);
  AssertFalse(P.Touched[pmkConfigVersion]); AssertFalse(P.Touched[pmkOverrideCommands]);
  AssertEquals(1,Length(P.AppliedEnv)); AssertEquals('MANGOHUD_CONFIGFILE',string(P.AppliedEnv[0].Key));
  AssertEquals(P.Selector,string(P.AppliedEnv[0].Value));
end;
procedure TPrismPlanTests.PreserveAllInheritedSiblings;
var P: TPrismEnableProposal;
begin
  P := Plan('EnableMangoHud=false'#10'UseDiscreteGpu=true'#10'UseZink=false'#10'EnableFeralGamemode=true'#10,
    'OverridePerformance=false'#10'UseDiscreteGpu=false'#10'UseZink=true'#10'EnableFeralGamemode=false'#10);
  AssertTrue(P.AppliedPerformance[ppfDiscreteGpu]); AssertFalse(P.AppliedPerformance[ppfZink]);
  AssertTrue(P.AppliedPerformance[ppfFeralGamemode]); AssertTrue(P.PerformanceInheritanceFreeze);
  AssertEquals('false',P.BeforeSnapshot.Performance[ppfDiscreteGpu].InstanceRaw.RawScalar);
  AssertEquals('true',P.ProposedInstanceDocument.Managed[pmkUseDiscreteGpu].RawScalar);
  AssertEquals(Ord(pesGlobal),Ord(P.BeforeSnapshot.Performance[ppfDiscreteGpu].Source));
end;
procedure TPrismPlanTests.EnabledGateChangesOnlyMangoHud;
var P: TPrismEnableProposal; F: TPrismPerformanceFlag;
begin
  P := Plan('UseZink=true'#10,'OverridePerformance=true'#10'EnableMangoHud=false'#10'UseDiscreteGpu=false'#10);
  AssertFalse(P.PerformanceInheritanceFreeze); AssertTrue(P.OwnsMangoHudEnable);
  AssertFalse(P.Touched[pmkOverridePerformance]); AssertTrue(P.Touched[pmkEnableMangoHud]);
  for F := ppfDiscreteGpu to ppfFeralGamemode do AssertFalse(P.Touched[PrismPerformanceManagedKeys[F]]);
  AssertTrue(P.AppliedPerformance[ppfZink]); AssertFalse(P.ProposedInstanceDocument.Managed[pmkUseZink].Present);
end;
procedure TPrismPlanTests.AlreadyEnabledAdoption;
var P: TPrismEnableProposal; F: TPrismPerformanceFlag;
begin
  P := Plan('EnableMangoHud=true'#10,'OverridePerformance=false'#10'EnableMangoHud=invalid dormant'#10);
  AssertTrue(P.SelectorOnlyAdoption); AssertFalse(P.OwnsMangoHudEnable); AssertFalse(P.PerformanceInheritanceFreeze);
  AssertFalse(P.AppliedPerformanceGate); AssertFalse(P.Touched[pmkOverridePerformance]);
  for F := Low(F) to High(F) do AssertFalse(P.Touched[PrismPerformanceManagedKeys[F]]);
  AssertEquals('invalid dormant',P.ProposedInstanceDocument.Managed[pmkEnableMangoHud].RawScalar);
  P := Plan('','OverridePerformance=true'#10'EnableMangoHud="true"'#10);
  AssertTrue(P.SelectorOnlyAdoption); AssertFalse(P.Owned[pmkEnableMangoHud]);
  AssertEquals('"true"',P.ProposedInstanceDocument.Managed[pmkEnableMangoHud].RawScalar);
end;
procedure TPrismPlanTests.EnvGateAndOrder;
var P: TPrismEnableProposal; M: TPrismEnvMap; E: TPrismEnvError; Raw: RawByteString;
begin
  SetLength(M,2); M[0].Key:='FIRST'; M[0].Value:=' 日本語 😀 '+#0#10;
  M[1].Key:='KEEP'; M[1].Value:='"quoted" \ value'; AssertTrue(EncodePrismEnv(M,Raw,E));
  P := Plan('Env='+Raw+#10,'OverrideEnv=false'#10'Env=invalid dormant'#10);
  AssertTrue(P.EnvInheritanceFreeze); AssertEquals(3,Length(P.AppliedEnv));
  AssertEquals(M[0].Key,P.AppliedEnv[0].Key); AssertEquals(M[0].Value,P.AppliedEnv[0].Value);
  AssertEquals(M[1].Value,P.AppliedEnv[1].Value); AssertEquals(2,Length(P.BeforeSnapshot.Env.Entries));
  AssertEquals('invalid dormant',P.BeforeSnapshot.Env.InstanceRaw.RawScalar);
  P := Plan('Env=unused invalid'#10,'OverrideEnv=true'#10'Env='+Raw+#10);
  AssertFalse(P.EnvInheritanceFreeze); AssertFalse(P.Touched[pmkOverrideEnv]);
  AssertEquals(M[1].Key,P.AppliedEnv[1].Key); AssertEquals(M[0].Value,P.AppliedEnv[0].Value);
  P := Plan('Env='+Raw+#10,'OverrideEnv=true'#10);
  AssertFalse(P.Touched[pmkOverrideEnv]); AssertFalse(P.Owned[pmkOverrideEnv]);
  AssertTrue(P.EnvInheritanceFreeze); AssertFalse(P.BeforeSnapshot.Env.InstanceRaw.Present);
  AssertEquals(Ord(pesGlobal),Ord(P.BeforeSnapshot.Env.Source));
  AssertEquals(M[0].Value,P.AppliedEnv[0].Value); AssertEquals(3,Length(P.AppliedEnv));
  P := Plan('','OverrideEnv=true'#10);
  AssertTrue(P.EnvInheritanceFreeze); AssertFalse(P.BeforeSnapshot.Env.InstanceRaw.Present);
  AssertFalse(P.Touched[pmkOverrideEnv]); AssertFalse(P.Owned[pmkOverrideEnv]);
  AssertEquals(Ord(pesDefault),Ord(P.BeforeSnapshot.Env.Source)); AssertEquals(1,Length(P.AppliedEnv));
end;
procedure TPrismPlanTests.DormantAndAbsentFallback;
var P: TPrismEnableProposal;
begin
  P := Plan('UseDiscreteGpu=true'#10,'OverridePerformance=true'#10'OverrideEnv=true'#10);
  AssertEquals(Ord(pesGlobal),Ord(P.BeforeSnapshot.Performance[ppfDiscreteGpu].Source));
  AssertFalse(P.Touched[pmkUseDiscreteGpu]); AssertTrue(P.AppliedPerformance[ppfDiscreteGpu]);
  P := Plan('','EnableMangoHud='#10'Env='#10'WrapperCommand=opaque dormant'#10);
  AssertTrue(P.BeforeSnapshot.Env.InstanceRaw.Present); AssertEquals('',P.BeforeSnapshot.Env.InstanceRaw.RawScalar);
  AssertEquals('opaque dormant',P.ProposedInstanceDocument.Managed[pmkWrapperCommand].RawScalar);
end;
procedure TPrismPlanTests.RawBytesAndTerminators;
var I: TPrismInstance; S: TPrismSettingsSnapshot; P: TPrismEnableProposal;
  R: TPrismEnableReason; A: TPrismAssessmentReason; L: RawByteString;
begin
  I := Instance; L := '[General]'#13#10'ConfigVersion = 1.3'#13#10'; keep comment'#13#10+
    'OverridePerformance = true'#13#10'EnableMangoHud = false  '#13#10+
    'JavaPath=/same/java'#13#10'[Other]'#13#10'Env=opaque final';
  S := RawSnapshot(H,L);
  AssertEquals(Ord(psaReady),Ord(PlanPrismEnable(I,Host,Selector(I),S,P,R,A)));
  AssertTrue(Pos('EnableMangoHud = true  '#13#10,P.ProposedInstanceDocument.Bytes)>0);
  AssertTrue(Pos('; keep comment'#13#10,P.ProposedInstanceDocument.Bytes)>0);
  AssertTrue(Pos('JavaPath=/same/java'#13#10,P.ProposedInstanceDocument.Bytes)>0);
  AssertTrue(Pos('[Other]'#13#10'Env=opaque final',P.ProposedInstanceDocument.Bytes)>0);
  AssertEquals('l',Copy(P.ProposedInstanceDocument.Bytes,Length(P.ProposedInstanceDocument.Bytes),1));
end;
procedure TPrismPlanTests.ReassessForgedSnapshot;
var S: TPrismSettingsSnapshot; I: TPrismInstance; P: TPrismEnableProposal;
  R: TPrismEnableReason; A: TPrismAssessmentReason;
begin
  I := Instance; S := RawSnapshot(H,H);
  S.Performance[ppfMangoHud].Value := True; S.EnvGate.Value := True;
  SetLength(S.Env.Entries,1); S.Env.Entries[0].Key:='MANGOHUD_CONFIGFILE';
  S.InstanceDocument.Managed[pmkEnv].Present := True;
  AssertEquals(Ord(psaReady),Ord(PlanPrismEnable(I,Host,Selector(I),S,P,R,A)));
  AssertTrue(P.OwnsMangoHudEnable); AssertTrue(P.EnvInheritanceFreeze);
  AssertEquals(0,Length(P.BeforeSnapshot.Env.Entries)); AssertFalse(P.BeforeSnapshot.InstanceDocument.Managed[pmkEnv].Present);
  S := RawSnapshot(H,H+'OverrideEnv=true'#10'Env='#10);
  Refuses(I,Host,Selector(I),S,psaUnsupported,perAssessment,psrEnvValue);
end;
procedure TPrismPlanTests.IdentityAndSelectorRefusals;
var I,J: TPrismInstance; S: TPrismSettingsSnapshot; P: TPrismEnableProposal;
  R: TPrismEnableReason; A: TPrismAssessmentReason;
begin
  I := Instance; S := RawSnapshot(H,H);
  Refuses(I,Host,Selector(I)+'/../MangoHud.conf',S,psaUnsupported,perSelector);
  Refuses(I,Host,'/synthetic/wrong/MangoHud.conf',S,psaUnsupported,perSelector);
  Refuses(I,Host,'relative',S,psaUnsupported,perSelector);
  Refuses(I,Host+'/',Selector(I),S,psaUnsupported,perIdentity);
  J:=I; J.StableKey:='prism-'+StringOfChar('0',40); Refuses(J,Host,Selector(I),S,psaUnsupported,perIdentity);
  J:=I; J.InstallationKey:='wrong'; Refuses(J,Host,Selector(I),S,psaUnsupported,perIdentity);
  J:=I; J.ConfigPath:='/external/instances/other/instance.cfg'; Refuses(J,Host,Selector(I),S,psaUnsupported,perIdentity);
  J:=I; J.UsesFolderIdentity:=True; Refuses(J,Host,Selector(I),S,psaUnsupported,perIdentity);
  J:=I; J.UUID:='INVALID'; Refuses(J,Host,Selector(I),S,psaUnsupported,perIdentity);
  J:=I; J.UUID:=''; J.UsesFolderIdentity:=True;
  J.StableKey:='prism-'+SHA1Print(SHA1String(J.DataRoot+#0+'folder:/external/instances/A'));
  AssertEquals(Ord(psaReady),Ord(PlanPrismEnable(J,Host,Selector(J),S,P,R,A)));
  AssertTrue(P.Instance.UsesFolderIdentity);
  { Success proves folder identity and external InstanceDir are accepted. }
  I:=J;
  Refuses(I,Host,Selector(I),RawSnapshot('[General]'#10,H),psaUnsupported,perAssessment,psrGlobalDocument);
end;
procedure TPrismPlanTests.CollisionRefusals;
var I: TPrismInstance; M: TPrismEnvMap; E: TPrismEnvError; Raw: RawByteString;
begin
  I:=Instance; SetLength(M,1); M[0].Key:='MANGOHUD_CONFIGFILE'; M[0].Value:=UTF8String(Selector(I));
  AssertTrue(EncodePrismEnv(M,Raw,E));
  Refuses(I,Host,Selector(I),RawSnapshot(H+'Env='+Raw+#10,H),psaConflict,perAssessment,psrMangoHudSelector);
  M[0].Key:='MANGOHUD_CONFIG'; M[0].Value:='secret'; AssertTrue(EncodePrismEnv(M,Raw,E));
  Refuses(I,Host,Selector(I),RawSnapshot(H+'Env='+Raw+#10,H),psaConflict,perAssessment,psrMangoHudConfig);
  M[0].Key:='LD_PRELOAD'; AssertTrue(EncodePrismEnv(M,Raw,E));
  Refuses(I,Host,Selector(I),RawSnapshot(H+'Env='+Raw+#10,H),psaUnsupported,perAssessment,psrPreload);
  Refuses(I,Host,Selector(I),RawSnapshot(H+'WrapperCommand=secret'#10,H),psaUnsupported,perAssessment,psrWrapperCommand);
  Refuses(I,Host,Selector(I),RawSnapshot(H,H+'OverrideCommands=false'#10'OverrideLaunchCmd=true'#10),psaUnsupported,perAssessment,psrCommandsAliases);
end;
procedure TPrismPlanTests.BoundsAndClearedOutput;
var I: TPrismInstance; M: TPrismEnvMap; E: TPrismEnvError; Raw: RawByteString; N: Integer;
begin
  I:=Instance; SetLength(M,PrismEnvMaxEntries);
  for N:=0 to High(M) do begin M[N].Key:='K'+IntToStr(N); M[N].Value:=''; end;
  AssertTrue(EncodePrismEnv(M,Raw,E));
  Refuses(I,Host,Selector(I),RawSnapshot(H+'Env='+Raw+#10,H),psaUnsupported,perEncoding);
  Refuses(I,Host,Selector(I),RawSnapshot(H,H+'OverridePerformance=true'#10'EnableMangoHud='#10),psaUnsupported,perAssessment,psrPerformanceValue);
  Refuses(I,Host,Selector(I),RawSnapshot(H,H+';'+StringOfChar('x',PrismDocumentMaxBytes-Length(H)-1)),psaUnsupported,perEdit);
end;
procedure TPrismPlanTests.SameJavaSeparateSelectors;
var I,J: TPrismInstance; S: TPrismSettingsSnapshot; P,Q: TPrismEnableProposal;
  R: TPrismEnableReason; A: TPrismAssessmentReason;
begin
  I:=Instance('A'); J:=Instance('B'); S:=RawSnapshot(H,H+'JavaPath=/same/java'#10);
  AssertEquals(Ord(psaReady),Ord(PlanPrismEnable(I,Host,Selector(I),S,P,R,A)));
  AssertEquals(Ord(psaReady),Ord(PlanPrismEnable(J,Host,Selector(J),S,Q,R,A)));
  AssertTrue(P.Selector<>Q.Selector); AssertTrue(P.ProposedInstanceDocument.Bytes<>Q.ProposedInstanceDocument.Bytes);
  AssertTrue(Pos('JavaPath=/same/java'#10,P.ProposedInstanceDocument.Bytes)>0);
  AssertTrue(Pos('JavaPath=/same/java'#10,Q.ProposedInstanceDocument.Bytes)>0);
  AssertEquals(S.InstanceDocument.Bytes,P.BeforeSnapshot.InstanceDocument.Bytes);
end;
initialization RegisterTest(TPrismPlanTests);
end.
