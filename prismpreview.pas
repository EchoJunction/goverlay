unit prismpreview;
{$mode objfpc}{$H+}
interface
uses prismprovider,prismsnapshot;
const PrismPreviewMetadataBudget=16*1024*1024;
type
  TPrismPreviewStatus=(ppsReady,ppsConflict,ppsUnsupported);
  TPrismPreviewReason=(pprNone,pprInvalidSelection,pprReadUnavailable,pprUnsafeRead,
    pprLimit,pprObservedChange,pprInvalidMetadata,pprIdentityChanged,pprAmbiguousIdentity,
    pprSettingsConflict,pprUnsupportedSettings);
  TPrismPreviewBool=record
    BeforeValue,ProposedValue,EffectiveChanges,SetsLocal:Boolean;
  end;
  TPrismPreviewDTO=record
    Status:TPrismPreviewStatus;
    Reason:TPrismPreviewReason;
    SettingsReason:TPrismAssessmentReason;
    Performance:array[TPrismPerformanceFlag] of TPrismPreviewBool;
    PerformanceGate,EnvGate:TPrismPreviewBool;
    PerformanceFreeze,EnvFreeze:Boolean;
    CopiedEnvEntryCount:SizeInt;
    SelectorAdded,PreservesUnrelated,AdvisoryOnly:Boolean;
    GeneratedSelector:string;
  end;
{ Inputs are a selected discovery identity and explicit profile data directory.
  Only that root's config/selected instance feed Assess/PlanEnable. Narrow extra
  immediate-instance metadata reads prove current UUID uniqueness, with pinned
  nofollow reads and conservative catalog byte/entry limits. No host discovery,
  account/game metadata, writes/locks or raw plan authority returned/retained.
  Result is advisory only: observed-change detection is not a coherent live
  snapshot, atomicity or CAS guarantee. Errors/logs never contain input data. }
function PreviewPrismEnable(const Selected:TPrismInstance;
  const HostDataDir:string):TPrismPreviewDTO;
implementation
uses gamecontext,prismdocument,prismplan,prismselectedreader;
function PreviewPrismEnable(const Selected:TPrismInstance;
  const HostDataDir:string):TPrismPreviewDTO;
var DTO:TPrismPreviewDTO; Documents:TPrismSelectedDocuments;
  Context:TActiveProfileContext; RR:TPrismSelectedReadReason;
  Snapshot:TPrismSettingsSnapshot; Plan:TPrismEnableProposal;
  AR:TPrismAssessmentReason; PR:TPrismEnableReason; Status:TPrismAssessmentStatus;
  F:TPrismPerformanceFlag;
  procedure Summary(var D:TPrismPreviewBool; Before,After,Sets:Boolean);
  begin D.BeforeValue:=Before; D.ProposedValue:=After; D.EffectiveChanges:=Before<>After; D.SetsLocal:=Sets; end;
begin
  DTO:=Default(TPrismPreviewDTO); DTO.Status:=ppsUnsupported;
  DTO.Reason:=pprInvalidSelection; DTO.AdvisoryOnly:=True;
  try
    if not ReadSelectedPrismDocuments(Selected,HostDataDir,Documents,RR) then
    begin
      case RR of
        psrrInvalidSelection:DTO.Reason:=pprInvalidSelection;
        psrrReadUnavailable:DTO.Reason:=pprReadUnavailable;
        psrrUnsafeRead:DTO.Reason:=pprUnsafeRead;
        psrrLimit:DTO.Reason:=pprLimit;
        psrrObservedChange:DTO.Reason:=pprObservedChange;
        psrrInvalidMetadata:DTO.Reason:=pprInvalidMetadata;
        psrrIdentityChanged:DTO.Reason:=pprIdentityChanged;
        psrrAmbiguousIdentity:DTO.Reason:=pprAmbiguousIdentity;
        else DTO.Reason:=pprUnsafeRead;
      end;
      Exit(DTO);
    end;
    if not PrismProfileContext(Documents.Current,HostDataDir,Context) then Exit(DTO);
    Status:=AssessPrismSettings(Documents.GlobalBytes,Documents.InstanceBytes,Snapshot,AR);
    if Status=psaReady then Status:=PlanPrismEnable(Documents.Current,HostDataDir,
      Context.ConfigDir+'MangoHud.conf',Snapshot,Plan,PR,AR);
    DTO.SettingsReason:=AR;
    if Status=psaConflict then
    begin DTO.Status:=ppsConflict; DTO.Reason:=pprSettingsConflict; Exit(DTO); end;
    if Status<>psaReady then begin DTO.Reason:=pprUnsupportedSettings; Exit(DTO); end;
    for F:=Low(F) to High(F) do
      Summary(DTO.Performance[F],Plan.BeforeSnapshot.Performance[F].Value,
        Plan.AppliedPerformance[F],Plan.Touched[PrismPerformanceManagedKeys[F]]);
    Summary(DTO.PerformanceGate,Plan.BeforeSnapshot.PerformanceGate.Value,
      Plan.AppliedPerformanceGate,Plan.Touched[pmkOverridePerformance]);
    Summary(DTO.EnvGate,Plan.BeforeSnapshot.EnvGate.Value,Plan.AppliedEnvGate,Plan.Touched[pmkOverrideEnv]);
    DTO.PerformanceFreeze:=Plan.PerformanceInheritanceFreeze; DTO.EnvFreeze:=Plan.EnvInheritanceFreeze;
    if Plan.EnvInheritanceFreeze then DTO.CopiedEnvEntryCount:=Length(Plan.BeforeSnapshot.Env.Entries);
    DTO.SelectorAdded:=Plan.OwnsSelector; DTO.PreservesUnrelated:=True;
    DTO.GeneratedSelector:=Plan.Selector; DTO.Status:=ppsReady; DTO.Reason:=pprNone;
  except
    DTO:=Default(TPrismPreviewDTO); DTO.Status:=ppsUnsupported;
    DTO.Reason:=pprUnsafeRead; DTO.AdvisoryOnly:=True;
  end;
  Result:=DTO;
end;
end.
