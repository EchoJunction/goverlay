unit prismplan;
{$mode objfpc}{$H+}
interface
uses prismprovider, prismdocument, prismsnapshot, prismenv;
type
  TPrismEnableReason = (perNone, perIdentity, perSelector, perAssessment,
    perEncoding, perEdit, perVerification);
  TPrismEnableProposal = record
    Instance: TPrismInstance;
    HostDataDir, Selector: string;
    BeforeSnapshot: TPrismSettingsSnapshot;
    ProposedInstanceDocument: TPrismDocument;
    Touched, Owned: array[TPrismManagedKey] of Boolean;
    OwnsSelector, OwnsMangoHudEnable, SelectorOnlyAdoption: Boolean;
    PerformanceInheritanceFreeze, EnvInheritanceFreeze: Boolean;
    AppliedPerformanceGate, AppliedEnvGate, AppliedCommandsGate: Boolean;
    AppliedPerformance: array[TPrismPerformanceFlag] of Boolean;
    AppliedEnv: TPrismEnvMap;
  end;
{ Pure proposal only. Caller supplies discovery-validated UUID uniqueness/root
  association and must separately validate ambient environment; M3b must recheck
  filesystem identity, launcher/concurrency and exact before bytes before writes.
  Paths/identity are checked lexically only, never discovered or read. External
  InstanceDir is supported. Supplied effective fields are untrusted: reassess
  both raw documents. Refusal clears proposal; reasons never contain raw data.
  BeforeSnapshot + applied document/values/ownership are transient provenance,
  not a persisted ownership schema. No existing unowned selector is adopted. }
function PlanPrismEnable(const Instance: TPrismInstance; const HostDataDir,
  Selector: string; const Snapshot: TPrismSettingsSnapshot;
  out Proposal: TPrismEnableProposal; out Reason: TPrismEnableReason;
  out AssessmentReason: TPrismAssessmentReason): TPrismAssessmentStatus;
implementation
uses SysUtils, SHA1, gamecontext, prismsettings;
function Canonical(const P: string): Boolean;
var C: string;
begin Result := CanonicalPrismPath(P,C,False) and (P=C); end;
function IdentityValid(const I: TPrismInstance; const Host: string;
  out Context: TActiveProfileContext): Boolean;
