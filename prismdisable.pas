unit prismdisable;
{$mode objfpc}{$H+}
interface
uses prismplan, prismdocument;
type
  TPrismDisableStatus=(pdsReady,pdsNoChanges,pdsConflict,pdsUnsupported);
  TPrismDisableReason=(pdrNone,pdrOwnership,pdrGlobalDocument,pdrInstanceDocument,
    pdrEnvGate,pdrEnvValue,pdrSelector,pdrPerformanceGate,pdrPerformanceValue,
    pdrInheritedValue,pdrEdit,pdrVerification);
  TPrismDisableProposal=record
    ExpectedGlobalBytes,ExpectedInstanceBytes:RawByteString;
    ProposedInstanceDocument:TPrismDocument;
    ResidualEnv,ResidualPerformance,ResidualFormatting:Boolean;
  end;
{ Pure three-way proposal. Validates transient internal consistency first; no
  ownership authenticity, target association, filesystem/concurrency or ambient
  checks. Those remain caller/M3b preconditions. Global bytes are never edited.
  Only exact owned selector and still-applied owned fields can be restored.
  NoChanges requires exact original instance bytes; missing selector alone is
  insufficient. Refusals clear every output and return fixed reasons only. }
function PlanPrismDisable(const Owned:TPrismEnableProposal;
  const CurrentGlobal,CurrentInstance:RawByteString;
  out Proposal:TPrismDisableProposal; out Reason:TPrismDisableReason):TPrismDisableStatus;
implementation
uses prismownership, prismsnapshot, prismsettings, prismenv;
function SameMap(const A,B:TPrismEnvMap):Boolean;
var I:SizeInt;
begin
  Result:=False; if Length(A)<>Length(B) then Exit;
  for I:=0 to High(A) do if (A[I].Key<>B[I].Key) or (A[I].Value<>B[I].Value) then Exit;
  Result:=True;
end;
function PlanPrismDisable(const Owned:TPrismEnableProposal;
  const CurrentGlobal,CurrentInstance:RawByteString;
  out Proposal:TPrismDisableProposal; out Reason:TPrismDisableReason):TPrismDisableStatus;
var Canonical:TPrismEnableProposal; ORsn:TPrismOwnershipReason;
  G,D,Intermediate,Proposed:TPrismDocument; DE:TPrismDocumentError;
  EE:TPrismEnvError; BE:TPrismBoolError; EditError:TPrismDocumentEditError;
  P:TPrismDisableProposal; CurrentEnv,Remaining:TPrismEnvMap;
  Edits:array of TPrismManagedEdit; Removals:array of RawByteString;
  F:TPrismPerformanceFlag; K:TPrismManagedKey;
  I,J,SelectorIndex,N:SizeInt; Gate,V,GroupUnchanged,EnvUnchanged,AddedAtEOF:Boolean;
  Raw:RawByteString;
  procedure SetScalar(Key:TPrismManagedKey; const Value:RawByteString);
  var Len:SizeInt;
  begin
    Len:=Length(Edits); SetLength(Edits,Len+1);
    Edits[Len].KeyName:=PrismManagedKeyNames[Key]; Edits[Len].RawScalar:=Value;
  end;
  procedure Restore(Key:TPrismManagedKey);
  var Len:SizeInt;
  begin
    if Canonical.BeforeSnapshot.InstanceDocument.Managed[Key].Present then
      SetScalar(Key,Canonical.BeforeSnapshot.InstanceDocument.Managed[Key].RawScalar)
    else
    begin
      Len:=Length(Removals); SetLength(Removals,Len+1);
      Removals[Len]:=PrismManagedKeyNames[Key];
    end;
  end;
  function OriginalRaw(Key:TPrismManagedKey):Boolean;
  begin
    Result:=(Proposed.Managed[Key].Present=Canonical.BeforeSnapshot.InstanceDocument.Managed[Key].Present) and
      (Proposed.Managed[Key].RawScalar=Canonical.BeforeSnapshot.InstanceDocument.Managed[Key].RawScalar);
  end;
  function TrueGate(Key:TPrismManagedKey; out Value:Boolean):Boolean;
  begin
    Value:=False;
    Result:=not D.Managed[Key].Present or
      DecodePrismBool(D.Managed[Key].RawScalar,Value,BE);
  end;
  function LocalMatchesApplied(Key:TPrismManagedKey; out Value:Boolean):Boolean;
  begin
    Value:=False;
    Result:=D.Managed[Key].Present and
      DecodePrismBool(D.Managed[Key].RawScalar,Value,BE) and
      Canonical.ProposedInstanceDocument.Managed[Key].Present;
    if Result then Result:=Value=Canonical.AppliedPerformance[ppfMangoHud];
  end;
  { Validate selected semantics after restoration against CURRENT global values.
    Dormant values and unowned/adopted performance remain opaque semantically. }
  function VerifySelected:Boolean;
  var LocalGate:Boolean; Values:TPrismEnvMap; Flag:TPrismPerformanceFlag;
    Key:TPrismManagedKey; BoolValue:Boolean; Chosen:TPrismIndexedValue;
  begin
    Result:=False; LocalGate:=False;
    if Proposed.Managed[pmkOverrideEnv].Present and not
      DecodePrismBool(Proposed.Managed[pmkOverrideEnv].RawScalar,LocalGate,BE) then Exit;
    if LocalGate and Proposed.Managed[pmkEnv].Present then Chosen:=Proposed.Managed[pmkEnv]
    else Chosen:=G.Managed[pmkEnv];
    if Chosen.Present and not DecodePrismEnv(Chosen.RawScalar,Values,EE) then Exit;
    if Canonical.OwnsMangoHudEnable then
    begin
      LocalGate:=False;
      if Proposed.Managed[pmkOverridePerformance].Present and not
        DecodePrismBool(Proposed.Managed[pmkOverridePerformance].RawScalar,LocalGate,BE) then Exit;
      for Flag:=Low(Flag) to High(Flag) do
      begin
        if not Canonical.PerformanceInheritanceFreeze and (Flag<>ppfMangoHud) then Continue;
        Key:=PrismPerformanceManagedKeys[Flag];
        if LocalGate and Proposed.Managed[Key].Present then Chosen:=Proposed.Managed[Key]
        else Chosen:=G.Managed[Key];
        if Chosen.Present and not DecodePrismBool(Chosen.RawScalar,BoolValue,BE) then Exit;
      end;
    end;
    Result:=True;
  end;
