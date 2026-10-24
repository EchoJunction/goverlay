unit prism_preview_test_cases;
{$mode objfpc}{$H+}{$codepage utf8}
{$ifndef PRISM_PREVIEW_TESTS}{$fatal Preview safety tests require -dPRISM_PREVIEW_TESTS}{$endif}
interface
uses Classes,SysUtils,BaseUnix,SHA1,fpcunit,testregistry,prismprovider,prismdocument,
  prismenv,prismreadonly,prismpreview,prismsnapshot;
type
  TPrismPreviewTests=class(TTestCase)
  private
    Base,Root,Host:string;
    Device,Inode:QWord;
    Selected:TPrismInstance;
    procedure Put(const Path,Data:string);
    function Bytes(const Path:string):RawByteString;
    function Tree(const Path:string):string;
    procedure AddInstance(const Folder,UUID:string);
    function Preview:TPrismPreviewDTO;
    procedure Refuses(Status:TPrismPreviewStatus; Reason:TPrismPreviewReason);
  protected
    procedure SetUp;override;
    procedure TearDown;override;
  published
    procedure ReadySanitizedAndReadOnly;
    procedure ConflictAndUnsupportedAreSecretSafe;
    procedure MissingInvalidAndIdentityReplacement;
    procedure ExternalFolderIdentity;
    procedure DuplicateUUIDAndUnknownCatalog;
    procedure AncestorAndFinalSymlinks;
    procedure FIFOAndDirectoryAreRefused;
    procedure FileAndAggregateBounds;
    procedure DirectoryListingBounds;
    procedure ObservedGrowthAndReplacement;
    procedure ObservedCatalogAndSiblingChanges;
    procedure SafeReaderRefusalClearsOutput;
    procedure SameJavaABAndInputPreservation;
  end;
implementation
function MkDTemp(Template:PChar):PChar;cdecl;external 'c' name 'mkdtemp';
const Header='[General]'#10'ConfigVersion=1.3'#10;
  U1='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  Secret='SYNTHETIC_SECRET_MUST_NEVER_ENTER_DTO';
var HookMode:Integer; HookPath,HookBase,FirstMetadata:string; ObservedReads:TStringList;
procedure PreviewReadHook(const Path:string);
var F:TFileStream; C:Char;
  procedure Write(const Target:string; const Data:RawByteString);
  begin
    F:=TFileStream.Create(Target,fmCreate);
    try if Data<>'' then F.WriteBuffer(Data[1],Length(Data)); finally F.Free; end;
  end;
begin
  if ObservedReads<>nil then ObservedReads.Add(Path);
  if HookMode=5 then
  begin
    if ExtractFileName(Path)<>'instance.cfg' then Exit;
    if FirstMetadata='' then FirstMetadata:=Path
    else begin Write(FirstMetadata,Header+'InstanceType=OneSix'#10'uuid='+U1+#10'; external changed'); HookMode:=0; end;
    Exit;
  end;
  if Path<>HookPath then Exit;
  case HookMode of
    1:Write(Path,Header+'InstanceType=OneSix'#10'uuid='+U1+#10'Extra=growth');
    2:begin RenameFile(Path,Path+'.old'); Write(Path,Header+'InstanceType=OneSix'#10'uuid='+U1+#10); end;
    3:ForceDirectories(HookBase+'/instances/New');
    4:begin RenameFile(HookBase+'/instances',HookBase+'/moved'); ForceDirectories(HookBase+'/instances'); end;
    6:begin F:=TFileStream.Create(Path,fmOpenReadWrite); try F.Position:=F.Size-1; C:=' '; F.WriteBuffer(C,1); finally F.Free; end; end;
  end;
  HookMode:=0;
end;
procedure TPrismPreviewTests.Put(const Path,Data:string);
var F:TFileStream;
begin
  ForceDirectories(ExtractFileDir(Path)); F:=TFileStream.Create(Path,fmCreate);
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data)); finally F.Free; end;
end;
function TPrismPreviewTests.Bytes(const Path:string):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead);
  try SetLength(Result,F.Size); if Result<>'' then F.ReadBuffer(Result[1],Length(Result)); finally F.Free; end;
