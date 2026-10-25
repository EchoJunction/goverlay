unit prism_performance_test_cases;
{$mode objfpc}{$H+}
interface
uses SysUtils, fpcunit, testregistry, prismdocument, prismsnapshot, prismperformance;
type
  TPrismPerformanceTests=class(TTestCase)
  private
    D:TPrismPerformanceDraft;
    P:TPrismPerformanceProposal;
    R:TPrismPerformanceDraftReason;
    procedure Ready(const G,I:RawByteString);
    procedure Refuses(const G,I:RawByteString; Reason:TPrismPerformanceDraftReason);
  protected
    procedure SetUp; override;
  published
    procedure KeepExactAndDefaults;
    procedure FreezeAllFourBeforeIntents;
    procedure AlreadyTrueOnlyRequested;
    procedure GlobalPreservesDormant;
    procedure InheritRemovesAndFallsBack;
    procedure ExplicitFalseEqualGlobal;
    procedure InactiveIntentRefused;
    procedure DormantAndUnusedMalformed;
    procedure NewlySelectedMalformedGlobal;
    procedure OpaqueBindingCollisionsPreserved;
    procedure EndingsAndUnknownSections;
    procedure StrictDocumentsAndBounds;
    procedure NoMutationAndDeterminism;
    procedure MangoHudGroupDisclosure;
    procedure GlobalDriftSelectedNow;
    procedure OutputExpansionLimit;
    procedure MixedTerminatorsPreserved;
  end;
implementation
const H:RawByteString='[General]'#10'ConfigVersion=1.3'#10;
procedure TPrismPerformanceTests.SetUp;
begin D:=Default(TPrismPerformanceDraft); P:=Default(TPrismPerformanceProposal); end;
procedure TPrismPerformanceTests.Ready(const G,I:RawByteString);
var S:TPrismPerformanceDraftStatus;
begin
  S:=PlanPrismPerformance(G,I,D,P,R); AssertTrue('Ready status reason='+IntToStr(Ord(R)),S in [ppdsReady,ppdsNoChanges]);
  AssertEquals(Ord(ppdrNone),Ord(R)); AssertEquals(G,P.ExpectedGlobalBytes);
  AssertEquals(I,P.ExpectedInstanceBytes);
end;
procedure TPrismPerformanceTests.Refuses(const G,I:RawByteString; Reason:TPrismPerformanceDraftReason);
var K:TPrismManagedKey; F:TPrismPerformanceFlag;
begin
  P.ExpectedGlobalBytes:='secret'; P.ExpectedInstanceBytes:='secret';
  P.ProposedInstanceDocument.Bytes:='secret'; P.InheritanceFreeze:=True;
  AssertEquals(Ord(ppdsUnsupported),Ord(PlanPrismPerformance(G,I,D,P,R)));
  AssertEquals(Ord(Reason),Ord(R)); AssertEquals('',P.ExpectedGlobalBytes);
  AssertEquals('',P.ExpectedInstanceBytes); AssertEquals('',P.ProposedInstanceDocument.Bytes);
  AssertFalse(P.InheritanceFreeze); AssertFalse(P.GateChanged);
  for K:=Low(K) to High(K) do AssertFalse(P.Touched[K]);
  for F:=Low(F) to High(F) do
  begin AssertFalse(P.Current.Flags[F].Value); AssertFalse(P.Proposed.Flags[F].Value);
    AssertFalse(P.EffectiveChanged[F]); end;
end;
procedure TPrismPerformanceTests.KeepExactAndDefaults;
var F:TPrismPerformanceFlag; S:RawByteString;
begin
  S:=H+'UseZink=not-a-bool'#10'Unrelated = opaque';
  AssertEquals(Ord(ppdsNoChanges),Ord(PlanPrismPerformance(H,S,D,P,R)));
  AssertEquals(S,P.ProposedInstanceDocument.Bytes);
  for F:=Low(F) to High(F) do
  begin AssertFalse(P.Current.Flags[F].Value); AssertEquals(Ord(pesDefault),Ord(P.Current.Flags[F].Source)); end;
  AssertFalse(P.Current.Gate.Value); AssertFalse(P.Current.Gate.Raw.Present);