begin
  Proposal:=Default(TPrismDisableProposal); P:=Default(TPrismDisableProposal);
  Result:=pdsUnsupported; Reason:=pdrOwnership;
  if not ValidatePrismEnableRecord(Owned,Canonical,ORsn) then Exit;
  Reason:=pdrGlobalDocument; if not IndexPrismDocument(CurrentGlobal,G,DE) then Exit;
  Reason:=pdrInstanceDocument; if not IndexPrismDocument(CurrentInstance,D,DE) then Exit;
  if CurrentInstance=Canonical.BeforeSnapshot.InstanceDocument.Bytes then
  begin
    P.ExpectedGlobalBytes:=CurrentGlobal; P.ExpectedInstanceBytes:=CurrentInstance;
    P.ProposedInstanceDocument:=D; Proposal:=P; Reason:=pdrNone; Exit(pdsNoChanges);
  end;
  Reason:=pdrEnvGate;
  if not TrueGate(pmkOverrideEnv,Gate) then Exit;
  if not Gate then Exit(pdsConflict);
  Reason:=pdrEnvValue;
  if not D.Managed[pmkEnv].Present then begin Reason:=pdrSelector; Exit(pdsConflict); end;
  if not DecodePrismEnv(D.Managed[pmkEnv].RawScalar,CurrentEnv,EE) then Exit;
  Reason:=pdrSelector; SelectorIndex:=-1;
  for I:=0 to High(CurrentEnv) do
    if CurrentEnv[I].Key='MANGOHUD_CONFIGFILE' then SelectorIndex:=I;
  if SelectorIndex<0 then Exit(pdsConflict);
  if CurrentEnv[SelectorIndex].Value<>UTF8String(Canonical.Selector) then Exit(pdsConflict);
  EnvUnchanged:=SameMap(CurrentEnv,Canonical.AppliedEnv);
  if EnvUnchanged then
  begin
    Restore(pmkEnv);
    if Canonical.Owned[pmkOverrideEnv] then Restore(pmkOverrideEnv);
  end
  else
  begin
    N:=Length(CurrentEnv)-1; SetLength(Remaining,N); J:=0;
    for I:=0 to High(CurrentEnv) do if I<>SelectorIndex then
    begin Remaining[J]:=CurrentEnv[I]; Inc(J); end;
    Reason:=pdrEnvValue;
    if not EncodePrismEnv(Remaining,Raw,EE) then Exit;
    SetScalar(pmkEnv,Raw);
    P.ResidualEnv:=Canonical.EnvInheritanceFreeze;
  end;
  GroupUnchanged:=True;
  if Canonical.OwnsMangoHudEnable then
  begin
    Reason:=pdrPerformanceGate;
    if not TrueGate(pmkOverridePerformance,Gate) then Exit;
    if not Gate then Exit(pdsConflict);
    Reason:=pdrPerformanceValue;
    if Canonical.PerformanceInheritanceFreeze then
    begin
      for F:=Low(F) to High(F) do
      begin
        K:=PrismPerformanceManagedKeys[F];
        if D.Managed[K].Present then
        begin
          if not DecodePrismBool(D.Managed[K].RawScalar,V,BE) then Exit;
          if V<>Canonical.AppliedPerformance[F] then GroupUnchanged:=False;
        end
        else GroupUnchanged:=False;
      end;
      if GroupUnchanged then
      begin
        for F:=Low(F) to High(F) do Restore(PrismPerformanceManagedKeys[F]);
        Restore(pmkOverridePerformance);
      end
      else
      begin
        if LocalMatchesApplied(pmkEnableMangoHud,V) then
          SetScalar(pmkEnableMangoHud,EncodePrismBool(Canonical.BeforeSnapshot.Performance[ppfMangoHud].Value));
        P.ResidualPerformance:=True;
      end;
    end
    else
    begin
      { Selected local empty/invalid is unsupported, not an opaque user flag. }
      if D.Managed[pmkEnableMangoHud].Present and not
        DecodePrismBool(D.Managed[pmkEnableMangoHud].RawScalar,V,BE) then Exit;
      GroupUnchanged:=LocalMatchesApplied(pmkEnableMangoHud,V);
      if GroupUnchanged then Restore(pmkEnableMangoHud)
      else P.ResidualPerformance:=True;
    end;
  end;
  Reason:=pdrEdit;
  if not RemovePrismManagedLines(D,Removals,Intermediate,EditError) then Exit;
  if not EditPrismDocument(Intermediate,Edits,Proposed,EditError) then Exit;
  if (CurrentInstance=Canonical.ProposedInstanceDocument.Bytes) and
    EnvUnchanged and GroupUnchanged then
    Proposed:=Canonical.BeforeSnapshot.InstanceDocument
  else
  begin
    { An edited unterminated original cannot prove ownership of a separator
      inserted at EOF. Keep it; never silently claim exact formatting rollback. }
    Raw:=Canonical.BeforeSnapshot.InstanceDocument.Bytes; AddedAtEOF:=False;
    for K:=Low(K) to High(K) do
      if Canonical.Touched[K] and not Canonical.BeforeSnapshot.InstanceDocument.Managed[K].Present then
        AddedAtEOF:=True;
    P.ResidualFormatting:=AddedAtEOF and(Length(Raw)>0) and (Raw[Length(Raw)]<>#10) and
      (Canonical.BeforeSnapshot.InstanceDocument.GeneralInsertOffset=Length(Raw)+1) and
      (Canonical.ProposedInstanceDocument.Bytes<>Raw);
  end;
  Reason:=pdrVerification;
  if not IndexPrismDocument(Proposed.Bytes,Intermediate,DE) then Exit;
  Proposed:=Intermediate;
  if P.ResidualPerformance then
  begin
    GroupUnchanged:=OriginalRaw(pmkOverridePerformance);
    for F:=Low(F) to High(F) do
      if not OriginalRaw(PrismPerformanceManagedKeys[F]) then GroupUnchanged:=False;
    if GroupUnchanged then P.ResidualPerformance:=False;
  end;
  { Verify every intended managed restoration/removal against freshly indexed
    output; other bytes were retained by the span primitives. }
  for I:=0 to High(Edits) do
    for K:=Low(K) to High(K) do
      if Edits[I].KeyName=PrismManagedKeyNames[K] then
        if not Proposed.Managed[K].Present or
          (Proposed.Managed[K].RawScalar<>Edits[I].RawScalar) then Exit;
  for I:=0 to High(Removals) do
    for K:=Low(K) to High(K) do
      if Removals[I]=PrismManagedKeyNames[K] then
        if Proposed.Managed[K].Present then Exit;
  Reason:=pdrInheritedValue;
  if not VerifySelected then Exit;
  P.ExpectedGlobalBytes:=CurrentGlobal; P.ExpectedInstanceBytes:=CurrentInstance;
  P.ProposedInstanceDocument:=Proposed;
  Proposal:=P; Reason:=pdrNone; Result:=pdsReady;
end;
end.
