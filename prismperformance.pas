unit prismperformance;
{$mode objfpc}{$H+}
interface
uses prismdocument, prismsnapshot;
type
  TPrismPerformanceGroupIntent = (ppgKeep, ppgGlobal, ppgInstance);
  TPrismPerformanceFieldIntent = (ppiKeep, ppiInherit, ppiOn, ppiOff);
  TPrismEditablePerformanceFlag = (pefDiscreteGpu, pefZink, pefFeralGamemode);
  TPrismPerformanceDraft = record
    Group: TPrismPerformanceGroupIntent;
    Fields: array[TPrismEditablePerformanceFlag] of TPrismPerformanceFieldIntent;
  end;
  TPrismPerformanceState = record
    Gate: TPrismGateSnapshot;
    Flags: array[TPrismPerformanceFlag] of TPrismEffectiveBool;
  end;
  TPrismPerformanceDraftStatus = (ppdsReady, ppdsNoChanges, ppdsUnsupported);
  TPrismPerformanceDraftReason = (ppdrNone, ppdrGlobalDocument,
    ppdrInstanceDocument, ppdrGate, ppdrValue, ppdrInactiveFieldIntent,
    ppdrEdit, ppdrVerification);
  TPrismPerformanceProposal = record
    ExpectedGlobalBytes, ExpectedInstanceBytes: RawByteString;
    ProposedInstanceDocument: TPrismDocument;
    Current, Proposed: TPrismPerformanceState;
    Touched: array[TPrismManagedKey] of Boolean;
    InheritanceFreeze, GateChanged: Boolean;
    EffectiveChanged: array[TPrismPerformanceFlag] of Boolean;
  end;
{ Pure advisory draft; no identity, I/O, ownership or publication authority.
  Index both complete ConfigVersion1.3 documents; decode only the instance
  performance gate and selected effective performance booleans. Env/wrapper/
  selectors remain opaque. Global/default fallback applies to absent locals.
  All-Keep returns exact NoChanges after validation. False->true freezes all
  four effective siblings before intents; MangoHud is never a field intent.
  Refusal clears the complete proposal and returns a fixed reason only. }
function PlanPrismPerformance(const GlobalBytes, InstanceBytes: RawByteString;
  const Draft: TPrismPerformanceDraft; out Proposal: TPrismPerformanceProposal;
  out Reason: TPrismPerformanceDraftReason): TPrismPerformanceDraftStatus;
implementation
uses prismsettings;
const EditableFlags: array[TPrismEditablePerformanceFlag] of TPrismPerformanceFlag =
  (ppfDiscreteGpu, ppfZink, ppfFeralGamemode);
function ReadState(const G,I:TPrismDocument; out S:TPrismPerformanceState;
  out Reason:TPrismPerformanceDraftReason):Boolean;
var F:TPrismPerformanceFlag; K:TPrismManagedKey; V:TPrismIndexedValue;
  E:TPrismBoolError;
begin
  S:=Default(TPrismPerformanceState); Result:=False; Reason:=ppdrGate;
  S.Gate.Key:=pmkOverridePerformance; S.Gate.Raw:=I.Managed[pmkOverridePerformance];
  if S.Gate.Raw.Present then
  begin
    S.Gate.Source:=pesInstance;
    if not DecodePrismBool(S.Gate.Raw.RawScalar,S.Gate.Value,E) then Exit;
  end;
  Reason:=ppdrValue;
  for F:=Low(F) to High(F) do
  begin
    K:=PrismPerformanceManagedKeys[F];
    S.Flags[F].GlobalRaw:=G.Managed[K]; S.Flags[F].InstanceRaw:=I.Managed[K];
    if S.Gate.Value and I.Managed[K].Present then
    begin S.Flags[F].Source:=pesInstance; V:=I.Managed[K]; end
    else if G.Managed[K].Present then
    begin S.Flags[F].Source:=pesGlobal; V:=G.Managed[K]; end
    else begin S.Flags[F].Source:=pesDefault; V:=Default(TPrismIndexedValue); end;
    if V.Present and not DecodePrismBool(V.RawScalar,S.Flags[F].Value,E) then Exit;
  end;
  Reason:=ppdrNone; Result:=True;
end;
function PlanPrismPerformance(const GlobalBytes, InstanceBytes:RawByteString;
  const Draft:TPrismPerformanceDraft; out Proposal:TPrismPerformanceProposal;
  out Reason:TPrismPerformanceDraftReason):TPrismPerformanceDraftStatus;
