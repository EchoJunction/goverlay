unit prismsnapshot;
{$mode objfpc}{$H+}
interface
uses prismsettings, prismenv, prismdocument;
type
  TPrismAssessmentStatus = (psaReady, psaConflict, psaUnsupported);
  TPrismAssessmentReason = (psrNone, psrGlobalDocument, psrInstanceDocument,
    psrPerformanceGate, psrEnvGate, psrCommandsGate, psrCommandsAliases,
    psrPerformanceValue, psrEnvValue, psrMangoHudConfig, psrMangoHudSelector,
    psrWrapperCommand, psrPreload);
  TPrismEffectiveSource = (pesDefault, pesGlobal, pesInstance);
  TPrismPerformanceFlag = (ppfMangoHud, ppfDiscreteGpu, ppfZink, ppfFeralGamemode);
  TPrismGateSnapshot = record
    Key: TPrismManagedKey;
    Raw: TPrismIndexedValue;
    Source: TPrismEffectiveSource;
    Value: Boolean;
  end;
  TPrismEffectiveBool = record
    GlobalRaw, InstanceRaw: TPrismIndexedValue;
    Source: TPrismEffectiveSource;
    Value: Boolean;
  end;
  TPrismEffectiveEnv = record
    GlobalRaw, InstanceRaw: TPrismIndexedValue;
    Source: TPrismEffectiveSource;
    Entries: TPrismEnvMap;
  end;
  TPrismEffectiveWrapper = record
    GlobalRaw, InstanceRaw: TPrismIndexedValue;
    Source: TPrismEffectiveSource;
    Value: UTF8String;
  end;
  TPrismSettingsSnapshot = record
    GlobalDocument, InstanceDocument: TPrismDocument;
    PerformanceGate, EnvGate, CommandsGate: TPrismGateSnapshot;
    Performance: array[TPrismPerformanceFlag] of TPrismEffectiveBool;
    Env: TPrismEffectiveEnv;
    Wrapper: TPrismEffectiveWrapper;
    AmbientEnvironmentVerified: Boolean;
  end;
const
  PrismPerformanceManagedKeys: array[TPrismPerformanceFlag] of TPrismManagedKey = (
    pmkEnableMangoHud, pmkUseDiscreteGpu, pmkUseZink, pmkEnableFeralGamemode);

{ Pure bounded snapshot of two complete strict ConfigVersion=1.3 documents.
  Only INSTANCE gates apply. False/absent gates select global/default; true gates
  select present instance fields, else global/default. Semantic bool/JSON decode
  applies only to selected effective fields; dormant/unused raw values remain
  intact. Structural/scalar checks still cover both entire input documents.
  Instance commands aliases together are conservatively unsupported; global
  aliases are unused raw metadata. Empty wrappers/defaults are supported.

  Ready concerns supplied settings only: ambient launch environment is NEVER
  inspected/verified and remains a separate caller/runtime precondition. No
  ownership, intended-selector comparison, edits, I/O, UI or plans. Existing
  effective selectors (even empty/equal intended) are unowned Conflict; opaque
  nonempty effective wrapper/preload is Unsupported. Refusals clear Snapshot
  entirely and report only a fixed enum, never input values. Deterministic
  priority: document/gate/value validation, config, selector, wrapper, preload. }
function AssessPrismSettings(const GlobalBytes, InstanceBytes: RawByteString;
  out Snapshot: TPrismSettingsSnapshot;
  out Reason: TPrismAssessmentReason): TPrismAssessmentStatus;

implementation
function AssessPrismSettings(const GlobalBytes, InstanceBytes: RawByteString;
  out Snapshot: TPrismSettingsSnapshot;
  out Reason: TPrismAssessmentReason): TPrismAssessmentStatus;
