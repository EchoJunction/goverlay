unit prismownership;
{$mode objfpc}{$H+}
interface
uses prismplan;
type
  TPrismOwnershipReason = (porNone, porReconstruction, porBeforeSnapshot,
    porAppliedDocument, porOwnershipFlags, porAppliedValues);
{ Validates INTERNAL CONSISTENCY of a transient enable record by reconstructing
  it from identity, explicit profile inputs and raw before bytes. Compares all
  derived fields; returns only the reconstructed canonical record. This does
  not authenticate persisted ownership or the caller's target association.
  Caller/M3b identity, authenticity, filesystem and concurrency preconditions
  remain. No disable/edit/I/O/UI/serialization. Refusal clears all output and
  returns a fixed reason, never arbitrary input values. }
function ValidatePrismEnableRecord(const Supplied: TPrismEnableProposal;
  out Canonical: TPrismEnableProposal; out Reason: TPrismOwnershipReason): Boolean;
implementation
uses prismdocument, prismsnapshot, prismenv;
function SameValue(const A,B:TPrismIndexedValue):Boolean;
begin
  Result := (A.Present=B.Present) and (A.LineSpan.Offset=B.LineSpan.Offset) and
    (A.LineSpan.Length=B.LineSpan.Length) and (A.ValueSpan.Offset=B.ValueSpan.Offset) and
    (A.ValueSpan.Length=B.ValueSpan.Length) and (A.RawScalar=B.RawScalar) and
    (A.DecodedScalar=B.DecodedScalar);
end;
function SameDocument(const A,B:TPrismDocument):Boolean;
var K:TPrismManagedKey;
begin
  Result:=False;
  if (A.Bytes<>B.Bytes) or (A.GeneralInsertOffset<>B.GeneralInsertOffset) or
    (A.GeneralLineEnding<>B.GeneralLineEnding) then Exit;
  for K:=Low(K) to High(K) do if not SameValue(A.Managed[K],B.Managed[K]) then Exit;
  Result:=True;
end;
function SameMap(const A,B:TPrismEnvMap):Boolean;
var I:SizeInt;
begin
  Result:=False; if Length(A)<>Length(B) then Exit;
  for I:=0 to High(A) do
    if (A[I].Key<>B[I].Key) or (A[I].Value<>B[I].Value) then Exit;
  Result:=True;
end;
function SameGate(const A,B:TPrismGateSnapshot):Boolean;
begin
  Result:=(A.Key=B.Key) and SameValue(A.Raw,B.Raw) and
    (A.Source=B.Source) and (A.Value=B.Value);
end;
function SameSnapshot(const A,B:TPrismSettingsSnapshot):Boolean;
var F:TPrismPerformanceFlag;
begin
  Result:=False;
  if not SameDocument(A.GlobalDocument,B.GlobalDocument) or
    not SameDocument(A.InstanceDocument,B.InstanceDocument) or
    not SameGate(A.PerformanceGate,B.PerformanceGate) or
    not SameGate(A.EnvGate,B.EnvGate) or not SameGate(A.CommandsGate,B.CommandsGate) or
    (A.AmbientEnvironmentVerified<>B.AmbientEnvironmentVerified) then Exit;
  for F:=Low(F) to High(F) do
    if not SameValue(A.Performance[F].GlobalRaw,B.Performance[F].GlobalRaw) or
      not SameValue(A.Performance[F].InstanceRaw,B.Performance[F].InstanceRaw) or
      (A.Performance[F].Source<>B.Performance[F].Source) or
      (A.Performance[F].Value<>B.Performance[F].Value) then Exit;
  if not SameValue(A.Env.GlobalRaw,B.Env.GlobalRaw) or
    not SameValue(A.Env.InstanceRaw,B.Env.InstanceRaw) or (A.Env.Source<>B.Env.Source) or
    not SameMap(A.Env.Entries,B.Env.Entries) or
    not SameValue(A.Wrapper.GlobalRaw,B.Wrapper.GlobalRaw) or
    not SameValue(A.Wrapper.InstanceRaw,B.Wrapper.InstanceRaw) or
    (A.Wrapper.Source<>B.Wrapper.Source) or (A.Wrapper.Value<>B.Wrapper.Value) then Exit;
  Result:=True;
end;
function ValidatePrismEnableRecord(const Supplied:TPrismEnableProposal;
  out Canonical:TPrismEnableProposal; out Reason:TPrismOwnershipReason):Boolean;
var Fresh:TPrismEnableProposal; R:TPrismEnableReason; AR:TPrismAssessmentReason;
  K:TPrismManagedKey; F:TPrismPerformanceFlag;
begin
  Result:=False; Canonical:=Default(TPrismEnableProposal); Reason:=porReconstruction;
  if PlanPrismEnable(Supplied.Instance,Supplied.HostDataDir,Supplied.Selector,
    Supplied.BeforeSnapshot,Fresh,R,AR)<>psaReady then Exit;
  { Identity/HostDataDir/Selector are the explicit reconstruction inputs. Plan
    validates them lexically and copies them exactly, not their authenticity. }
  Reason:=porBeforeSnapshot;
  if not SameSnapshot(Supplied.BeforeSnapshot,Fresh.BeforeSnapshot) then Exit;
  Reason:=porAppliedDocument;
  if not SameDocument(Supplied.ProposedInstanceDocument,Fresh.ProposedInstanceDocument) then Exit;
  Reason:=porOwnershipFlags;
  for K:=Low(K) to High(K) do
    if (Supplied.Touched[K]<>Fresh.Touched[K]) or (Supplied.Owned[K]<>Fresh.Owned[K]) then Exit;
  if (Supplied.OwnsSelector<>Fresh.OwnsSelector) or
    (Supplied.OwnsMangoHudEnable<>Fresh.OwnsMangoHudEnable) or
    (Supplied.SelectorOnlyAdoption<>Fresh.SelectorOnlyAdoption) or
    (Supplied.PerformanceInheritanceFreeze<>Fresh.PerformanceInheritanceFreeze) or
    (Supplied.EnvInheritanceFreeze<>Fresh.EnvInheritanceFreeze) then Exit;
  Reason:=porAppliedValues;
  if (Supplied.AppliedPerformanceGate<>Fresh.AppliedPerformanceGate) or
    (Supplied.AppliedEnvGate<>Fresh.AppliedEnvGate) or
    (Supplied.AppliedCommandsGate<>Fresh.AppliedCommandsGate) then Exit;
  for F:=Low(F) to High(F) do
    if Supplied.AppliedPerformance[F]<>Fresh.AppliedPerformance[F] then Exit;
  if not SameMap(Supplied.AppliedEnv,Fresh.AppliedEnv) then Exit;
  Canonical:=Fresh; Reason:=porNone; Result:=True;
end;
end.