var P:TPrismPerformanceProposal; G,I,Work:TPrismDocument;
  DE:TPrismDocumentError; EE:TPrismDocumentEditError; BE:TPrismBoolError;
  Edits:array of TPrismManagedEdit; Removes:array of RawByteString;
  F:TPrismPerformanceFlag; Field:TPrismEditablePerformanceFlag;
  K:TPrismManagedKey; TargetGate, Value:Boolean;
  function GlobalValue(Flag:TPrismPerformanceFlag; out V:Boolean):Boolean;
  var Key:TPrismManagedKey;
  begin
    Key:=PrismPerformanceManagedKeys[Flag]; V:=False;
    Result:=not G.Managed[Key].Present;
    if not Result then Result:=DecodePrismBool(G.Managed[Key].RawScalar,V,BE);
  end;
  procedure Add(Key:TPrismManagedKey; V:Boolean);
  var J:SizeInt;
  begin
    { A field intent supersedes the initial freeze value, never duplicate edits. }
    for J:=0 to High(Edits) do
      if Edits[J].KeyName=PrismManagedKeyNames[Key] then
      begin Edits[J].RawScalar:=EncodePrismBool(V); Exit; end;
    J:=Length(Edits); SetLength(Edits,J+1);
    Edits[J].KeyName:=PrismManagedKeyNames[Key];
    Edits[J].RawScalar:=EncodePrismBool(V); P.Touched[Key]:=True;
  end;
  procedure Remove(Key:TPrismManagedKey);
  var J,L:SizeInt;
  begin
    for J:=0 to High(Edits) do
      if Edits[J].KeyName=PrismManagedKeyNames[Key] then
      begin
        for L:=J to High(Edits)-1 do Edits[L]:=Edits[L+1];
        SetLength(Edits,Length(Edits)-1); Break;
      end;
    J:=Length(Removes); SetLength(Removes,J+1);
    Removes[J]:=PrismManagedKeyNames[Key]; P.Touched[Key]:=True;
  end;
begin
  Proposal:=Default(TPrismPerformanceProposal); P:=Default(TPrismPerformanceProposal);
  Result:=ppdsUnsupported; Reason:=ppdrGlobalDocument;
  if not IndexPrismDocument(GlobalBytes,G,DE) then Exit;
  Reason:=ppdrInstanceDocument;
  if not IndexPrismDocument(InstanceBytes,I,DE) then Exit;
  if not ReadState(G,I,P.Current,Reason) then Exit;
  TargetGate:=P.Current.Gate.Value;
  case Draft.Group of
    ppgGlobal: TargetGate:=False;
    ppgInstance: TargetGate:=True;
  end;
  Reason:=ppdrInactiveFieldIntent;
  if not TargetGate then
    for Field:=Low(Field) to High(Field) do
      if Draft.Fields[Field]<>ppiKeep then Exit;
  P.InheritanceFreeze:=TargetGate and not P.Current.Gate.Value;
  P.GateChanged:=TargetGate<>P.Current.Gate.Value;
  if P.GateChanged then Add(pmkOverridePerformance,TargetGate);
  if P.InheritanceFreeze then
    for F:=Low(F) to High(F) do Add(PrismPerformanceManagedKeys[F],P.Current.Flags[F].Value);
  for Field:=Low(Field) to High(Field) do
  begin
    K:=PrismPerformanceManagedKeys[EditableFlags[Field]];
    case Draft.Fields[Field] of
      ppiInherit: Remove(K);
      ppiOn: Add(K,True);
      ppiOff: Add(K,False);
    end;
  end;
  Reason:=ppdrEdit;
  if not RemovePrismManagedLines(I,Removes,Work,EE) then Exit;
  if not EditPrismDocument(Work,Edits,P.ProposedInstanceDocument,EE) then Exit;
  if not ReadState(G,P.ProposedInstanceDocument,P.Proposed,Reason) then Exit;
  Reason:=ppdrVerification;
  { Compute intent independently from the selected sources, including newly
    selected global values after group/inherit changes. ReadState validated them. }
  for F:=Low(F) to High(F) do
  begin
    Value:=P.Current.Flags[F].Value;
    if not TargetGate then
      if not GlobalValue(F,Value) then Exit;
    for Field:=Low(Field) to High(Field) do
      if EditableFlags[Field]=F then
        case Draft.Fields[Field] of
          ppiInherit: if not GlobalValue(F,Value) then Exit;
          ppiOn: Value:=True;
          ppiOff: Value:=False;
        end;
    if P.Proposed.Flags[F].Value<>Value then Exit;
    P.EffectiveChanged[F]:=P.Current.Flags[F].Value<>Value;
  end;
  if P.Proposed.Gate.Value<>TargetGate then Exit;
  for Field:=Low(Field) to High(Field) do
  begin
    K:=PrismPerformanceManagedKeys[EditableFlags[Field]];
    case Draft.Fields[Field] of
      ppiInherit: if P.ProposedInstanceDocument.Managed[K].Present then Exit;
      ppiOn,ppiOff:
        if not P.ProposedInstanceDocument.Managed[K].Present or
          (P.ProposedInstanceDocument.Managed[K].RawScalar<>
          EncodePrismBool(Draft.Fields[Field]=ppiOn)) then Exit;
    end;
  end;
  for K:=Low(K) to High(K) do
    if not P.Touched[K] then
      if (I.Managed[K].Present<>P.ProposedInstanceDocument.Managed[K].Present) or
        (I.Managed[K].RawScalar<>P.ProposedInstanceDocument.Managed[K].RawScalar) then Exit;
  { Removal/edit helpers independently reindex and preserve all other raw spans. }
  P.ExpectedGlobalBytes:=GlobalBytes; P.ExpectedInstanceBytes:=InstanceBytes;
  Proposal:=P; Reason:=ppdrNone;
  if P.ProposedInstanceDocument.Bytes=InstanceBytes then Result:=ppdsNoChanges
  else Result:=ppdsReady;
end;
end.
