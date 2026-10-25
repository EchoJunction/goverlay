unit prism_performance_preview_test_cases;
{$mode objfpc}{$H+}
{$ifndef PRISM_PREVIEW_TESTS}{$fatal Preview tests require test hooks}{$endif}
interface
uses Classes,SysUtils,BaseUnix,SHA1,fpcunit,testregistry,prismprovider,
  prismdocument,prismreadonly,prismselectedreader,prismsnapshot,prismperformance,
  prismperformancepreview;
type
  TPrismPerformancePreviewTests=class(TTestCase)
  private
    Base,Root,Host:string;
    Selected:TPrismInstance;
    Baseline:TPrismPerformanceBaseline;
    Draft:TPrismPerformanceDraft;
    procedure Put(const Path,Data:string);
    function Tree(const Path:string):string;
    function Load:TPrismPerformanceDTO;
    function Preview:TPrismPerformanceDTO;
    procedure Local(const Extra:string);
    procedure Global(const Extra:string);
  protected
    procedure SetUp;override;
    procedure TearDown;override;
  published
    procedure ReadyTypedAndNoWrites;
    procedure EffectiveAndGateDriftStale;
    procedure DormantAndEquivalentRawDriftStale;
    procedure OpaqueUnrelatedChangesNotStale;
    procedure SelectionAndHostBoundBaseline;
    procedure ExplicitReloadRetainsRequestedDraft;
    procedure InitialInvalidAndChangedInvalid;
    procedure ExternalFolderAndDuplicateIdentity;
    procedure SymlinkFIFOAndLimits;
    procedure ObservedChangeRefuses;
    procedure NewBaselineAndFailureClear;
    procedure SanitizedSecretsAndNoMutation;
  end;
implementation
const H='[General]'#10'ConfigVersion=1.3'#10;
  U='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  Secret='PRIVATE_CANARY_NEVER_IN_SANITIZED_SUMMARY';
function MkDTemp(Template:PChar):PChar;cdecl;external 'c' name 'mkdtemp';
var ChangedPath:string;
procedure ChangeAfterRead(const Path:string);
var F:TFileStream; S:string;
begin
  if Path<>ChangedPath then Exit;
  PrismReadAfterReadHook:=nil; S:=H+'InstanceType=OneSix'#10'uuid='+U+#10'Changed=yes'#10;
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(S[1],Length(S)); finally F.Free; end;
end;
procedure TPrismPerformancePreviewTests.Put(const Path,Data:string);
var F:TFileStream;
begin
  ForceDirectories(ExtractFileDir(Path)); F:=TFileStream.Create(Path,fmCreate);
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data)); finally F.Free; end;
end;
function TPrismPerformancePreviewTests.Tree(const Path:string):string;
var Info:Stat; Search:TSearchRec; Entries:TStringList; I:Integer; S,Item:RawByteString;
  F:TFileStream;
begin
  AssertEquals(0,fpLStat(PChar(Path),Info)); S:=Path+'|'+IntToStr(Info.st_mode)+'|';
  if FPS_ISLNK(Info.st_mode) then S+=fpReadLink(Path)
  else if FPS_ISREG(Info.st_mode) then
  begin
    F:=TFileStream.Create(Path,fmOpenRead);
    try SetLength(Item,F.Size); if Item<>'' then F.ReadBuffer(Item[1],Length(Item)); finally F.Free; end;
    S+=SHA1Print(SHA1String(Item));
  end
  else if FPS_ISDIR(Info.st_mode) then
  begin
    Entries:=TStringList.Create;
    try
      if FindFirst(Path+'/*',faAnyFile or faSymLink,Search)=0 then
      try repeat if (Search.Name<>'.') and (Search.Name<>'..') then Entries.Add(Search.Name); until FindNext(Search)<>0;
      finally FindClose(Search); end;
      Entries.Sort;
      for I:=0 to Entries.Count-1 do S+=Tree(Path+'/'+Entries[I]);
    finally Entries.Free; end;
  end;
  Result:=SHA1Print(SHA1String(S));