var
  Candidate: TPrismSettingsSnapshot;
  DocumentError: TPrismDocumentError;
  BoolError: TPrismBoolError;
  EnvError: TPrismEnvError;
  Flag: TPrismPerformanceFlag;
  CommandsKey: TPrismManagedKey;
  Selected: TPrismIndexedValue;
  I: SizeInt;

  function Gate(Key: TPrismManagedKey; out Value: TPrismGateSnapshot): Boolean;
  begin
    Value := Default(TPrismGateSnapshot); Value.Key := Key;
    Value.Raw := Candidate.InstanceDocument.Managed[Key];
    Result := True;
    if not Value.Raw.Present then Exit;
    Value.Source := pesInstance;
    Result := DecodePrismBool(Value.Raw.RawScalar, Value.Value, BoolError);
  end;

  procedure Select(Key: TPrismManagedKey; Override: Boolean;
    out GlobalRaw, InstanceRaw: TPrismIndexedValue;
    out Source: TPrismEffectiveSource; out Effective: TPrismIndexedValue);
  begin
    GlobalRaw := Candidate.GlobalDocument.Managed[Key];
    InstanceRaw := Candidate.InstanceDocument.Managed[Key];
    if Override and InstanceRaw.Present then
    begin Effective := InstanceRaw; Source := pesInstance; end
    else if GlobalRaw.Present then
    begin Effective := GlobalRaw; Source := pesGlobal; end
    else
    begin Effective := Default(TPrismIndexedValue); Source := pesDefault; end;
  end;

begin
  Snapshot := Default(TPrismSettingsSnapshot);
  Candidate := Default(TPrismSettingsSnapshot);
  Result := psaUnsupported; Reason := psrGlobalDocument;
  if not IndexPrismDocument(GlobalBytes, Candidate.GlobalDocument, DocumentError) then Exit;
  Reason := psrInstanceDocument;
  if not IndexPrismDocument(InstanceBytes, Candidate.InstanceDocument, DocumentError) then Exit;
  Reason := psrPerformanceGate;
  if not Gate(pmkOverridePerformance, Candidate.PerformanceGate) then Exit;
  Reason := psrEnvGate;
  if not Gate(pmkOverrideEnv, Candidate.EnvGate) then Exit;
  Reason := psrCommandsAliases;
  if Candidate.InstanceDocument.Managed[pmkOverrideCommands].Present and
    Candidate.InstanceDocument.Managed[pmkOverrideLaunchCmd].Present then Exit;
  CommandsKey := pmkOverrideCommands;
  if not Candidate.InstanceDocument.Managed[CommandsKey].Present and
    Candidate.InstanceDocument.Managed[pmkOverrideLaunchCmd].Present then
    CommandsKey := pmkOverrideLaunchCmd;
  Reason := psrCommandsGate;
  if not Gate(CommandsKey, Candidate.CommandsGate) then Exit;
  Reason := psrPerformanceValue;
  for Flag := Low(Flag) to High(Flag) do
  begin
    Select(PrismPerformanceManagedKeys[Flag], Candidate.PerformanceGate.Value,
      Candidate.Performance[Flag].GlobalRaw, Candidate.Performance[Flag].InstanceRaw,
      Candidate.Performance[Flag].Source, Selected);
    if Selected.Present and not DecodePrismBool(Selected.RawScalar,
      Candidate.Performance[Flag].Value, BoolError) then Exit;
  end;
  Reason := psrEnvValue;
  Select(pmkEnv, Candidate.EnvGate.Value, Candidate.Env.GlobalRaw,
    Candidate.Env.InstanceRaw, Candidate.Env.Source, Selected);
  if Selected.Present and not DecodePrismEnv(Selected.RawScalar,
    Candidate.Env.Entries, EnvError) then Exit;
  Select(pmkWrapperCommand, Candidate.CommandsGate.Value, Candidate.Wrapper.GlobalRaw,
    Candidate.Wrapper.InstanceRaw, Candidate.Wrapper.Source, Selected);
  if Selected.Present then Candidate.Wrapper.Value := Selected.DecodedScalar;
  for I := 0 to High(Candidate.Env.Entries) do
    if Candidate.Env.Entries[I].Key = 'MANGOHUD_CONFIG' then
    begin Reason := psrMangoHudConfig; Result := psaConflict; Exit; end;
  for I := 0 to High(Candidate.Env.Entries) do
    if Candidate.Env.Entries[I].Key = 'MANGOHUD_CONFIGFILE' then
    begin Reason := psrMangoHudSelector; Result := psaConflict; Exit; end;
  Reason := psrWrapperCommand;
  if Candidate.Wrapper.Value <> '' then Exit;
  Reason := psrPreload;
  for I := 0 to High(Candidate.Env.Entries) do
    if (Candidate.Env.Entries[I].Key = 'LD_PRELOAD') and
      (Candidate.Env.Entries[I].Value <> '') then Exit;
  Candidate.AmbientEnvironmentVerified := False;
  Snapshot := Candidate; Reason := psrNone; Result := psaReady;
end;
end.
