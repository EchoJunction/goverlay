unit prism_test_cases;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, fpcunit, testregistry, prismprovider, prismroots;

type
  TPrismTests = class(TTestCase)
  private
    Base, Root: string;
    BaseDevice, BaseInode: QWord;
    Input: TPrismDiscoveryInput;
    procedure Put(const Path, Content: string);
    procedure Instance(const Folder, Name, UUID: string);
    function Scan: TPrismDiscoveryResult;
    function HasIssue(const R: TPrismDiscoveryResult; Kind: TPrismIssueKind): Boolean;
    function Snapshot(const Dir: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure RootsPersistenceRoundTripAndDedup;
    procedure RootsCorruptStatePreserved;
    procedure RootsBoundsAndUnsafePaths;
    procedure RootSelectionValidationAndMissingReload;
    procedure NativeMetadataAndReadonly;
    procedure PinnedQtFixture;
    procedure FlatpakCustomAndDedup;
    procedure ConfiguredDirectoriesAndUnicode;
    procedure RenameAndFallbackIdentity;
    procedure DuplicateNamesAndScopedUUID;
    procedure RejectEveryDuplicateUUID;
    procedure InvalidEntriesAreIsolated;
    procedure QtEscapesAndEncodedDuplicateKeys;
    procedure SymlinksAndTraversal;
    procedure Bounds;
    procedure AbsentRoots;
    procedure CaseSensitiveRoots;
    procedure ConfiguredDirectoryFallbackIdentity;
    procedure ExclusiveFixtureRoot;
    procedure TruncatedRootDiscardsCandidates;
    procedure GlobalScanBudget;
  end;

implementation

uses BaseUnix, SHA1;

function MkDTemp(Template: PChar): PChar; cdecl; external 'c' name 'mkdtemp';

const
  U1 = '0123456789abcdef0123456789abcdef';
  U2 = '1123456789abcdef0123456789abcdef';
  Header = '[General]' + LineEnding + 'ConfigVersion=1.3' + LineEnding + 'InstanceType=OneSix' + LineEnding;

procedure TPrismTests.Put(const Path, Content: string);
var F: TFileStream;
begin
  ForceDirectories(ExtractFileDir(Path));
  F := TFileStream.Create(Path, fmCreate);
  try if Content <> '' then F.WriteBuffer(Content[1], Length(Content));
  finally F.Free; end;
end;

procedure TPrismTests.Instance(const Folder, Name, UUID: string);
var S: string;
begin
  S := Header + 'name=' + Name + LineEnding;
  if UUID <> '' then S := S + 'uuid=' + UUID + LineEnding;
  Put(Root + '/instances/' + Folder + '/instance.cfg', S);
end;

procedure TPrismTests.SetUp;
var Template: string; St: Stat;
begin
  Base := '';
  Template := GetTempDir(False) + 'goverlay-prism-XXXXXX';
  if MkDTemp(PChar(Template)) = nil then
    raise Exception.Create('Cannot exclusively create Prism test directory');
  Base := Template;
  if (fpLStat(PChar(Base), St) <> 0) or not FPS_ISDIR(St.st_mode) or
     ((St.st_mode and $1FF) <> $1C0) or (St.st_uid <> fpGetUid) then
    raise Exception.Create('Unsafe Prism test directory');
  BaseDevice := St.st_dev; BaseInode := St.st_ino;
  Input := Default(TPrismDiscoveryInput);
  Input.HomeDir := Base;
  Root := Base + '/.local/share/PrismLauncher';
  Put(Root + '/prismlauncher.cfg', Header);
end;

procedure RemoveTree(const Dir: string);
var S: TSearchRec; St: Stat;
begin
  if (fpLStat(PChar(Dir), St) <> 0) or not FPS_ISDIR(St.st_mode) then Exit;
  if FindFirst(Dir + '/*', faAnyFile, S) = 0 then
  try
    repeat
      if (S.Name = '.') or (S.Name = '..') then Continue;
      if (S.Attr and faSymLink) <> 0 then DeleteFile(Dir + '/' + S.Name)
      else if (S.Attr and faDirectory) <> 0 then RemoveTree(Dir + '/' + S.Name)
      else DeleteFile(Dir + '/' + S.Name);
    until FindNext(S) <> 0;
  finally FindClose(S); end;
  RemoveDir(Dir);
end;

procedure TPrismTests.TearDown;
var St: Stat;
begin
  if Base = '' then Exit;
  if (fpLStat(PChar(Base), St) <> 0) or not FPS_ISDIR(St.st_mode) or
     (QWord(St.st_dev) <> BaseDevice) or (QWord(St.st_ino) <> BaseInode) or
     (St.st_uid <> fpGetUid) then
    raise Exception.Create('Fixture root replaced; refusing recursive cleanup');
  RemoveTree(Base);
end;

function TPrismTests.Scan: TPrismDiscoveryResult;
begin
  Result := DiscoverPrism(Input);
end;

function TPrismTests.HasIssue(const R: TPrismDiscoveryResult; Kind: TPrismIssueKind): Boolean;
var I: Integer;
begin
  Result := False;
  for I := 0 to High(R.Issues) do if R.Issues[I].Kind = Kind then Exit(True);
end;

function TPrismTests.Snapshot(const Dir: string): string;
var S: TSearchRec; Names: TStringList; P: string; I: Integer;
begin
  Names := TStringList.Create;
  try
    if FindFirst(Dir + '/*', faAnyFile, S) = 0 then
    try
      repeat
        if (S.Name = '.') or (S.Name = '..') then Continue;
        P := Dir + '/' + S.Name;
        if (S.Attr and faDirectory) <> 0 then Names.Add('D:' + P + Snapshot(P))
        else Names.Add('F:' + P + ':' + SHA1Print(SHA1File(P)));
      until FindNext(S) <> 0;
    finally FindClose(S); end;
    Names.Sort; Result := '';
    for I := 0 to Names.Count - 1 do Result := Result + Names[I] + #10;
  finally Names.Free; end;
end;

procedure TPrismTests.NativeMetadataAndReadonly;
var R: TPrismDiscoveryResult; Before: string;
begin
  Instance('A', 'Vanilla', U1);
  Put(Root + '/instances/A/mmc-pack.json', '{"components":[{"uid":"net.minecraft","version":"1.21.1"},{"uid":"net.fabricmc.fabric-loader","version":"0.16.9"}]}');
  Before := Snapshot(Base); R := Scan;
  AssertEquals(Before, Snapshot(Base));
  AssertEquals(1, Length(R.Instances)); AssertEquals(0, Length(R.Issues));
  AssertEquals('Vanilla', R.Instances[0].DisplayName);
  AssertEquals('1.21.1', R.Instances[0].MinecraftVersion);
  AssertEquals('net.fabricmc.fabric-loader 0.16.9', R.Instances[0].Loader);
  AssertEquals('prism-' + SHA1Print(SHA1String(Root + #0 + 'uuid:' + U1)), R.Instances[0].StableKey);
end;

procedure TPrismTests.PinnedQtFixture;
var R: TPrismDiscoveryResult; Fixture: TStringList;
begin
  Fixture := TStringList.Create;
  try
    Fixture.LoadFromFile('tests/prism/fixtures/modern-instance.cfg');
    Put(Root + '/instances/qt/instance.cfg', Fixture.Text);
  finally Fixture.Free; end;
  R := Scan; AssertEquals(1, Length(R.Instances));
  AssertEquals('Synthetic 日本語 =,#; "test"', R.Instances[0].DisplayName);
  AssertEquals(U1, R.Instances[0].UUID);
end;

procedure TPrismTests.FlatpakCustomAndDedup;
var R: TPrismDiscoveryResult;
begin
  Instance('native', 'Same', U1);
  Root := Base + '/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher';
  Put(Root + '/prismlauncher.cfg', Header); Instance('flat', 'Same', U1);
  Root := Base + '/"custom data'; Put(Root + '/prismlauncher.cfg', Header);
  Instance('"quoted folder', 'Same', U1);
  SetLength(Input.AdditionalRoots, 2);
  Input.AdditionalRoots[0] := Root; Input.AdditionalRoots[1] := Root + '/.';
  R := Scan;
  AssertEquals(3, Length(R.Installations)); AssertEquals(3, Length(R.Instances));
  AssertTrue(R.Installations[1].Kind = pikFlatpak);
  AssertEquals(Root + '/instances/"quoted folder/instance.cfg', R.Instances[2].ConfigPath);
end;

procedure TPrismTests.ConfiguredDirectoriesAndUnicode;
var R: TPrismDiscoveryResult;
begin
  Put(Root + '/prismlauncher.cfg', Header + 'InstanceDir="日本語, instances"');
  Put(Root + '/日本語, instances/A/instance.cfg', Header + 'name="日本語, =; # \"quoted\""' + LineEnding + 'uuid=' + U1);
  R := Scan; AssertEquals(1, Length(R.Instances));
  AssertEquals('日本語, =; # "quoted"', R.Instances[0].DisplayName);
  Put(Root + '/prismlauncher.cfg', Header + 'InstanceDir="' + Base + '/absolute instances"');
  Put(Base + '/absolute instances/B/instance.cfg', Header + 'uuid=' + U2);
  R := Scan; AssertEquals(1, Length(R.Instances)); AssertEquals('B', R.Instances[0].Folder);
  Input.XdgDataHome := Base + '/xdg'; Root := Input.XdgDataHome + '/PrismLauncher';
  Put(Root + '/prismlauncher.cfg', Header); Instance('C', 'XDG', U1);
  R := Scan; AssertEquals('XDG', R.Instances[0].DisplayName);
end;

procedure TPrismTests.RenameAndFallbackIdentity;
var A, B: TPrismDiscoveryResult; Key: string;
begin
  Instance('A', 'Old', UpperCase(U1)); A := Scan; Key := A.Instances[0].StableKey;
  Instance('A', 'New', U1); RenameFile(Root + '/instances/A', Root + '/instances/B');
  B := Scan; AssertEquals(Key, B.Instances[0].StableKey);
  Instance('fallback', 'Fallback', ''); A := Scan;
  Key := ''; if A.Instances[0].UsesFolderIdentity then Key := A.Instances[0].StableKey
  else Key := A.Instances[1].StableKey;
  RenameFile(Root + '/instances/fallback', Root + '/instances/moved'); B := Scan;
  if B.Instances[0].UsesFolderIdentity then AssertTrue(Key <> B.Instances[0].StableKey)
  else AssertTrue(Key <> B.Instances[1].StableKey);
end;

procedure TPrismTests.DuplicateNamesAndScopedUUID;
var R: TPrismDiscoveryResult;
begin
  Instance('A', 'Same', U1); Instance('B', 'Same', U2);
  R := Scan; AssertEquals(2, Length(R.Instances));
  AssertTrue(R.Instances[0].StableKey <> R.Instances[1].StableKey);
  Root := Base + '/custom'; Put(Root + '/prismlauncher.cfg', Header); Instance('A', 'Same', U1);
  SetLength(Input.AdditionalRoots, 1); Input.AdditionalRoots[0] := Root;
  R := Scan; AssertEquals(3, Length(R.Instances)); AssertFalse(HasIssue(R, piDuplicateUUID));
  AssertTrue(R.Instances[0].StableKey <> R.Instances[2].StableKey);
end;

procedure TPrismTests.RejectEveryDuplicateUUID;
var R: TPrismDiscoveryResult;
begin
  Instance('A', 'One', U1); Instance('B', 'Two', UpperCase(U1)); Instance('C', 'Three', U2);
  R := Scan; AssertEquals(1, Length(R.Instances)); AssertEquals(U2, R.Instances[0].UUID);
  AssertEquals(2, Length(R.Issues)); AssertTrue(HasIssue(R, piDuplicateUUID));
end;

procedure TPrismTests.InvalidEntriesAreIsolated;
var R: TPrismDiscoveryResult;
begin
  Instance('good', 'Good', U1); Put(Root + '/instances/good/mmc-pack.json', '{broken');
  Put(Root + '/instances/bad/instance.cfg', Header + 'uuid=broken');
  Put(Root + '/instances/not-minecraft/instance.cfg', '[General]' + LineEnding + 'ConfigVersion=1.3' + LineEnding + 'InstanceType=Unrelated');
  Put(Root + '/instances/old/instance.cfg', '[General]' + LineEnding + 'ConfigVersion=1.2');
  Put(Root + '/instances/no-general/instance.cfg', 'ConfigVersion=1.3');
  Put(Root + '/instances/malformed/instance.cfg', Header + 'broken');
  R := Scan; AssertEquals(1, Length(R.Instances)); AssertEquals('', R.Instances[0].MinecraftVersion);
  AssertTrue(HasIssue(R, piInvalidMetadata)); AssertTrue(HasIssue(R, piInvalidUUID));
  AssertTrue(HasIssue(R, piUnsupportedInstanceType));
  AssertTrue(HasIssue(R, piUnsupportedVersion)); AssertTrue(HasIssue(R, piMalformedConfig));
end;

procedure TPrismTests.QtEscapesAndEncodedDuplicateKeys;
var R: TPrismDiscoveryResult;
begin
  Put(Root + '/instances/A/instance.cfg', Header + 'na%6De="A\x20\"B\"\\C\n\t"' + LineEnding + 'uuid=' + U1);
  R := Scan; AssertEquals(1, Length(R.Instances));
  AssertEquals('A "B"\C' + #10 + #9, R.Instances[0].DisplayName);
  Put(Root + '/instances/A/instance.cfg', Header + 'name=One' + LineEnding + 'na%6De=Two');
  R := Scan; AssertEquals(0, Length(R.Instances)); AssertTrue(HasIssue(R, piMalformedConfig));
  Put(Root + '/instances/A/instance.cfg', Header + 'uuid=' + LineEnding + 'uuid=' + U1);
  R := Scan; AssertEquals(0, Length(R.Instances)); AssertTrue(HasIssue(R, piMalformedConfig));
  Put(Root + '/instances/A/instance.cfg', Header + 'name="unclosed');
  R := Scan; AssertEquals(0, Length(R.Instances));
  Put(Root + '/instances/A/instance.cfg', Header + 'name=\xD83D\xDE00');
  R := Scan; AssertEquals(1, Length(R.Instances)); AssertEquals('😀', R.Instances[0].DisplayName);
end;

procedure TPrismTests.SymlinksAndTraversal;
var R: TPrismDiscoveryResult;
begin
  Instance('A', 'Good', U1);
  fpSymlink(PChar(Root + '/instances/A'), PChar(Root + '/instances/link'));
  R := Scan; AssertEquals(1, Length(R.Instances)); AssertTrue(HasIssue(R, piUnsafePath));
  DeleteFile(Root + '/instances/A/instance.cfg'); Put(Base + '/outside.cfg', Header);
  fpSymlink(PChar(Base + '/outside.cfg'), PChar(Root + '/instances/A/instance.cfg'));
  R := Scan; AssertEquals(0, Length(R.Instances));
  Put(Root + '/prismlauncher.cfg', Header + 'InstanceDir=../escape');
  R := Scan; AssertEquals(0, Length(R.Installations)); AssertTrue(HasIssue(R, piUnsafePath));
  SetLength(Input.AdditionalRoots, 1); Input.AdditionalRoots[0] := Base + '/alias';
  fpSymlink(PChar(Root), PChar(Input.AdditionalRoots[0]));
  R := Scan; AssertTrue(HasIssue(R, piUnsafePath));
end;

procedure TPrismTests.Bounds;
var R: TPrismDiscoveryResult;
begin
  Put(Root + '/instances/large/instance.cfg', StringOfChar('x', PrismMaxFileBytes + 1));
  Put(Root + '/instances/long/instance.cfg', Header + 'name=' + StringOfChar('n', PrismMaxTextBytes + 1));
  Instance('good', 'Good', U1);
  Put(Root + '/instances/good/mmc-pack.json', StringOfChar('[', 1000) + StringOfChar(']', 1000));
  R := Scan; AssertEquals(1, Length(R.Instances)); AssertTrue(HasIssue(R, piLimitExceeded));
  AssertTrue(HasIssue(R, piMalformedConfig)); AssertTrue(HasIssue(R, piInvalidMetadata));
  SetLength(Input.AdditionalRoots, PrismMaxRoots + 1);
  R := Scan; AssertTrue(HasIssue(R, piLimitExceeded));
end;

procedure TPrismTests.AbsentRoots;
var R: TPrismDiscoveryResult;
begin
  Input.HomeDir := Base + '/absent'; R := Scan;
  AssertEquals(0, Length(R.Instances)); AssertEquals(0, Length(R.Issues));
  AssertFalse(DirectoryExists(Input.HomeDir));
end;

procedure TPrismTests.CaseSensitiveRoots;
var R: TPrismDiscoveryResult; LowerRoot: string;
begin
  Input.HomeDir := '';
  Root := Base + '/case'; LowerRoot := Root;
  Put(Root + '/prismlauncher.cfg', Header); Instance('A', 'lower', U1);
  Root := Base + '/CASE';
  Put(Root + '/prismlauncher.cfg', Header); Instance('A', 'upper', U1);
  SetLength(Input.AdditionalRoots, 2);
  Input.AdditionalRoots[0] := LowerRoot; Input.AdditionalRoots[1] := Root;
  R := Scan; AssertEquals(2, Length(R.Installations)); AssertEquals(2, Length(R.Instances));
  AssertTrue(R.Instances[0].StableKey <> R.Instances[1].StableKey);
end;

procedure TPrismTests.ConfiguredDirectoryFallbackIdentity;
var A, B: TPrismDiscoveryResult;
begin
  Put(Root + '/one/A/instance.cfg', Header + 'name=Same');
  Put(Root + '/two/A/instance.cfg', Header + 'name=Same');
  Put(Root + '/prismlauncher.cfg', Header + 'InstanceDir=one'); A := Scan;
  Put(Root + '/prismlauncher.cfg', Header + 'InstanceDir=two'); B := Scan;
  AssertEquals(1, Length(A.Instances)); AssertEquals(1, Length(B.Instances));
  AssertTrue(A.Instances[0].UsesFolderIdentity);
  AssertTrue(A.Instances[0].StableKey <> B.Instances[0].StableKey);
  Put(Root + '/prismlauncher.cfg', Header + 'InstanceDir=./two/.'); A := Scan;
  AssertEquals(B.Instances[0].StableKey, A.Instances[0].StableKey);
end;

procedure TPrismTests.ExclusiveFixtureRoot;
var St: Stat; Moved: string;
begin
  AssertEquals(0, fpLStat(PChar(Base), St));
  AssertTrue(FPS_ISDIR(St.st_mode)); AssertEquals($1C0, St.st_mode and $1FF);
  AssertEquals(QWord(fpGetUid), QWord(St.st_uid));
  Put(Base + '/sentinel', 'preserve');
  Moved := Base + '-moved'; AssertTrue(RenameFile(Base, Moved));
  try
    AssertEquals(0, fpSymlink(PChar(Moved), PChar(Base)));
    RemoveTree(Base);
    AssertTrue(FileExists(Moved + '/sentinel'));
    AssertEquals(0, fpLStat(PChar(Base), St)); AssertTrue(FPS_ISLNK(St.st_mode));
  finally
    DeleteFile(Base); RenameFile(Moved, Base);
  end;
end;

procedure TPrismTests.TruncatedRootDiscardsCandidates;
var R: TPrismDiscoveryResult; I: Integer;
begin
  Instance('unique', 'Unique', U2);
  for I := 1 to PrismMaxEntries do Instance('clone' + IntToStr(I), 'Clone', U1);
  R := Scan;
  AssertEquals(0, Length(R.Instances));
  AssertTrue(HasIssue(R, piLimitExceeded));
end;

procedure TPrismTests.GlobalScanBudget;
var R: TPrismDiscoveryResult; I: Integer; FirstRoot: string;
begin
  Input.HomeDir := ''; FirstRoot := Root;
  Instance('good', 'Good', U2);
  for I := 2 to PrismMaxEntries do Put(Root + '/instances/file' + IntToStr(I), '');
  Root := Base + '/second'; Put(Root + '/prismlauncher.cfg', Header); Instance('A', 'Next', U1);
  SetLength(Input.AdditionalRoots, 2);
  Input.AdditionalRoots[0] := FirstRoot; Input.AdditionalRoots[1] := Root;
  R := Scan;
  AssertEquals(1, Length(R.Instances)); AssertEquals(U2, R.Instances[0].UUID);
  AssertTrue(HasIssue(R, piLimitExceeded));
end;

procedure TPrismTests.RootsPersistenceRoundTripAndDedup;
var Roots, Loaded: TPrismRootPaths; FileName, Error, Before: string;
begin
  FileName := Base + '/goverlay/prism_roots.json';
  SetLength(Roots, 4);
  Roots[0] := Base + '/portable 日本語 "quoted"' + #10 + 'root';
  Roots[1] := Roots[0] + '/./';
  Roots[2] := Base + '/Case'; Roots[3] := Base + '/case';
  Before := Snapshot(Root);
  AssertTrue(SavePrismRoots(FileName, Roots, Error));
  AssertTrue(LoadPrismRoots(FileName, Loaded, Error));
  AssertEquals(3, Length(Loaded)); AssertEquals(Roots[0], Loaded[0]);
  AssertEquals(Roots[2], Loaded[1]); AssertEquals(Roots[3], Loaded[2]);
  AssertEquals(Before, Snapshot(Root));
end;

procedure TPrismTests.RootsCorruptStatePreserved;
var Roots: TPrismRootPaths; FileName, Error, Before: string; I: Integer;
const Bad: array[0..9] of string = ('{', '{"version":2,"roots":[]}',
  '{"version":1,"roots":[7]}', '{"version":1,"roots":["relative"]}',
  '{"version":1,"roots":[],"extra":true}', '{"version":1,"version":1,"roots":[]}',
  '{"version":1,"roots":["/tmp/../escape"]}',
  '{"version":1,"roots":[]}garbage',
  '{"version":1,"roots":[]} {"extra":2}',
  '{"version":1,"roots":[]}' + #0 + 'garbage');
begin
  FileName := Base + '/goverlay/prism_roots.json';
  for I := 0 to High(Bad) do
  begin
    Put(FileName, Bad[I]); Before := Snapshot(Base + '/goverlay');
    AssertFalse(LoadPrismRoots(FileName, Roots, Error)); AssertTrue(Error <> '');
    AssertEquals(0, Length(Roots));
    AssertFalse(SavePrismRoots(FileName, Roots, Error));
    AssertEquals(Before, Snapshot(Base + '/goverlay'));
  end;
  Put(FileName, ' ' + #9 + '{"version":1,"roots":[]}' + #13 + #10 + ' ');
  AssertTrue('JSON whitespace is allowed', LoadPrismRoots(FileName, Roots, Error));
end;

procedure TPrismTests.RootsBoundsAndUnsafePaths;
var Roots, Loaded: TPrismRootPaths; FileName, Error, Before, C: string; I, Issues: Integer;
begin
  FileName := Base + '/goverlay/prism_roots.json';
  SetLength(Roots, PrismMaxAdditionalRoots);
  for I := 0 to High(Roots) do Roots[I] := Base + '/portable-' + IntToStr(I);
  AssertTrue(SavePrismRoots(FileName, Roots, Error));
  Before := Snapshot(Base + '/goverlay');
  SetLength(Roots, PrismMaxAdditionalRoots + 1); Roots[High(Roots)] := Base + '/extra';
  AssertFalse(SavePrismRoots(FileName, Roots, Error));
  AssertEquals(Before, Snapshot(Base + '/goverlay'));
  SetLength(Roots, 1); Roots[0] := '/' + StringOfChar('x', PrismMaxTextBytes);
  AssertFalse(SavePrismRoots(FileName, Roots, Error));
  AssertEquals(Before, Snapshot(Base + '/goverlay'));
  AssertEquals(0, fpSymlink(PChar(Root), PChar(Base + '/alias')));
  Roots[0] := Base + '/alias';
  AssertFalse(ValidatePrismRoot(Roots[0], C, Error, Issues));
  AssertTrue('unavailable saved selection remains removable', SavePrismRoots(FileName, Roots, Error));
  AssertTrue(LoadPrismRoots(FileName, Loaded, Error));
  AssertEquals(Roots[0], Loaded[0]);
  DeleteFile(FileName);
  AssertEquals(0, fpSymlink(PChar(Root + '/prismlauncher.cfg'), PChar(FileName)));
  AssertFalse(LoadPrismRoots(FileName, Loaded, Error));
  DeleteFile(FileName); Put(FileName, StringOfChar('[', 10000));
  AssertFalse(LoadPrismRoots(FileName, Loaded, Error));
  Put(FileName, StringOfChar(' ', PrismRootsMaxBytes + 1));
  AssertFalse(LoadPrismRoots(FileName, Loaded, Error));
end;

procedure TPrismTests.RootSelectionValidationAndMissingReload;
var C, Error, Before, FileName: string; Issues: Integer; Roots, Loaded: TPrismRootPaths;
begin
  Before := Snapshot(Root);
  AssertTrue('valid empty root', ValidatePrismRoot(Root, C, Error, Issues));
  AssertEquals(Root, C); AssertEquals(0, Issues);
  AssertEquals(Before, Snapshot(Root));
  Instance('broken', 'broken', 'bad uuid');
  AssertTrue('bad individual instance does not reject root', ValidatePrismRoot(Root, C, Error, Issues));
  AssertTrue(Issues > 0);
  Put(Root + '/prismlauncher.cfg', '[General]' + LineEnding + 'ConfigVersion=9');
  AssertFalse('unsupported launcher version', ValidatePrismRoot(Root, C, Error, Issues));
  AssertFalse('missing root', ValidatePrismRoot(Base + '/gone', C, Error, Issues));
  Put(Root + '/prismlauncher.cfg', Header);
  AssertEquals(0, fpChmod(PChar(Root + '/prismlauncher.cfg'), 0));
  AssertFalse('unreadable launcher settings', ValidatePrismRoot(Root, C, Error, Issues));
  fpChmod(PChar(Root + '/prismlauncher.cfg'), &600);
  FileName := Base + '/goverlay/prism_roots.json'; SetLength(Roots, 1);
  Roots[0] := Base + '/currently-missing';
  AssertTrue(SavePrismRoots(FileName, Roots, Error));
  AssertTrue(LoadPrismRoots(FileName, Loaded, Error));
  AssertEquals(Roots[0], Loaded[0]);
end;

initialization
  RegisterTest(TPrismTests);
end.
