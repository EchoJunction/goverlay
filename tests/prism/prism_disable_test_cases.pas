unit prism_disable_test_cases;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,SHA1,fpcunit,testregistry,prismprovider,gamecontext,prismdocument,
  prismsettings,prismenv,prismsnapshot,prismplan,prismdisable;
type
  TPrismDisableTests=class(TTestCase)
  private
    function Enable(const G,L:RawByteString; const Folder:string='A'):TPrismEnableProposal;
    function Put(const Bytes,Key,Raw:RawByteString):RawByteString;
    function Delete(const Bytes,Key:RawByteString):RawByteString;
    function Env(const Bytes:RawByteString):TPrismEnvMap;
    function PutEnv(const Bytes:RawByteString; const M:TPrismEnvMap):RawByteString;
    function Disable(const P:TPrismEnableProposal; const G,L:RawByteString):TPrismDisableProposal;
    procedure Refuses(const P:TPrismEnableProposal; const G,L:RawByteString;
      Status:TPrismDisableStatus; Reason:TPrismDisableReason);
  published
    procedure ExactBeforeRoundtrips;
    procedure NoChangesAndMissingSelector;
    procedure EnvInheritedAddAndModify;
    procedure EnvLocalReorderAndDelete;
    procedure EnvAbsentUnderTrueGate;
    procedure ForeignConfigPreloadAndWrapper;
    procedure PerformanceResidualGroup;
    procedure PerformancePresenceAndUserEnable;
    procedure AlreadyEnabledAdoption;
    procedure CurrentGlobalDrift;
    procedure UnknownEditsAndEOFFormatting;
    procedure ChangedGatesAndMalformedValues;
    procedure OwnershipAndDocumentRefusals;
    procedure SameJavaABIsolation;
  end;
implementation
const H:RawByteString='[General]'#10'ConfigVersion=1.3'#10;
function TPrismDisableTests.Enable(const G,L:RawByteString; const Folder:string):TPrismEnableProposal;
var I:TPrismInstance; C:TActiveProfileContext; S:TPrismSettingsSnapshot;
  R:TPrismEnableReason; A:TPrismAssessmentReason;