end;
procedure TPrismPerformancePreviewTests.Local(const Extra:string);
begin Put(Selected.ConfigPath,H+'InstanceType=OneSix'#10'uuid='+Selected.UUID+#10+
  'name='+Secret+#10'JavaPath=/same/java'#10+Extra); end;
procedure TPrismPerformancePreviewTests.Global(const Extra:string);
begin Put(Root+'/prismlauncher.cfg',H+Extra); end;
function TPrismPerformancePreviewTests.Load:TPrismPerformanceDTO;
var Before:string;
begin
  Before:=Tree(Base); Result:=LoadPrismPerformanceBaseline(Selected,Host,Baseline);
  AssertEquals('Reader preserves whole synthetic tree',Before,Tree(Base));
end;
function TPrismPerformancePreviewTests.Preview:TPrismPerformanceDTO;
var Before:string;
begin
  Before:=Tree(Base); Result:=PreviewPrismPerformance(Selected,Host,Baseline,Draft);
  AssertEquals('Preview preserves whole synthetic tree',Before,Tree(Base));
end;
procedure TPrismPerformancePreviewTests.SetUp;
var S:string;
begin
  S:='/tmp/goverlay-performance-preview-XXXXXX'; UniqueString(S);
  AssertTrue(MkDTemp(PChar(S))<>nil); Base:=S; Root:=Base+'/Prism'; Host:=Base+'/profiles';
  Selected:=Default(TPrismInstance); Selected.DataRoot:=Root; Selected.Folder:='A';
  Selected.ConfigPath:=Root+'/instances/A/instance.cfg'; Selected.UUID:=U;
  Selected.InstallationKey:='prism-root-'+SHA1Print(SHA1String(Root));
  Selected.StableKey:='prism-'+SHA1Print(SHA1String(Root+#0+'uuid:'+U));
  Draft:=Default(TPrismPerformanceDraft); Global(''); Local('');
  Baseline:=Default(TPrismPerformanceBaseline); PrismReadAfterReadHook:=nil;
end;
procedure RemoveTree(const Path:string);
var Info:Stat; Search:TSearchRec; Item:string;
begin
  if FindFirst(Path+'/*',faAnyFile or faSymLink,Search)=0 then
  try repeat
    if (Search.Name='.') or (Search.Name='..') then Continue;
    Item:=Path+'/'+Search.Name; if fpLStat(PChar(Item),Info)<>0 then raise Exception.Create('Synthetic cleanup failed');
    if FPS_ISDIR(Info.st_mode) then RemoveTree(Item)
    else if fpUnlink(PChar(Item))<>0 then raise Exception.Create('Synthetic unlink failed');
  until FindNext(Search)<>0; finally FindClose(Search); end;
  if not RemoveDir(Path) then raise Exception.Create('Synthetic directory cleanup failed');
end;
procedure TPrismPerformancePreviewTests.TearDown;
begin PrismReadAfterReadHook:=nil; RemoveTree(Base); end;
procedure TPrismPerformancePreviewTests.ReadyTypedAndNoWrites;
var D:TPrismPerformanceDTO;
begin
  Global('UseDiscreteGpu=true'#10); D:=Load; AssertEquals(Ord(ppvsNoChanges),Ord(D.Status));
  AssertTrue(Baseline.Initialized); AssertTrue(Baseline.Current.Flags[ppfDiscreteGpu].Value);
  Draft.Group:=ppgInstance; Draft.Fields[pefZink]:=ppiOn; D:=Preview;
  AssertEquals(Ord(ppvsReady),Ord(D.Status)); AssertTrue(D.AdvisoryOnly);
  AssertTrue(D.InheritanceFreeze); AssertTrue(D.GateChanged); AssertTrue(D.PreservesUnrelated);
  AssertEquals(Ord(pesGlobal),Ord(D.Current.Flags[ppfDiscreteGpu].Source));
  AssertEquals(Ord(pesInstance),Ord(D.Proposed.Flags[ppfDiscreteGpu].Source));
  AssertTrue(D.Proposed.Flags[ppfZink].Value); AssertTrue(D.Proposed.Flags[ppfZink].LocalPresent);
end;
procedure TPrismPerformancePreviewTests.EffectiveAndGateDriftStale;
var D:TPrismPerformanceDTO;
begin
  Load; Global('UseZink=true'#10); D:=Preview;
  AssertEquals(Ord(ppvsStale),Ord(D.Status)); AssertEquals(Ord(ppvrStale),Ord(D.Reason));
  Load; Local('OverridePerformance=true'#10); D:=Preview;
  AssertEquals(Ord(ppvsStale),Ord(D.Status));
end;
procedure TPrismPerformancePreviewTests.DormantAndEquivalentRawDriftStale;
var D:TPrismPerformanceDTO;
begin
  Local('OverridePerformance=false'#10'UseZink=invalid-dormant'#10); Load;
  Local('OverridePerformance=false'#10'UseZink=changed-dormant'#10); D:=Preview;
  AssertEquals(Ord(ppvsStale),Ord(D.Status));
  Global('UseZink=false'#10); Load; Global('UseZink="false"'#10); D:=Preview;
  AssertEquals(Ord(ppvsStale),Ord(D.Status));
end;
procedure TPrismPerformancePreviewTests.OpaqueUnrelatedChangesNotStale;
var D:TPrismPerformanceDTO;
begin
  Load;
  Global('; changed comment'#10'OverridePerformance=ignored-metadata'#10'Env=invalid-json'#10);
  Local('Env=private-invalid-json'#10'WrapperCommand='+Secret+#10);
  Draft.Group:=ppgInstance; Draft.Fields[pefZink]:=ppiOn; D:=Preview;
  AssertEquals(Ord(ppvsReady),Ord(D.Status)); AssertTrue(D.PreservesUnrelated);
  Put(Selected.ConfigPath,StringReplace(H,#10,#13#10,[rfReplaceAll])+
    'InstanceType=OneSix'#13#10'uuid='+U+#13#10'; shifted offsets'#13#10);
  D:=Preview; AssertEquals(Ord(ppvsReady),Ord(D.Status));
end;
procedure TPrismPerformancePreviewTests.SelectionAndHostBoundBaseline;
var D:TPrismPerformanceDTO; A:TPrismInstance;
begin
  Load; A:=Selected; Selected.Folder:='B'; Selected.UUID:='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  Selected.ConfigPath:=Root+'/instances/B/instance.cfg';
  Selected.StableKey:='prism-'+SHA1Print(SHA1String(Root+#0+'uuid:'+Selected.UUID)); Local('');
  D:=Preview; AssertEquals(Ord(ppvsStale),Ord(D.Status));
  Selected:=A; Host:=Base+'/different-host'; D:=Preview;
  AssertEquals(Ord(ppvsStale),Ord(D.Status));
end;
procedure TPrismPerformancePreviewTests.ExplicitReloadRetainsRequestedDraft;
var D:TPrismPerformanceDTO;
begin
  Load; Draft.Group:=ppgInstance; Draft.Fields[pefFeralGamemode]:=ppiOn;
  Global('EnableMangoHud=true'#10); D:=Preview;
  AssertEquals(Ord(ppvsStale),Ord(D.Status)); AssertEquals(Ord(ppiOn),Ord(D.Requested.Fields[pefFeralGamemode]));
  AssertFalse(Baseline.Current.Flags[ppfMangoHud].Value);
  Load; AssertTrue(Baseline.Current.Flags[ppfMangoHud].Value); D:=Preview;
  AssertEquals(Ord(ppvsReady),Ord(D.Status)); AssertTrue(D.Proposed.Flags[ppfMangoHud].Value);
  AssertTrue(D.Proposed.Flags[ppfFeralGamemode].Value);
end;
procedure TPrismPerformancePreviewTests.InitialInvalidAndChangedInvalid;
var D:TPrismPerformanceDTO;
begin
  Global('UseZink=secret-invalid'#10); D:=Load;
  AssertEquals(Ord(ppvsUnsupported),Ord(D.Status)); AssertFalse(Baseline.Initialized);
  Global(''); Load; Global('UseZink=secret-invalid'#10); D:=Preview;
  AssertEquals(Ord(ppvsStale),Ord(D.Status)); AssertEquals(Ord(ppdrNone),Ord(D.SettingsReason));
  Global(''); Load; Put(Selected.ConfigPath,'invalid document'); D:=Preview;
  AssertEquals(Ord(ppvsUnsupported),Ord(D.Status));
end;
procedure TPrismPerformancePreviewTests.ExternalFolderAndDuplicateIdentity;
var D:TPrismPerformanceDTO;
begin
  Selected.ConfigPath:=Base+'/external/A/instance.cfg'; Selected.UUID:=''; Selected.UsesFolderIdentity:=True;
  Selected.StableKey:='prism-'+SHA1Print(SHA1String(Root+#0+'folder:'+Base+'/external/A'));
  Global('InstanceDir='+Base+'/external'#10); Local(''); D:=Load;
  AssertEquals(Ord(ppvsNoChanges),Ord(D.Status));
  Put(Base+'/external/B/instance.cfg',H+'InstanceType=OneSix'#10'uuid='+U+#10);
  Selected.UUID:=U; Selected.UsesFolderIdentity:=False;
  Selected.StableKey:='prism-'+SHA1Print(SHA1String(Root+#0+'uuid:'+U)); Local(''); D:=Load;
  AssertEquals(Ord(ppvsUnsupported),Ord(D.Status)); AssertEquals(Ord(psrrAmbiguousIdentity),Ord(D.ReadReason));
end;
procedure TPrismPerformancePreviewTests.SymlinkFIFOAndLimits;
var D:TPrismPerformanceDTO;
begin
  Load; AssertTrue(RenameFile(Selected.ConfigPath,Selected.ConfigPath+'.real'));
  AssertEquals(0,fpSymlink(PChar(Selected.ConfigPath+'.real'),PChar(Selected.ConfigPath)));
  D:=Preview; AssertEquals(Ord(ppvsUnsupported),Ord(D.Status));
  AssertEquals(0,fpUnlink(PChar(Selected.ConfigPath)));
  AssertEquals(0,fpMkFifo(PChar(Selected.ConfigPath),&600));
  D:=Preview; AssertEquals(Ord(ppvsUnsupported),Ord(D.Status));
  AssertEquals(0,fpUnlink(PChar(Selected.ConfigPath))); Local('');
  Global('Opaque='+StringOfChar('a',PrismDocumentMaxBytes)); D:=Preview;
  AssertEquals(Ord(ppvsUnsupported),Ord(D.Status)); AssertEquals(Ord(psrrLimit),Ord(D.ReadReason));
end;
procedure TPrismPerformancePreviewTests.ObservedChangeRefuses;
var D:TPrismPerformanceDTO;
begin
  Load; ChangedPath:=Selected.ConfigPath; PrismReadAfterReadHook:=@ChangeAfterRead;
  D:=PreviewPrismPerformance(Selected,Host,Baseline,Draft);
  AssertEquals(Ord(ppvsUnsupported),Ord(D.Status)); AssertEquals(Ord(psrrObservedChange),Ord(D.ReadReason));
end;
procedure TPrismPerformancePreviewTests.NewBaselineAndFailureClear;
var D:TPrismPerformanceDTO;
begin
  D:=Preview; AssertEquals(Ord(ppvsStale),Ord(D.Status));
  Load; AssertTrue(Baseline.Initialized); Selected.StableKey:='forged'; D:=Load;
  AssertFalse(Baseline.Initialized); AssertFalse(Baseline.Current.GatePresent);
  AssertEquals(Ord(ppvsUnsupported),Ord(D.Status)); AssertFalse(D.PreservesUnrelated);
end;
procedure TPrismPerformancePreviewTests.SanitizedSecretsAndNoMutation;
var D:TPrismPerformanceDTO; S:string; F:TPrismPerformanceFlag;
begin
  Global('Env='+Secret+#10'WrapperCommand='+Secret+#10); Local('Env='+Secret+#10);
  Load; Draft.Group:=ppgInstance; Draft.Fields[pefDiscreteGpu]:=ppiOn; D:=Preview;
  AssertEquals(Ord(ppvsReady),Ord(D.Status));
  { Every public DTO field is a fixed enum/Boolean/typed draft: no input strings,
    raw bytes, maps, paths or fingerprint field exists for a UI/log to render. }
  S:=IntToStr(Ord(D.Status))+IntToStr(Ord(D.Reason))+IntToStr(Ord(D.ReadReason))+
    IntToStr(Ord(D.SettingsReason))+IntToStr(Ord(D.Requested.Group));
  for F:=Low(F) to High(F) do S+=IntToStr(Ord(D.Current.Flags[F].Source));
  AssertEquals(0,Pos(Secret,S)); AssertEquals(Ord(ppiOn),Ord(Draft.Fields[pefDiscreteGpu]));
  AssertEquals(U,Selected.UUID); AssertFalse(Baseline.Current.GateValue);
end;
initialization RegisterTest(TPrismPerformancePreviewTests);
end.