end;
function TPrismPreviewTests.Tree(const Path:string):string;
var Info:Stat; Search:TSearchRec; Entries:TStringList; I:Integer; Item,Data:string;
begin
  AssertEquals(0,fpLStat(PChar(Path),Info));
  Data:=Path+'|'+IntToStr(Info.st_mode)+'|';
  if FPS_ISLNK(Info.st_mode) then Data+=fpReadLink(Path)
  else if FPS_ISREG(Info.st_mode) then Data+=SHA1Print(SHA1String(Bytes(Path)))
  else if FPS_ISDIR(Info.st_mode) then
  begin
    Entries:=TStringList.Create;
    try
      if FindFirst(Path+'/*',faAnyFile,Search)=0 then
      try repeat if (Search.Name<>'.') and (Search.Name<>'..') then Entries.Add(Search.Name); until FindNext(Search)<>0;
      finally FindClose(Search); end;
      Entries.Sort;
      for I:=0 to Entries.Count-1 do begin Item:=Path+'/'+Entries[I]; Data+=Tree(Item); end;
    finally Entries.Free; end;
  end;
  Result:=SHA1Print(SHA1String(Data));
end;
procedure TPrismPreviewTests.AddInstance(const Folder,UUID:string);
begin
  Put(Root+'/instances/'+Folder+'/instance.cfg',Header+'InstanceType=OneSix'#10'uuid='+UUID+#10+
    'name='+Secret+#10'JavaPath=/same/java'#10);
end;
procedure TPrismPreviewTests.SetUp;
var Template:string; Info:Stat;
begin
  Template:='/tmp/goverlay-prism-preview-XXXXXX'; UniqueString(Template);
  AssertTrue(MkDTemp(PChar(Template))<>nil); Base:=Template;
  AssertEquals(0,fpLStat(PChar(Base),Info)); Device:=Info.st_dev; Inode:=Info.st_ino;
  Root:=Base+'/Prism'; Host:=Base+'/profiles'; Put(Root+'/prismlauncher.cfg',Header);
  AddInstance('A',U1); Selected:=Default(TPrismInstance);
  Selected.DataRoot:=Root; Selected.Folder:='A'; Selected.ConfigPath:=Root+'/instances/A/instance.cfg';
  Selected.UUID:=U1; Selected.InstallationKey:='prism-root-'+SHA1Print(SHA1String(Root));
  Selected.StableKey:='prism-'+SHA1Print(SHA1String(Root+#0+'uuid:'+U1));
  HookMode:=0; FirstMetadata:=''; HookBase:=Root; HookPath:=Selected.ConfigPath; ObservedReads:=TStringList.Create;
end;
procedure RemoveTree(const Path:string);
var Search:TSearchRec; Info:Stat; Item:string;
begin
  if FindFirst(Path+'/*',faAnyFile,Search)=0 then
  try
    repeat
      if (Search.Name='.') or (Search.Name='..') then Continue;
      Item:=Path+'/'+Search.Name;
      if fpLStat(PChar(Item),Info)<>0 then raise Exception.Create('Synthetic cleanup failed');
      if FPS_ISDIR(Info.st_mode) then RemoveTree(Item)
      else if fpUnlink(PChar(Item))<>0 then raise Exception.Create('Synthetic unlink failed');
    until FindNext(Search)<>0;
  finally FindClose(Search); end;
  if not RemoveDir(Path) then raise Exception.Create('Synthetic directory cleanup failed');
end;
procedure TPrismPreviewTests.TearDown;
var Info:Stat;
begin
  PrismReadAfterReadHook:=nil; FreeAndNil(ObservedReads);
  AssertTrue(Copy(Base,1,28)='/tmp/goverlay-prism-preview-');
  AssertEquals(0,fpLStat(PChar(Base),Info)); AssertTrue(FPS_ISDIR(Info.st_mode));
  AssertTrue((Info.st_dev=Device) and (Info.st_ino=Inode) and (Info.st_uid=fpGetUID));
  RemoveTree(Base);
end;
function TPrismPreviewTests.Preview:TPrismPreviewDTO;
var Before,Key,Path:string;
begin
  Before:=Tree(Base); Key:=Selected.StableKey; Path:=Selected.ConfigPath;
  Result:=PreviewPrismEnable(Selected,Host);
  AssertEquals('No synthetic tree writes',Before,Tree(Base));
  AssertEquals(Key,Selected.StableKey); AssertEquals(Path,Selected.ConfigPath);
  AssertFalse('No profile directory creation',DirectoryExists(Host));
end;
function DTOText(const D:TPrismPreviewDTO):string;
var F:TPrismPerformanceFlag;
begin
  Result:=IntToStr(Ord(D.Status))+IntToStr(Ord(D.Reason))+IntToStr(Ord(D.SettingsReason))+
    D.GeneratedSelector+IntToStr(D.CopiedEnvEntryCount);
  for F:=Low(F) to High(F) do Result+=BoolToStr(D.Performance[F].BeforeValue)+BoolToStr(D.Performance[F].ProposedValue);
end;
procedure TPrismPreviewTests.Refuses(Status:TPrismPreviewStatus; Reason:TPrismPreviewReason);
var D:TPrismPreviewDTO; F:TPrismPerformanceFlag;
begin
  D:=Preview; AssertEquals(Ord(Status),Ord(D.Status)); AssertEquals(Ord(Reason),Ord(D.Reason));
  AssertTrue(D.AdvisoryOnly); AssertFalse(D.SelectorAdded); AssertFalse(D.PreservesUnrelated);
  AssertFalse(D.PerformanceFreeze); AssertFalse(D.EnvFreeze); AssertEquals(0,D.CopiedEnvEntryCount);
  AssertEquals('',D.GeneratedSelector);
  for F:=Low(F) to High(F) do
  begin AssertFalse(D.Performance[F].BeforeValue); AssertFalse(D.Performance[F].ProposedValue); AssertFalse(D.Performance[F].SetsLocal); end;
  AssertTrue('No secret-bearing DTO',Pos(Secret,DTOText(D))=0);
end;
procedure TPrismPreviewTests.ReadySanitizedAndReadOnly;
var M:TPrismEnvMap; Raw:RawByteString; E:TPrismEnvError; D:TPrismPreviewDTO;
begin
  SetLength(M,1); M[0].Key:=Secret; M[0].Value:=Secret+' 日本語'+#0#10;
  AssertTrue(EncodePrismEnv(M,Raw,E)); Put(Root+'/prismlauncher.cfg',Header+'Env='+Raw+#10'UseDiscreteGpu=true'#10);
  Put(Selected.ConfigPath,Bytes(Selected.ConfigPath)+'WrapperCommand='+Secret+#10);
  Put(Root+'/accounts.json',Secret); Put(Root+'/instances/A/mmc-pack.json',Secret);
  PrismReadAfterReadHook:=@PreviewReadHook;
  D:=Preview; AssertEquals(Ord(ppsReady),Ord(D.Status)); AssertEquals(Ord(pprNone),Ord(D.Reason));
  AssertTrue(D.Performance[ppfMangoHud].EffectiveChanges); AssertTrue(D.Performance[ppfDiscreteGpu].BeforeValue);
  AssertTrue(D.Performance[ppfDiscreteGpu].ProposedValue); AssertTrue(D.Performance[ppfDiscreteGpu].SetsLocal);
  AssertTrue(D.PerformanceFreeze); AssertTrue(D.EnvFreeze); AssertEquals(1,D.CopiedEnvEntryCount);
  AssertTrue(D.SelectorAdded and D.PreservesUnrelated and D.AdvisoryOnly);
  AssertTrue(Pos(Host+'/goverlay/gameconfig/prism/',D.GeneratedSelector)=1);
  AssertTrue(Pos(Secret,DTOText(D))=0);
  AssertEquals(-1,ObservedReads.IndexOf(Root+'/accounts.json'));
  AssertEquals(-1,ObservedReads.IndexOf(Root+'/instances/A/mmc-pack.json'));
end;
procedure TPrismPreviewTests.ConflictAndUnsupportedAreSecretSafe;
var M:TPrismEnvMap; Raw:RawByteString; E:TPrismEnvError;
begin
  SetLength(M,1); M[0].Key:='MANGOHUD_CONFIGFILE'; M[0].Value:=Secret;
  AssertTrue(EncodePrismEnv(M,Raw,E)); Put(Root+'/prismlauncher.cfg',Header+'Env='+Raw+#10);
  Refuses(ppsConflict,pprSettingsConflict);
  Put(Root+'/prismlauncher.cfg',Header+'WrapperCommand='+Secret+#10);
  Refuses(ppsUnsupported,pprUnsupportedSettings);
  Put(Root+'/prismlauncher.cfg',Header+'EnableMangoHud='+Secret+#10);
  Refuses(ppsUnsupported,pprUnsupportedSettings);
end;
procedure TPrismPreviewTests.MissingInvalidAndIdentityReplacement;
begin
  DeleteFile(Root+'/prismlauncher.cfg'); Refuses(ppsUnsupported,pprReadUnavailable);
  Put(Root+'/prismlauncher.cfg','[General]'#10'ConfigVersion=1.2'#10); Refuses(ppsUnsupported,pprInvalidMetadata);
  Put(Root+'/prismlauncher.cfg',Header); AddInstance('A',StringOfChar('b',32)); Refuses(ppsUnsupported,pprIdentityChanged);
  AddInstance('A',U1); Selected.StableKey:='bad'; Refuses(ppsUnsupported,pprInvalidSelection);
end;
procedure TPrismPreviewTests.ExternalFolderIdentity;
var D:TPrismPreviewDTO; ExternalDir:string;
begin
  ExternalDir:=Base+'/external'; AssertTrue(RenameFile(Root+'/instances',ExternalDir));
  Put(Root+'/prismlauncher.cfg',Header+'InstanceDir='+ExternalDir+#10);
  Put(ExternalDir+'/A/instance.cfg',Header+'InstanceType=OneSix'#10'name='+Secret+#10);
  Selected.ConfigPath:=ExternalDir+'/A/instance.cfg'; Selected.UUID:=''; Selected.UsesFolderIdentity:=True;
  Selected.StableKey:='prism-'+SHA1Print(SHA1String(Root+#0+'folder:'+ExternalDir+'/A'));
  D:=Preview; AssertEquals(Ord(ppsReady),Ord(D.Status));
end;
procedure TPrismPreviewTests.DuplicateUUIDAndUnknownCatalog;
begin
  AddInstance('B',U1); Refuses(ppsUnsupported,pprAmbiguousIdentity);
  AddInstance('B',StringOfChar('b',32)); DeleteFile(Root+'/instances/B/instance.cfg'); Refuses(ppsUnsupported,pprReadUnavailable);
  Put(Root+'/instances/B/instance.cfg',Header+'InstanceType=OneSix'#10'uuid=invalid'#10); Refuses(ppsUnsupported,pprInvalidMetadata);
end;
procedure TPrismPreviewTests.AncestorAndFinalSymlinks;
var Original,Alias:string;
begin
  Original:=Selected.ConfigPath; AssertTrue(RenameFile(Original,Original+'.real'));
  AssertEquals(0,fpSymlink(PChar(Original+'.real'),PChar(Original))); Refuses(ppsUnsupported,pprUnsafeRead);
  fpUnlink(PChar(Original)); AssertTrue(RenameFile(Original+'.real',Original));
  Alias:=Base+'/alias'; AssertEquals(0,fpSymlink(PChar(Root),PChar(Alias)));
  Selected.DataRoot:=Alias; Selected.ConfigPath:=Alias+'/instances/A/instance.cfg';
  Refuses(ppsUnsupported,pprUnsafeRead);
end;
procedure TPrismPreviewTests.FIFOAndDirectoryAreRefused;
var Started:QWord;
begin
  DeleteFile(Selected.ConfigPath); AssertEquals(0,fpMkFifo(PChar(Selected.ConfigPath),&600));
  Started:=GetTickCount64; Refuses(ppsUnsupported,pprUnsafeRead); AssertTrue(GetTickCount64-Started<1000);
  fpUnlink(PChar(Selected.ConfigPath)); AssertTrue(CreateDir(Selected.ConfigPath)); Refuses(ppsUnsupported,pprUnsafeRead);
end;
procedure TPrismPreviewTests.FileAndAggregateBounds;
var I:Integer; Data:string;
begin
  Put(Root+'/prismlauncher.cfg',Header+StringOfChar('x',PrismDocumentMaxBytes)); Refuses(ppsUnsupported,pprLimit);
  Put(Root+'/prismlauncher.cfg',Header);
  for I:=0 to 15 do
  begin
    if I=0 then Data:=Header+'InstanceType=OneSix'#10'uuid='+U1+#10
    else Data:=Header+'InstanceType=OneSix'#10'uuid='+LowerCase(IntToHex(I,32))+#10;
    Data+=';'+StringOfChar('x',PrismDocumentMaxBytes-Length(Data)-1);
    if I=0 then Put(Selected.ConfigPath,Data) else Put(Root+'/instances/B'+IntToStr(I)+'/instance.cfg',Data);
  end;
  Refuses(ppsUnsupported,pprLimit);
end;
procedure TPrismPreviewTests.DirectoryListingBounds;
var Names:TPrismEntryNames; Stamp:TPrismNodeStamp; E:TPrismReadError;
begin
  AddInstance('B',StringOfChar('b',32));
  AssertFalse(ListPrismDirectory(Root+'/instances',1,Names,Stamp,E));
  AssertEquals(Ord(preLimit),Ord(E)); AssertEquals(0,Length(Names)); AssertEquals('',Stamp.Path);
end;
procedure TPrismPreviewTests.ObservedGrowthAndReplacement;
var D:TPrismPreviewDTO; I:Integer;
begin
  for I:=1 to 3 do
  begin
    AddInstance('A',U1); if I=3 then HookMode:=6 else HookMode:=I; PrismReadAfterReadHook:=@PreviewReadHook;
    D:=PreviewPrismEnable(Selected,Host); AssertEquals(Ord(ppsUnsupported),Ord(D.Status)); AssertEquals(Ord(pprObservedChange),Ord(D.Reason));
    AssertEquals('',D.GeneratedSelector); AssertFalse(D.SelectorAdded); PrismReadAfterReadHook:=nil;
  end;
end;
procedure TPrismPreviewTests.ObservedCatalogAndSiblingChanges;
var D:TPrismPreviewDTO;
begin
  HookMode:=3; PrismReadAfterReadHook:=@PreviewReadHook;
  D:=PreviewPrismEnable(Selected,Host); AssertEquals(Ord(pprObservedChange),Ord(D.Reason));
  PrismReadAfterReadHook:=nil; RemoveTree(Root+'/instances/New'); AddInstance('B',StringOfChar('b',32));
  HookMode:=5; FirstMetadata:=''; PrismReadAfterReadHook:=@PreviewReadHook;
  D:=PreviewPrismEnable(Selected,Host); AssertEquals(Ord(pprObservedChange),Ord(D.Reason));
end;
procedure TPrismPreviewTests.SafeReaderRefusalClearsOutput;
var Raw:RawByteString; Stamp:TPrismNodeStamp; E:TPrismReadError;
begin
  AssertTrue(ReadPrismFile(Selected.ConfigPath,PrismDocumentMaxBytes,Raw,Stamp,E));
  HookMode:=4; PrismReadAfterReadHook:=@PreviewReadHook;
  AssertFalse(ReadPrismFile(Selected.ConfigPath,PrismDocumentMaxBytes,Raw,Stamp,E));
  AssertEquals(Ord(preChanged),Ord(E)); AssertEquals('',Raw); AssertEquals('',Stamp.Path);
  AssertEquals(0,Length(Stamp.Ancestors));
end;
procedure TPrismPreviewTests.SameJavaABAndInputPreservation;
var A,B:TPrismPreviewDTO;
begin
  AddInstance('B',StringOfChar('b',32)); A:=Preview;
  Selected.Folder:='B'; Selected.ConfigPath:=Root+'/instances/B/instance.cfg'; Selected.UUID:=StringOfChar('b',32);
  Selected.StableKey:='prism-'+SHA1Print(SHA1String(Root+#0+'uuid:'+Selected.UUID)); B:=Preview;
  AssertEquals(Ord(ppsReady),Ord(A.Status)); AssertEquals(Ord(ppsReady),Ord(B.Status));
  AssertTrue(A.GeneratedSelector<>B.GeneratedSelector); AssertTrue(Pos(Secret,DTOText(A)+DTOText(B))=0);
end;
initialization RegisterTest(TPrismPreviewTests);
end.
