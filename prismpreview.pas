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
uses Classes,SysUtils,SHA1,gamecontext,prismreadonly,prismdocument,prismplan;
function PreviewPrismEnable(const Selected:TPrismInstance;
  const HostDataDir:string):TPrismPreviewDTO;
var DTO:TPrismPreviewDTO; Current:TPrismInstance; Context:TActiveProfileContext;
  Global,Raw,Local:RawByteString; C,InstanceRoot,EntryPath,Expected,UUID,Identity:string;
  Names:TPrismEntryNames; Stamps:array of TPrismNodeStamp;
  Stamp:TPrismNodeStamp; RE:TPrismReadError; ME:TPrismMetadataError;
  Settings:TStringList; Snapshot:TPrismSettingsSnapshot; Plan:TPrismEnableProposal;
  AR:TPrismAssessmentReason; PR:TPrismEnableReason; Status:TPrismAssessmentStatus;
  I,N,BytesRead,Matches,Found:SizeInt; F:TPrismPerformanceFlag;
  procedure Keep(const S:TPrismNodeStamp);
  begin N:=Length(Stamps); SetLength(Stamps,N+1); Stamps[N]:=S; end;
  function FailRead:Boolean;
  begin
    case RE of
      preUnavailable:DTO.Reason:=pprReadUnavailable;
      preUnsafe,preInvalidPath:DTO.Reason:=pprUnsafeRead;
      preLimit:DTO.Reason:=pprLimit;
      preChanged:DTO.Reason:=pprObservedChange;
      else DTO.Reason:=pprUnsafeRead;
    end;
    FailRead:=False;
  end;
  function ReadMetadata(const Path:string; out Bytes:RawByteString):Boolean;
  var Allowed:SizeInt;
  begin
    ReadMetadata:=False;
    Allowed:=PrismPreviewMetadataBudget-BytesRead;
    if Allowed<=0 then begin DTO.Reason:=pprLimit; Exit; end;
    if Allowed>PrismDocumentMaxBytes then Allowed:=PrismDocumentMaxBytes;
    if not ReadPrismFile(Path,Allowed,Bytes,Stamp,RE) then
    begin FailRead; Exit; end;
    Inc(BytesRead,Length(Bytes));
    if BytesRead>PrismPreviewMetadataBudget then begin DTO.Reason:=pprLimit; Exit; end;
    Keep(Stamp); Settings.Clear;
    if not ParsePrismMetadata(Bytes,Settings,ME) then
    begin DTO.Reason:=pprInvalidMetadata; Exit; end;
    ReadMetadata:=True;
  end;
  procedure Summary(var D:TPrismPreviewBool; Before,After,Sets:Boolean);
  begin D.BeforeValue:=Before; D.ProposedValue:=After; D.EffectiveChanges:=Before<>After; D.SetsLocal:=Sets; end;
begin
  DTO:=Default(TPrismPreviewDTO); DTO.Status:=ppsUnsupported;
  DTO.Reason:=pprInvalidSelection; DTO.AdvisoryOnly:=True;
  Settings:=nil;
  try
   try
    if not CanonicalPrismPath(Selected.DataRoot,C,False) or (C<>Selected.DataRoot) or
      not CanonicalPrismPath(Selected.ConfigPath,C,False) or (C<>Selected.ConfigPath) or
      not CanonicalPrismPath(HostDataDir,C,False) or (C<>HostDataDir) or
      not PrismProfileContext(Selected,HostDataDir,Context) or
      (Selected.Folder='') or (Selected.Folder='.') or (Selected.Folder='..') or
      (Pos('/',Selected.Folder)>0) or (Pos(#0,Selected.Folder)>0) then Exit;
    Settings:=TStringList.Create; Settings.CaseSensitive:=True;
    BytesRead:=0; Matches:=0; Found:=0; Stamps:=nil;
    if not ReadMetadata(IncludeTrailingPathDelimiter(Selected.DataRoot)+'prismlauncher.cfg',Global) then Exit;
    InstanceRoot:=Settings.Values['InstanceDir']; if InstanceRoot='' then InstanceRoot:='instances';
    if InstanceRoot[1]<>'/' then InstanceRoot:=IncludeTrailingPathDelimiter(Selected.DataRoot)+InstanceRoot;
    if not CanonicalPrismPath(InstanceRoot,C,False) then begin DTO.Reason:=pprInvalidMetadata; Exit; end;
    InstanceRoot:=C; Expected:=IncludeTrailingPathDelimiter(InstanceRoot)+Selected.Folder+'/instance.cfg';
    if Expected<>Selected.ConfigPath then begin DTO.Reason:=pprIdentityChanged; Exit; end;
    if not ListPrismDirectory(InstanceRoot,PrismMaxEntries,Names,Stamp,RE) then begin FailRead; Exit; end;
    Keep(Stamp);
    for I:=0 to High(Names) do
    begin
      EntryPath:=IncludeTrailingPathDelimiter(InstanceRoot)+Names[I];
      if not InspectPrismNode(EntryPath,Stamp,RE) then begin FailRead; Exit; end;
      Keep(Stamp); if Stamp.Kind<>pnDirectory then Continue;
      if not ReadMetadata(EntryPath+'/instance.cfg',Raw) then Exit;
      if Settings.Values['InstanceType']<>'OneSix' then Continue;
      UUID:=LowerCase(Settings.Values['uuid']);
      if UUID<>'' then
      begin
        if Length(UUID)<>32 then begin DTO.Reason:=pprInvalidMetadata; Exit; end;
        for N:=1 to Length(UUID) do if not (UUID[N] in ['0'..'9','a'..'f']) then
        begin DTO.Reason:=pprInvalidMetadata; Exit; end;
        if UUID=Selected.UUID then Inc(Matches);
      end;
      if EntryPath+'/instance.cfg'=Expected then
      begin
        Inc(Found); Current:=Selected; Current.UUID:=UUID; Current.UsesFolderIdentity:=UUID='';
        Current.InstallationKey:='prism-root-'+SHA1Print(SHA1String(Selected.DataRoot));
        if UUID='' then Identity:='folder:'+EntryPath else Identity:='uuid:'+UUID;
        Current.StableKey:='prism-'+SHA1Print(SHA1String(Selected.DataRoot+#0+Identity));
        Local:=Raw;
      end;
    end;
    DTO.Reason:=pprIdentityChanged;
    if (Found<>1) or (Current.UUID<>Selected.UUID) or
      (Current.UsesFolderIdentity<>Selected.UsesFolderIdentity) or
      (Current.StableKey<>Selected.StableKey) or (Current.InstallationKey<>Selected.InstallationKey) then Exit;
    if (Current.UUID<>'') and (Matches<>1) then begin DTO.Reason:=pprAmbiguousIdentity; Exit; end;
    for I:=0 to High(Stamps) do
      if not RecheckPrismNode(Stamps[I],RE) then begin FailRead; Exit; end;
    Status:=AssessPrismSettings(Global,Local,Snapshot,AR);
    if Status=psaReady then Status:=PlanPrismEnable(Current,HostDataDir,
      Context.ConfigDir+'MangoHud.conf',Snapshot,Plan,PR,AR);
    DTO.SettingsReason:=AR;
    if Status=psaConflict then
    begin DTO.Status:=ppsConflict; DTO.Reason:=pprSettingsConflict; Exit; end;
    if Status<>psaReady then begin DTO.Reason:=pprUnsupportedSettings; Exit; end;
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
  finally
    Settings.Free; Result:=DTO;
  end;
end;
end.