end;
procedure TPrismPerformanceTests.FreezeAllFourBeforeIntents;
var F:TPrismPerformanceFlag;
begin
  D.Group:=ppgInstance; D.Fields[pefZink]:=ppiOn;
  Ready(H+'EnableMangoHud=true'#10'UseDiscreteGpu=true'#10'EnableFeralGamemode=true'#10,
    H+'UseDiscreteGpu=invalid-dormant'#10'UseZink=false'#10);
  AssertTrue(P.InheritanceFreeze); AssertTrue(P.GateChanged);
  for F:=Low(F) to High(F) do
  begin AssertTrue(P.Proposed.Flags[F].Value); AssertEquals(Ord(pesInstance),Ord(P.Proposed.Flags[F].Source)); end;
  AssertTrue(P.EffectiveChanged[ppfZink]); AssertFalse(P.EffectiveChanged[ppfMangoHud]);
end;
procedure TPrismPerformanceTests.AlreadyTrueOnlyRequested;
begin
  D.Fields[pefZink]:=ppiOn;
  Ready(H+'UseDiscreteGpu=true'#10,H+'OverridePerformance=true'#10'UseZink=false'#10);
  AssertFalse(P.InheritanceFreeze); AssertFalse(P.Touched[pmkOverridePerformance]);
  AssertFalse(P.Proposed.Flags[ppfDiscreteGpu].InstanceRaw.Present);
  AssertEquals(Ord(pesGlobal),Ord(P.Proposed.Flags[ppfDiscreteGpu].Source));
  AssertFalse(P.Touched[pmkEnableMangoHud]);
end;
procedure TPrismPerformanceTests.GlobalPreservesDormant;
var S:RawByteString;
begin
  S:=H+'OverridePerformance=true'#10'UseZink=true'#10'EnableMangoHud=false'#10;
  D.Group:=ppgGlobal; Ready(H+'EnableMangoHud=true'#10,S);
  AssertEquals(H+'OverridePerformance=false'#10'UseZink=true'#10'EnableMangoHud=false'#10,P.ProposedInstanceDocument.Bytes);
  AssertFalse(P.Proposed.Flags[ppfZink].Value); AssertTrue(P.Proposed.Flags[ppfMangoHud].Value);
  AssertTrue(P.EffectiveChanged[ppfMangoHud]);
  D:=Default(TPrismPerformanceDraft); D.Group:=ppgGlobal;
  AssertEquals(Ord(ppdsNoChanges),Ord(PlanPrismPerformance(H,H,D,P,R)));
end;
procedure TPrismPerformanceTests.InheritRemovesAndFallsBack;
begin
  D.Fields[pefDiscreteGpu]:=ppiInherit;
  Ready(H+'UseDiscreteGpu=true'#10,H+'OverridePerformance=true'#10' UseDiscreteGpu = false '#9#10'Unknown=kept');
  AssertFalse(P.Proposed.Flags[ppfDiscreteGpu].InstanceRaw.Present);
  AssertTrue(P.Proposed.Flags[ppfDiscreteGpu].Value);
  AssertEquals(H+'OverridePerformance=true'#10'Unknown=kept',P.ProposedInstanceDocument.Bytes);
  D.Group:=ppgInstance;
  Ready(H+'UseDiscreteGpu=true'#10,H);
  AssertTrue(P.InheritanceFreeze); AssertFalse(P.Proposed.Flags[ppfDiscreteGpu].InstanceRaw.Present);
  AssertTrue(P.Proposed.Flags[ppfDiscreteGpu].Value);
end;
procedure TPrismPerformanceTests.ExplicitFalseEqualGlobal;
begin
  D.Fields[pefZink]:=ppiOff;
  Ready(H+'UseZink=false'#10,H+'OverridePerformance=true'#10);
  AssertTrue(P.Proposed.Flags[ppfZink].InstanceRaw.Present);
  AssertEquals('false',P.Proposed.Flags[ppfZink].InstanceRaw.RawScalar);
  AssertFalse(P.EffectiveChanged[ppfZink]);
end;
procedure TPrismPerformanceTests.InactiveIntentRefused;
var Field:TPrismEditablePerformanceFlag; Intent:TPrismPerformanceFieldIntent;
begin
  for Field:=Low(Field) to High(Field) do
    for Intent:=ppiInherit to ppiOff do
    begin
      D:=Default(TPrismPerformanceDraft); D.Fields[Field]:=Intent;
      Refuses(H,H,ppdrInactiveFieldIntent); D.Group:=ppgGlobal;
      Refuses(H,H+'OverridePerformance=true'#10,ppdrInactiveFieldIntent);
    end;
end;
procedure TPrismPerformanceTests.DormantAndUnusedMalformed;
begin
  Ready(H,H+'OverridePerformance=false'#10'UseZink='#10'EnableMangoHud=1'#10);
  Ready(H+'UseZink=secret-invalid'#10,H+'OverridePerformance=true'#10'UseZink=true'#10);
  Refuses(H,H+'OverridePerformance='#10,ppdrGate);
  Refuses(H+'UseZink=0'#10,H,ppdrValue);
  Refuses(H,H+'OverridePerformance=true'#10'UseZink='#10,ppdrValue);
end;
procedure TPrismPerformanceTests.NewlySelectedMalformedGlobal;
begin
  D.Group:=ppgGlobal;
  Refuses(H+'UseZink=canary'#10,H+'OverridePerformance=true'#10'UseZink=false'#10,ppdrValue);
  D.Group:=ppgKeep; D.Fields[pefZink]:=ppiInherit;
  Refuses(H+'UseZink=canary'#10,H+'OverridePerformance=true'#10'UseZink=false'#10,ppdrValue);
end;
procedure TPrismPerformanceTests.OpaqueBindingCollisionsPreserved;
const O:RawByteString='OverrideEnv=not-bool'#10'Env="{not-json-secret}"'#10+
  'WrapperCommand=private-wrapper'#10'OverrideCommands=true'#10'OverrideLaunchCmd=false'#10;
begin
  D.Group:=ppgInstance; D.Fields[pefZink]:=ppiOn;
  Ready(H+O,H+O);
  AssertTrue(Pos(O,P.ProposedInstanceDocument.Bytes)>0);
  Ready(H+'Env="{\"MANGOHUD_CONFIGFILE\":\"secret\",\"LD_PRELOAD\":\"private\"}"'#10,H+O);
end;
procedure TPrismPerformanceTests.EndingsAndUnknownSections;
var E,S:RawByteString; J:Integer;
begin
  for J:=0 to 1 do
  begin
    if J=0 then E:=#10 else E:=#13#10;
    S:='[General]'+E+'ConfigVersion=1.3'+E+'OverridePerformance=true'+E+
      '  UseZink = "false" '+#9+E+'; untouched'+E+'[Unknown]'+E+'Data=opaque';
    D.Fields[pefZink]:=ppiOn; Ready(H,S);
    AssertEquals('replace EOL length='+IntToStr(Length(E)),StringReplace(S,'"false"','true',[]),P.ProposedInstanceDocument.Bytes);
    D.Fields[pefZink]:=ppiInherit; Ready(H,S);
    AssertTrue(Pos('; untouched'+E+'[Unknown]'+E+'Data=opaque',P.ProposedInstanceDocument.Bytes)>0);
  end;
  D.Group:=ppgInstance; D.Fields[pefZink]:=ppiOn;
  Ready(H,'[General]'#10'ConfigVersion=1.3');
  AssertTrue(P.Proposed.Flags[ppfZink].Value);
end;
procedure TPrismPerformanceTests.StrictDocumentsAndBounds;
begin
  Refuses('[General]'#10'Held=secret',H,ppdrGlobalDocument);
  Refuses(H,H+'ConfigVersion=1.3'#10,ppdrInstanceDocument);
  Refuses(H+'X='+StringOfChar('a',PrismDocumentMaxBytes),H,ppdrGlobalDocument);
  Refuses(H,H+'Env="unclosed',ppdrInstanceDocument);
end;
procedure TPrismPerformanceTests.NoMutationAndDeterminism;
var G,I:RawByteString; A:TPrismPerformanceProposal; AR:TPrismPerformanceDraftReason;
begin
  G:=H+'UseZink=true'#10; I:=H+'Unknown=canary'#10;
  D.Group:=ppgInstance; D.Fields[pefZink]:=ppiOff;
  Ready(G,I); A:=P;
  AssertEquals(Ord(ppdsReady),Ord(PlanPrismPerformance(G,I,D,P,AR)));
  AssertEquals(A.ProposedInstanceDocument.Bytes,P.ProposedInstanceDocument.Bytes);
  AssertEquals(H+'UseZink=true'#10,G); AssertEquals(H+'Unknown=canary'#10,I);
  AssertEquals(Ord(ppiOff),Ord(D.Fields[pefZink]));
end;
procedure TPrismPerformanceTests.MangoHudGroupDisclosure;
begin
  D.Group:=ppgGlobal; Ready(H+'EnableMangoHud=true'#10,H+'OverridePerformance=true'#10'EnableMangoHud=false'#10);
  AssertFalse(P.Current.Flags[ppfMangoHud].Value); AssertTrue(P.Proposed.Flags[ppfMangoHud].Value);
  AssertTrue(P.EffectiveChanged[ppfMangoHud]); AssertFalse(P.Touched[pmkEnableMangoHud]);
end;
procedure TPrismPerformanceTests.GlobalDriftSelectedNow;
begin
  D.Group:=ppgGlobal;
  Ready(H+'OverridePerformance=ignored-metadata'#10'UseZink=true'#10,
    H+'OverridePerformance=true'#10'UseZink=false'#10);
  AssertTrue(P.Proposed.Flags[ppfZink].Value);
  Ready(H+'UseZink=false'#10,H+'OverridePerformance=true'#10'UseZink=true'#10);
  AssertFalse(P.Proposed.Flags[ppfZink].Value);
end;
procedure TPrismPerformanceTests.OutputExpansionLimit;
var S:RawByteString;
begin
  S:=H+'Opaque='+StringOfChar('a',PrismDocumentMaxBytes-Length(H)-Length('Opaque='));
  AssertEquals(Ord(ppdsNoChanges),Ord(PlanPrismPerformance(H,S,D,P,R)));
  D.Group:=ppgInstance; Refuses(H,S,ppdrEdit);
end;
procedure TPrismPerformanceTests.MixedTerminatorsPreserved;
var S:RawByteString;
begin
  S:='[General]'#13#10'ConfigVersion=1.3'#10'OverridePerformance=true'#13#10+
    'UseZink=false'#10'; sentinel '#9#13#10'[Other]'#10'Held=opaque';
  D.Fields[pefZink]:=ppiInherit; Ready(H,S);
  AssertEquals(StringReplace(S,'UseZink=false'+#10,'',[]),P.ProposedInstanceDocument.Bytes);
end;
initialization
  RegisterTest(TPrismPerformanceTests);
end.