begin
  I:=Default(TPrismInstance); I.DataRoot:='/synthetic/Prism'; I.Folder:=Folder;
  I.ConfigPath:='/external/instances/'+Folder+'/instance.cfg'; I.UUID:=StringOfChar('a',32);
  if Folder='B' then I.UUID:=StringOfChar('b',32);
  I.InstallationKey:='prism-root-'+SHA1Print(SHA1String(I.DataRoot));
  I.StableKey:='prism-'+SHA1Print(SHA1String(I.DataRoot+#0+'uuid:'+I.UUID));
  AssertTrue(PrismProfileContext(I,'/synthetic/日本語',C));
  S:=Default(TPrismSettingsSnapshot); S.GlobalDocument.Bytes:=G; S.InstanceDocument.Bytes:=L;
  AssertEquals(Ord(psaReady),Ord(PlanPrismEnable(I,'/synthetic/日本語',C.ConfigDir+'MangoHud.conf',S,Result,R,A)));
end;
function TPrismDisableTests.Put(const Bytes,Key,Raw:RawByteString):RawByteString;
var D,P:TPrismDocument; E:TPrismDocumentError; EE:TPrismDocumentEditError;
  Edits:array[0..0] of TPrismManagedEdit;
begin
  AssertTrue(IndexPrismDocument(Bytes,D,E)); Edits[0].KeyName:=Key; Edits[0].RawScalar:=Raw;
  AssertTrue(EditPrismDocument(D,Edits,P,EE)); Result:=P.Bytes;
end;
function TPrismDisableTests.Delete(const Bytes,Key:RawByteString):RawByteString;
var D,P:TPrismDocument; E:TPrismDocumentError; EE:TPrismDocumentEditError;
begin
  AssertTrue(IndexPrismDocument(Bytes,D,E)); AssertTrue(RemovePrismManagedLines(D,[Key],P,EE)); Result:=P.Bytes;
end;
function TPrismDisableTests.Env(const Bytes:RawByteString):TPrismEnvMap;
var D:TPrismDocument; E:TPrismDocumentError; EE:TPrismEnvError;
begin
  AssertTrue(IndexPrismDocument(Bytes,D,E));
  AssertTrue(DecodePrismEnv(D.Managed[pmkEnv].RawScalar,Result,EE));
end;
function TPrismDisableTests.PutEnv(const Bytes:RawByteString; const M:TPrismEnvMap):RawByteString;
var Raw:RawByteString; E:TPrismEnvError;
begin AssertTrue(EncodePrismEnv(M,Raw,E)); Result:=Put(Bytes,'Env',Raw); end;
function TPrismDisableTests.Disable(const P:TPrismEnableProposal; const G,L:RawByteString):TPrismDisableProposal;
var R:TPrismDisableReason;
begin
  AssertEquals(Ord(pdsReady),Ord(PlanPrismDisable(P,G,L,Result,R))); AssertEquals(Ord(pdrNone),Ord(R));
  AssertEquals(G,Result.ExpectedGlobalBytes); AssertEquals(L,Result.ExpectedInstanceBytes);
end;
procedure TPrismDisableTests.Refuses(const P:TPrismEnableProposal; const G,L:RawByteString;
  Status:TPrismDisableStatus; Reason:TPrismDisableReason);
var D:TPrismDisableProposal; R:TPrismDisableReason; K:TPrismManagedKey; Before,Applied:RawByteString;
begin
  D:=Disable(Enable(H,H),H,Enable(H,H).ProposedInstanceDocument.Bytes);
  Before:=P.BeforeSnapshot.InstanceDocument.Bytes; Applied:=P.ProposedInstanceDocument.Bytes;
  AssertEquals(Ord(Status),Ord(PlanPrismDisable(P,G,L,D,R))); AssertEquals(Ord(Reason),Ord(R));
  AssertEquals(Before,P.BeforeSnapshot.InstanceDocument.Bytes); AssertEquals(Applied,P.ProposedInstanceDocument.Bytes);
  AssertEquals('',D.ExpectedGlobalBytes); AssertEquals('',D.ExpectedInstanceBytes);
  AssertEquals('',D.ProposedInstanceDocument.Bytes); AssertFalse(D.ResidualEnv);
  AssertFalse(D.ResidualPerformance); AssertFalse(D.ResidualFormatting);
  AssertEquals(0,D.ProposedInstanceDocument.GeneralInsertOffset); AssertEquals('',D.ProposedInstanceDocument.GeneralLineEnding);
  for K:=Low(K) to High(K) do
  begin
    AssertFalse(D.ProposedInstanceDocument.Managed[K].Present);
    AssertEquals('',D.ProposedInstanceDocument.Managed[K].RawScalar);
    AssertEquals('',D.ProposedInstanceDocument.Managed[K].DecodedScalar);
    AssertEquals(0,D.ProposedInstanceDocument.Managed[K].LineSpan.Offset);
    AssertEquals(0,D.ProposedInstanceDocument.Managed[K].ValueSpan.Length);
  end;
end;
procedure TPrismDisableTests.ExactBeforeRoundtrips;
var P:TPrismEnableProposal; D:TPrismDisableProposal; I:Integer; Before,EOL:RawByteString;
begin
  for I:=0 to 2 do
  begin
    if I=1 then EOL:=#13#10 else EOL:=#10;
    Before:='[General]'+EOL+'ConfigVersion = 1.3'+EOL+'Unknown=keep';
    if I<2 then Before+=EOL;
    P:=Enable(H,Before); D:=Disable(P,H,P.ProposedInstanceDocument.Bytes);
    AssertEquals(Before,D.ProposedInstanceDocument.Bytes); AssertFalse(D.ResidualEnv);
    AssertFalse(D.ResidualPerformance); AssertFalse(D.ResidualFormatting);
  end;
  P:=Enable(H,H+'OverrideEnv=true'#10'Env={}'#10'OverridePerformance=true'#10'EnableMangoHud="false"'#10);
  D:=Disable(P,H,P.ProposedInstanceDocument.Bytes); AssertEquals(P.BeforeSnapshot.InstanceDocument.Bytes,D.ProposedInstanceDocument.Bytes);
end;
procedure TPrismDisableTests.NoChangesAndMissingSelector;
var P:TPrismEnableProposal; D:TPrismDisableProposal; R:TPrismDisableReason; L:RawByteString;
begin
  P:=Enable(H,H); D:=Disable(P,H,P.ProposedInstanceDocument.Bytes);
  { No input/out alias: raw byte argument is copied into a distinct variable. }
  L:=P.BeforeSnapshot.InstanceDocument.Bytes;
  AssertEquals(Ord(pdsNoChanges),Ord(PlanPrismDisable(P,H,L,D,R))); AssertEquals(L,D.ProposedInstanceDocument.Bytes);
  L:=Put(P.ProposedInstanceDocument.Bytes,'Env','{}'); Refuses(P,H,L,pdsConflict,pdrSelector);
  L:=Delete(P.ProposedInstanceDocument.Bytes,'Env'); Refuses(P,H,L,pdsConflict,pdrSelector);
end;
procedure TPrismDisableTests.EnvInheritedAddAndModify;
var P:TPrismEnableProposal; D:TPrismDisableProposal; M:TPrismEnvMap; G,L:RawByteString;
begin
  SetLength(M,1); M[0].Key:='GLOBAL'; M[0].Value:='日本語'+#0#10;
  G:=PutEnv(H,M); P:=Enable(G,H+'Env=invalid dormant'#10);
  M:=Env(P.ProposedInstanceDocument.Bytes); M[0].Value:='user modified';
  SetLength(M,Length(M)+1); M[High(M)].Key:='NEW'; M[High(M)].Value:='user';
  L:=PutEnv(P.ProposedInstanceDocument.Bytes,M); D:=Disable(P,G,L);
  AssertTrue(D.ResidualEnv); AssertEquals('true',D.ProposedInstanceDocument.Managed[pmkOverrideEnv].RawScalar);
  M:=Env(D.ProposedInstanceDocument.Bytes); AssertEquals(2,Length(M));
  AssertEquals('user modified',string(M[0].Value)); AssertEquals('NEW',string(M[1].Key));
  AssertEquals('invalid dormant',P.BeforeSnapshot.Env.InstanceRaw.RawScalar);
end;
procedure TPrismDisableTests.EnvLocalReorderAndDelete;
var P:TPrismEnableProposal; D:TPrismDisableProposal; M:TPrismEnvMap; V:TPrismEnvEntry; L:RawByteString;
begin
  SetLength(M,2); M[0].Key:='ONE'; M[0].Value:='1'; M[1].Key:='TWO'; M[1].Value:='2';
  L:=PutEnv(H+'OverrideEnv=true'#10,M); P:=Enable(H,L); M:=Env(P.ProposedInstanceDocument.Bytes);
  V:=M[0]; M[0]:=M[1]; M[1]:=V; D:=Disable(P,H,PutEnv(P.ProposedInstanceDocument.Bytes,M));
  AssertFalse(D.ResidualEnv); M:=Env(D.ProposedInstanceDocument.Bytes);
  AssertEquals('TWO',string(M[0].Key)); AssertEquals('ONE',string(M[1].Key));
  M:=Env(P.ProposedInstanceDocument.Bytes); M[0]:=M[1]; M[1]:=M[2]; SetLength(M,2);
  D:=Disable(P,H,PutEnv(P.ProposedInstanceDocument.Bytes,M)); M:=Env(D.ProposedInstanceDocument.Bytes);
  AssertFalse(D.ResidualEnv); AssertEquals(1,Length(M)); AssertEquals('TWO',string(M[0].Key));
end;
procedure TPrismDisableTests.EnvAbsentUnderTrueGate;
var P:TPrismEnableProposal; D:TPrismDisableProposal; M:TPrismEnvMap;
begin
  P:=Enable(H+'Env={}'#10,H+'OverrideEnv=true'#10); AssertTrue(P.EnvInheritanceFreeze);
  D:=Disable(P,H+'Env={}'#10,P.ProposedInstanceDocument.Bytes);
  AssertFalse(D.ProposedInstanceDocument.Managed[pmkEnv].Present);
  AssertEquals('true',D.ProposedInstanceDocument.Managed[pmkOverrideEnv].RawScalar);
  M:=Env(P.ProposedInstanceDocument.Bytes); SetLength(M,2); M[1].Key:='NEW'; M[1].Value:='keep';
  D:=Disable(P,H,PutEnv(P.ProposedInstanceDocument.Bytes,M)); AssertTrue(D.ResidualEnv);
end;
procedure TPrismDisableTests.ForeignConfigPreloadAndWrapper;
var P:TPrismEnableProposal; D:TPrismDisableProposal; M:TPrismEnvMap; L:RawByteString;
begin
  P:=Enable(H,H); M:=Env(P.ProposedInstanceDocument.Bytes); SetLength(M,3);
  M[1].Key:='MANGOHUD_CONFIG'; M[1].Value:='foreign secret'; M[2].Key:='LD_PRELOAD'; M[2].Value:='foreign.so';
  L:=PutEnv(P.ProposedInstanceDocument.Bytes,M); L:=Put(L,'WrapperCommand','opaque user wrapper');
  D:=Disable(P,H,L); M:=Env(D.ProposedInstanceDocument.Bytes); AssertEquals(2,Length(M));
  AssertEquals('MANGOHUD_CONFIG',string(M[0].Key)); AssertEquals('LD_PRELOAD',string(M[1].Key));
  AssertEquals('opaque user wrapper',D.ProposedInstanceDocument.Managed[pmkWrapperCommand].RawScalar);
end;
procedure TPrismDisableTests.PerformanceResidualGroup;
var P:TPrismEnableProposal; D:TPrismDisableProposal; L:RawByteString;
begin
  P:=Enable(H+'UseDiscreteGpu=false'#10,H+'OverridePerformance=false'#10'UseDiscreteGpu=true'#10);
  L:=Put(P.ProposedInstanceDocument.Bytes,'UseZink','true'); D:=Disable(P,H+'UseDiscreteGpu=false'#10,L);
  AssertTrue(D.ResidualPerformance); AssertEquals('true',D.ProposedInstanceDocument.Managed[pmkOverridePerformance].RawScalar);
  AssertEquals('false',D.ProposedInstanceDocument.Managed[pmkUseDiscreteGpu].RawScalar);
  AssertEquals('true',D.ProposedInstanceDocument.Managed[pmkUseZink].RawScalar);
  AssertEquals('false',D.ProposedInstanceDocument.Managed[pmkEnableMangoHud].RawScalar);
end;
procedure TPrismDisableTests.PerformancePresenceAndUserEnable;
var P:TPrismEnableProposal; D:TPrismDisableProposal; L:RawByteString;
begin
  P:=Enable(H,H); L:=Delete(P.ProposedInstanceDocument.Bytes,'UseZink'); D:=Disable(P,H,L);
  AssertTrue(D.ResidualPerformance); AssertFalse(D.ProposedInstanceDocument.Managed[pmkUseZink].Present);
  P:=Enable(H,H+'OverridePerformance=true'#10'EnableMangoHud=false'#10);
  L:=Put(P.ProposedInstanceDocument.Bytes,'EnableMangoHud','false'); D:=Disable(P,H,L);
  AssertFalse(D.ResidualPerformance); AssertEquals('false',D.ProposedInstanceDocument.Managed[pmkEnableMangoHud].RawScalar);
  P:=Enable(H+'EnableMangoHud=false'#10,H+'OverridePerformance=true'#10);
  L:=Put(P.ProposedInstanceDocument.Bytes,'EnableMangoHud','false'); D:=Disable(P,H,L);
  AssertTrue(D.ResidualPerformance); AssertTrue(D.ProposedInstanceDocument.Managed[pmkEnableMangoHud].Present);
  P:=Enable(H,H+'OverridePerformance=true'#10'EnableMangoHud=false'#10);
  L:=Put(P.ProposedInstanceDocument.Bytes,'UseZink','invalid user sibling'); D:=Disable(P,H,L);
  AssertEquals('invalid user sibling',D.ProposedInstanceDocument.Managed[pmkUseZink].RawScalar);
  AssertEquals('false',D.ProposedInstanceDocument.Managed[pmkEnableMangoHud].RawScalar);
end;
procedure TPrismDisableTests.AlreadyEnabledAdoption;
var P:TPrismEnableProposal; D:TPrismDisableProposal; L:RawByteString;
begin
  P:=Enable(H+'EnableMangoHud=true'#10,H); AssertFalse(P.OwnsMangoHudEnable);
  L:=Put(P.ProposedInstanceDocument.Bytes,'EnableMangoHud','opaque dormant');
  L:=Put(L,'OverridePerformance','invalid user gate'); D:=Disable(P,H+'EnableMangoHud=true'#10,L);
  AssertEquals('invalid user gate',D.ProposedInstanceDocument.Managed[pmkOverridePerformance].RawScalar);
  AssertEquals('opaque dormant',D.ProposedInstanceDocument.Managed[pmkEnableMangoHud].RawScalar);
  AssertFalse(D.ResidualPerformance);
end;
procedure TPrismDisableTests.CurrentGlobalDrift;
var P:TPrismEnableProposal; D:TPrismDisableProposal; G,L:RawByteString; M:TPrismEnvMap;
begin
  P:=Enable(H,H); G:=H+'UseDiscreteGpu=true'#10'Env={}'#10;
  D:=Disable(P,G,P.ProposedInstanceDocument.Bytes); AssertEquals(H,D.ProposedInstanceDocument.Bytes);
  AssertEquals(G,D.ExpectedGlobalBytes);
  P:=Enable(H+'EnableMangoHud=false'#10,H+'OverridePerformance=true'#10);
  D:=Disable(P,H+'EnableMangoHud=true'#10,P.ProposedInstanceDocument.Bytes);
  AssertFalse(D.ProposedInstanceDocument.Managed[pmkEnableMangoHud].Present);
  P:=Enable(H,H);
  Refuses(P,H+'UseDiscreteGpu=invalid'#10,P.ProposedInstanceDocument.Bytes,pdsUnsupported,pdrInheritedValue);
  Refuses(P,H+'Env=invalid'#10,P.ProposedInstanceDocument.Bytes,pdsUnsupported,pdrInheritedValue);
  M:=Env(P.ProposedInstanceDocument.Bytes); SetLength(M,2); M[1].Key:='NEW'; M[1].Value:='keeps local map';
  L:=PutEnv(P.ProposedInstanceDocument.Bytes,M); L:=Put(L,'UseZink','true');
  D:=Disable(P,H+'Env=invalid'#10'UseDiscreteGpu=invalid'#10,L);
  AssertTrue(D.ResidualEnv); AssertTrue(D.ResidualPerformance);
end;
procedure TPrismDisableTests.UnknownEditsAndEOFFormatting;
var P:TPrismEnableProposal; D:TPrismDisableProposal; L,Before:RawByteString;
begin
  Before:='[General]'#10'ConfigVersion=1.3'; P:=Enable(H,Before);
  D:=Disable(P,H,P.ProposedInstanceDocument.Bytes); AssertEquals(Before,D.ProposedInstanceDocument.Bytes);
  L:=P.ProposedInstanceDocument.Bytes+#10'; external edit'; D:=Disable(P,H,L);
  AssertTrue(D.ResidualFormatting); AssertTrue(Pos('; external edit',D.ProposedInstanceDocument.Bytes)>0);
  AssertTrue(Pos('ConfigVersion=1.3'#10,D.ProposedInstanceDocument.Bytes)>0);
  P:=Enable(H,H+'JavaPath=/same/java'#10'[Other]'#10'Unknown=keep'#10);
  L:=P.ProposedInstanceDocument.Bytes+'New=external'#10; D:=Disable(P,H,L);
  AssertTrue(Pos('JavaPath=/same/java'#10,D.ProposedInstanceDocument.Bytes)>0);
  AssertTrue(Pos('[Other]'#10'Unknown=keep'#10'New=external'#10,D.ProposedInstanceDocument.Bytes)>0);
  AssertFalse(D.ResidualFormatting);
  { Replacements only did not insert an EOF separator, despite no final LF. }
  P:=Enable(H,H+'OverridePerformance=true'#10'EnableMangoHud=false'#10'OverrideEnv=true'#10'Env={}');
  L:=P.ProposedInstanceDocument.Bytes+#10'; external edit'; D:=Disable(P,H,L);
  AssertFalse(D.ResidualFormatting);
end;
procedure TPrismDisableTests.ChangedGatesAndMalformedValues;
var P:TPrismEnableProposal; L:RawByteString; M:TPrismEnvMap;
begin
  P:=Enable(H,H);
  Refuses(P,H,Put(P.ProposedInstanceDocument.Bytes,'OverrideEnv','false'),pdsConflict,pdrEnvGate);
  Refuses(P,H,Put(P.ProposedInstanceDocument.Bytes,'OverrideEnv','invalid'),pdsUnsupported,pdrEnvGate);
  Refuses(P,H,Put(P.ProposedInstanceDocument.Bytes,'OverridePerformance','false'),pdsConflict,pdrPerformanceGate);
  Refuses(P,H,Put(P.ProposedInstanceDocument.Bytes,'OverridePerformance','invalid'),pdsUnsupported,pdrPerformanceGate);
  Refuses(P,H,Put(P.ProposedInstanceDocument.Bytes,'Env',''),pdsUnsupported,pdrEnvValue);
  Refuses(P,H,Put(P.ProposedInstanceDocument.Bytes,'UseZink',''),pdsUnsupported,pdrPerformanceValue);
  M:=Env(P.ProposedInstanceDocument.Bytes); M[0].Value:='/foreign/selector';
  L:=PutEnv(P.ProposedInstanceDocument.Bytes,M); Refuses(P,H,L,pdsConflict,pdrSelector);
end;
procedure TPrismDisableTests.OwnershipAndDocumentRefusals;
var P:TPrismEnableProposal; L:RawByteString;
begin
  P:=Enable(H,H); L:=P.ProposedInstanceDocument.Bytes; P.OwnsSelector:=False;
  Refuses(P,H,L,pdsUnsupported,pdrOwnership);
  P:=Enable(H,H); Refuses(P,'[General]'#10,P.ProposedInstanceDocument.Bytes,pdsUnsupported,pdrGlobalDocument);
  Refuses(P,H,'[General]'#10'ConfigVersion=1.2'#10,pdsUnsupported,pdrInstanceDocument);
  Refuses(P,H,H+StringOfChar('x',PrismDocumentMaxBytes),pdsUnsupported,pdrInstanceDocument);
end;
procedure TPrismDisableTests.SameJavaABIsolation;
var A,B:TPrismEnableProposal; D:TPrismDisableProposal;
begin
  A:=Enable(H,H+'JavaPath=/same/java'#10,'A'); B:=Enable(H,H+'JavaPath=/same/java'#10,'B');
  AssertTrue(A.Selector<>B.Selector);
  Refuses(A,H,B.ProposedInstanceDocument.Bytes,pdsConflict,pdrSelector);
  D:=Disable(A,H,A.ProposedInstanceDocument.Bytes); AssertEquals(A.BeforeSnapshot.InstanceDocument.Bytes,D.ProposedInstanceDocument.Bytes);
  D:=Disable(B,H,B.ProposedInstanceDocument.Bytes); AssertEquals(B.BeforeSnapshot.InstanceDocument.Bytes,D.ProposedInstanceDocument.Bytes);
end;
initialization RegisterTest(TPrismDisableTests);
end.