var Identity, Dir: string; C: Char;
begin
  Result := False;
  if not Canonical(I.DataRoot) or not Canonical(I.ConfigPath) or
    not Canonical(Host) then Exit;
  if ExtractFileName(I.ConfigPath) <> 'instance.cfg' then Exit;
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(I.ConfigPath));
  if (I.Folder='') or (ExtractFileName(Dir)<>I.Folder) then Exit;
  if I.UsesFolderIdentity then
  begin
    if I.UUID<>'' then Exit;
    Identity := 'folder:'+Dir;
  end
  else
  begin
    if Length(I.UUID)<>32 then Exit;
    for C in I.UUID do if not (C in ['0'..'9','a'..'f']) then Exit;
    Identity := 'uuid:'+I.UUID;
  end;
  if I.InstallationKey <> 'prism-root-'+SHA1Print(SHA1String(I.DataRoot)) then Exit;
  if I.StableKey <> 'prism-'+SHA1Print(SHA1String(I.DataRoot+#0+Identity)) then Exit;
  Result := PrismProfileContext(I,Host,Context);
end;
function PlanPrismEnable(const Instance: TPrismInstance; const HostDataDir,
  Selector: string; const Snapshot: TPrismSettingsSnapshot;
  out Proposal: TPrismEnableProposal; out Reason: TPrismEnableReason;
  out AssessmentReason: TPrismAssessmentReason): TPrismAssessmentStatus;
var P: TPrismEnableProposal; Context: TActiveProfileContext;
  Edits: array of TPrismManagedEdit; F: TPrismPerformanceFlag;
  K: TPrismManagedKey; E: TPrismDocumentEditError; DE: TPrismDocumentError;
  EE: TPrismEnvError; BE: TPrismBoolError; Encoded: RawByteString;
  Indexed: TPrismDocument; Selected: TPrismIndexedValue;
  I, N: SizeInt; V: Boolean; Expected: TPrismEnvMap;
  procedure Add(Key: TPrismManagedKey; const Value: RawByteString);
  var Len: SizeInt;
  begin
    Len := Length(Edits); SetLength(Edits,Len+1);
    Edits[Len].KeyName := PrismManagedKeyNames[Key]; Edits[Len].RawScalar := Value;
    P.Touched[Key] := True; P.Owned[Key] := True;
  end;
  function LocalBool(Key: TPrismManagedKey; out Value: Boolean): Boolean;
  begin
    Result := Indexed.Managed[Key].Present and
      DecodePrismBool(Indexed.Managed[Key].RawScalar,Value,BE);
  end;
begin
  Proposal := Default(TPrismEnableProposal); P := Default(TPrismEnableProposal);
  Result := psaUnsupported; Reason := perIdentity; AssessmentReason := psrNone;
  if not IdentityValid(Instance,HostDataDir,Context) then Exit;
  Reason := perSelector;
  if not Canonical(Selector) or (Selector<>Context.ConfigDir+'MangoHud.conf') then Exit;
  Reason := perAssessment;
  Result := AssessPrismSettings(Snapshot.GlobalDocument.Bytes,
    Snapshot.InstanceDocument.Bytes,P.BeforeSnapshot,AssessmentReason);
  if Result<>psaReady then Exit;
  Result := psaUnsupported; Reason := perEncoding;
  P.Instance := Instance; P.HostDataDir := HostDataDir; P.Selector := Selector;
  P.SelectorOnlyAdoption := P.BeforeSnapshot.Performance[ppfMangoHud].Value;
  P.OwnsMangoHudEnable := not P.SelectorOnlyAdoption;
  P.PerformanceInheritanceFreeze := P.OwnsMangoHudEnable and
    not P.BeforeSnapshot.PerformanceGate.Value;
  for F := Low(F) to High(F) do
    P.AppliedPerformance[F] := P.BeforeSnapshot.Performance[F].Value;
  P.AppliedPerformanceGate := P.BeforeSnapshot.PerformanceGate.Value;
  P.AppliedCommandsGate := P.BeforeSnapshot.CommandsGate.Value;
  if P.OwnsMangoHudEnable then
  begin
    P.AppliedPerformance[ppfMangoHud] := True;
    P.AppliedPerformanceGate := True;
    if P.PerformanceInheritanceFreeze then
    begin
      for F := Low(F) to High(F) do
        Add(PrismPerformanceManagedKeys[F],EncodePrismBool(P.AppliedPerformance[F]));
      Add(pmkOverridePerformance,EncodePrismBool(True));
    end
    else Add(pmkEnableMangoHud,EncodePrismBool(True));
  end;
  { Copy dynamic map explicitly: never modify caller-owned/shared entries. }
  N := Length(P.BeforeSnapshot.Env.Entries); SetLength(Expected,N+1);
  for I := 0 to N-1 do Expected[I] := P.BeforeSnapshot.Env.Entries[I];
  Expected[N].Key := 'MANGOHUD_CONFIGFILE'; Expected[N].Value := UTF8String(Selector);
  if not EncodePrismEnv(Expected,Encoded,EE) then Exit;
  Add(pmkEnv,Encoded); P.OwnsSelector := True;
  P.EnvInheritanceFreeze := P.BeforeSnapshot.Env.Source<>pesInstance;
  if not P.BeforeSnapshot.EnvGate.Value then Add(pmkOverrideEnv,EncodePrismBool(True));
  P.AppliedEnvGate := True;
  Reason := perEdit;
  if not EditPrismDocument(P.BeforeSnapshot.InstanceDocument,Edits,
    P.ProposedInstanceDocument,E) then Exit;
  Reason := perVerification;
  if not IndexPrismDocument(P.ProposedInstanceDocument.Bytes,Indexed,DE) then Exit;
  { Direct semantic checks intentionally recognize only our exact new selector.
    Unowned preflight above remains strict. No general collision bypass exists. }
  if not LocalBool(pmkOverrideEnv,V) or not V then Exit;
  if not DecodePrismEnv(Indexed.Managed[pmkEnv].RawScalar,P.AppliedEnv,EE) then Exit;
  if Length(P.AppliedEnv)<>Length(Expected) then Exit;
  for I := 0 to High(Expected) do
    if (P.AppliedEnv[I].Key<>Expected[I].Key) or
      (P.AppliedEnv[I].Value<>Expected[I].Value) then Exit;
  if P.OwnsMangoHudEnable then
  begin
    if not LocalBool(pmkOverridePerformance,V) or not V then Exit;
  end;
  for F := Low(F) to High(F) do
  begin
    K := PrismPerformanceManagedKeys[F];
    if P.AppliedPerformanceGate and Indexed.Managed[K].Present then
      Selected := Indexed.Managed[K]
    else Selected := P.BeforeSnapshot.GlobalDocument.Managed[K];
    V := False;
    if Selected.Present and not DecodePrismBool(Selected.RawScalar,V,BE) then Exit;
    if V<>P.AppliedPerformance[F] then Exit;
  end;
  { Every unedited managed scalar must remain exactly present/absent and raw.
    The span editor preserves all other lines, whitespace and terminators. }
  for K := Low(K) to High(K) do
    if not P.Touched[K] then
      if (Indexed.Managed[K].Present<>P.BeforeSnapshot.InstanceDocument.Managed[K].Present) or
        (Indexed.Managed[K].RawScalar<>P.BeforeSnapshot.InstanceDocument.Managed[K].RawScalar) then Exit;
  P.ProposedInstanceDocument := Indexed;
  Proposal := P; Reason := perNone; Result := psaReady;
end;
end.
