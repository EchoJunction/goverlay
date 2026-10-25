unit prismperformancepreview;
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
interface
uses prismprovider,prismsnapshot,prismperformance,prismselectedreader;
type
  TPrismPerformancePreviewStatus=(ppvsReady,ppvsNoChanges,ppvsStale,ppvsUnsupported);
  TPrismPerformancePreviewReason=(ppvrNone,ppvrRead,ppvrSettings,ppvrStale);
  TPrismPerformanceViewBool=record
    Value,LocalPresent:Boolean;
    Source:TPrismEffectiveSource;
  end;
  TPrismPerformanceView=record
    GateValue,GatePresent:Boolean;
    Flags:array[TPrismPerformanceFlag] of TPrismPerformanceViewBool;
  end;
  TPrismPerformanceBaseline=record
  private
    FGroupToken,FIdentityToken:string;
    FCurrent:TPrismPerformanceView;
    FInitialized:Boolean;
  public
    property Current:TPrismPerformanceView read FCurrent;
    property Initialized:Boolean read FInitialized;
  end;
  TPrismPerformanceDTO=record
    Status:TPrismPerformancePreviewStatus;
    Reason:TPrismPerformancePreviewReason;
    ReadReason:TPrismSelectedReadReason;
    SettingsReason:TPrismPerformanceDraftReason;
    Requested:TPrismPerformanceDraft;
    Current,Proposed:TPrismPerformanceView;
    EffectiveChanged:array[TPrismPerformanceFlag] of Boolean;
    InheritanceFreeze,GateChanged,PreservesUnrelated,AdvisoryOnly:Boolean;
  end;
{ Only typed sanitized summaries leave this adapter; no raw docs/maps/proposal,
  commands, keys/values, paths, token, ownership or publication authority.
  Explicit load creates a transient selected-identity-bound baseline. Relevant
  raw performance-group/provenance drift returns Stale before semantic decode,
  retaining the caller's draft/baseline until explicit reload. Unrelated fresh
  bytes do not stale. Pinned reads remain advisory, never coherent-live/CAS. }
function LoadPrismPerformanceBaseline(const Selected:TPrismInstance;
  const HostDataDir:string; out Baseline:TPrismPerformanceBaseline):TPrismPerformanceDTO;
function PreviewPrismPerformance(const Selected:TPrismInstance;
  const HostDataDir:string; const Baseline:TPrismPerformanceBaseline;
  const Draft:TPrismPerformanceDraft):TPrismPerformanceDTO;
implementation
uses SHA1,SysUtils,prismdocument;
function View(const State:TPrismPerformanceState):TPrismPerformanceView;
var F:TPrismPerformanceFlag;
begin
  Result:=Default(TPrismPerformanceView); Result.GateValue:=State.Gate.Value;
  Result.GatePresent:=State.Gate.Raw.Present;
  for F:=Low(F) to High(F) do
  begin
    Result.Flags[F].Value:=State.Flags[F].Value;
    Result.Flags[F].Source:=State.Flags[F].Source;
    Result.Flags[F].LocalPresent:=State.Flags[F].InstanceRaw.Present;
  end;
end;
procedure Part(var Buffer:RawByteString; const Value:RawByteString);
begin Buffer+=IntToStr(Length(Value))+':'+Value; end;
function IdentityToken(const D:TPrismSelectedDocuments; const Host:string):string;
var S:RawByteString;
begin
  S:=''; Part(S,D.Current.DataRoot); Part(S,D.Current.ConfigPath);
  Part(S,D.Current.StableKey); Part(S,D.Current.InstallationKey); Part(S,Host);
  Result:=SHA1Print(SHA1String(S));
end;
function GroupToken(const G,I:TPrismDocument):string;
var S:RawByteString; F:TPrismPerformanceFlag;
  procedure Add(const V:TPrismIndexedValue);
  begin
    if V.Present then S+='1' else S+='0';
    Part(S,V.RawScalar);
  end;
begin
  S:='';
  for F:=Low(F) to High(F) do Add(G.Managed[PrismPerformanceManagedKeys[F]]);
  for F:=Low(F) to High(F) do Add(I.Managed[PrismPerformanceManagedKeys[F]]);
  Add(I.Managed[pmkOverridePerformance]); Result:=SHA1Print(SHA1String(S));
end;
function EmptyDTO(const Draft:TPrismPerformanceDraft):TPrismPerformanceDTO;
begin
  Result:=Default(TPrismPerformanceDTO); Result.Status:=ppvsUnsupported;
  Result.AdvisoryOnly:=True; Result.Requested:=Draft;
end;
function ReadIndexed(const Selected:TPrismInstance; const Host:string;
  out Documents:TPrismSelectedDocuments; out G,I:TPrismDocument;
  var DTO:TPrismPerformanceDTO):Boolean;
var E:TPrismDocumentError;
begin
  Result:=False; DTO.Reason:=ppvrRead;
  if not ReadSelectedPrismDocuments(Selected,Host,Documents,DTO.ReadReason) then Exit;
  DTO.Reason:=ppvrSettings; DTO.SettingsReason:=ppdrGlobalDocument;
  if not IndexPrismDocument(Documents.GlobalBytes,G,E) then Exit;
  DTO.SettingsReason:=ppdrInstanceDocument;
  if not IndexPrismDocument(Documents.InstanceBytes,I,E) then Exit;
  DTO.SettingsReason:=ppdrNone; DTO.Reason:=ppvrNone; Result:=True;
end;
procedure Summary(const P:TPrismPerformanceProposal; S:TPrismPerformanceDraftStatus;
  var DTO:TPrismPerformanceDTO);
var F:TPrismPerformanceFlag;
begin
  DTO.Current:=View(P.Current); DTO.Proposed:=View(P.Proposed);
  for F:=Low(F) to High(F) do DTO.EffectiveChanged[F]:=P.EffectiveChanged[F];
  DTO.InheritanceFreeze:=P.InheritanceFreeze; DTO.GateChanged:=P.GateChanged;
  DTO.PreservesUnrelated:=True; DTO.Reason:=ppvrNone;
  if S=ppdsNoChanges then DTO.Status:=ppvsNoChanges else DTO.Status:=ppvsReady;
end;
function LoadPrismPerformanceBaseline(const Selected:TPrismInstance;
  const HostDataDir:string; out Baseline:TPrismPerformanceBaseline):TPrismPerformanceDTO;
var DTO:TPrismPerformanceDTO; Draft:TPrismPerformanceDraft;
  Docs:TPrismSelectedDocuments; G,I:TPrismDocument;
  Plan:TPrismPerformanceProposal; Status:TPrismPerformanceDraftStatus;
begin
  Baseline:=Default(TPrismPerformanceBaseline); Draft:=Default(TPrismPerformanceDraft);
  DTO:=EmptyDTO(Draft);
  try
    if not ReadIndexed(Selected,HostDataDir,Docs,G,I,DTO) then Exit(DTO);
    Status:=PlanPrismPerformance(Docs.GlobalBytes,Docs.InstanceBytes,Draft,Plan,DTO.SettingsReason);
    if Status=ppdsUnsupported then begin DTO.Reason:=ppvrSettings; Exit(DTO); end;
    Summary(Plan,Status,DTO); Baseline.FCurrent:=DTO.Current;
    Baseline.FIdentityToken:=IdentityToken(Docs,HostDataDir);
    Baseline.FGroupToken:=GroupToken(G,I); Baseline.FInitialized:=True;
  except
    Baseline:=Default(TPrismPerformanceBaseline); DTO:=EmptyDTO(Draft);
    DTO.Reason:=ppvrRead; DTO.ReadReason:=psrrUnsafeRead;
  end;
  Result:=DTO;
end;
function PreviewPrismPerformance(const Selected:TPrismInstance;
  const HostDataDir:string; const Baseline:TPrismPerformanceBaseline;
  const Draft:TPrismPerformanceDraft):TPrismPerformanceDTO;
var DTO:TPrismPerformanceDTO; Docs:TPrismSelectedDocuments; G,I:TPrismDocument;
  Plan:TPrismPerformanceProposal; Status:TPrismPerformanceDraftStatus;
begin
  DTO:=EmptyDTO(Draft);
  try
    if not ReadIndexed(Selected,HostDataDir,Docs,G,I,DTO) then Exit(DTO);
    if not Baseline.FInitialized or
      (Baseline.FIdentityToken<>IdentityToken(Docs,HostDataDir)) or
      (Baseline.FGroupToken<>GroupToken(G,I)) then
    begin DTO.Status:=ppvsStale; DTO.Reason:=ppvrStale; Exit(DTO); end;
    Status:=PlanPrismPerformance(Docs.GlobalBytes,Docs.InstanceBytes,Draft,Plan,DTO.SettingsReason);
    if Status=ppdsUnsupported then begin DTO.Reason:=ppvrSettings; Exit(DTO); end;
    Summary(Plan,Status,DTO);
  except
    DTO:=EmptyDTO(Draft); DTO.Reason:=ppvrRead; DTO.ReadReason:=psrrUnsafeRead;
  end;
  Result:=DTO;
end;
end.
