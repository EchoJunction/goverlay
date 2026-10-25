unit prism_gui_test_cases;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, prismprovider;
type
  TPrismGuiTests = class(TTestCase)
  private
    Base: string;
    A, B: TPrismInstance;
    LegacyPath, GlobalPath, GlobalBefore, NativePath, NativeBefore, GlobalWrapperPath, GlobalWrapperBefore, FlatpakPath, FlatpakBefore, BlacklistPath, BlacklistBefore: string;
    procedure Put(const P, S: string);
    function ReadText(const P: string): string;
    function Snapshot(const P: string): string;
    procedure AssertSentinels;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPrismGamesSubmenuCatalog;
    procedure TestPrismGamesSubmenuDirtyGuard;
    procedure TestPrismTweaksCategoriesAndRefresh;
    procedure TestPrismTweaksDirtyRoundTrip;
    procedure TestReadOnlyPreviewAndContext;
    procedure TestDistinctLocalProfilesAndReadonlySelection;
    procedure TestPendingEditAndFailurePreserveContext;
    procedure TestDeniedHandlersAndHelpers;
    procedure TestTypedCatalogAndLegacyReturn;
    procedure TestImportedLogPathAndHelperFailure;
    procedure TestPendingLegacySelectionAndInvalidKey;
    procedure TestFailedGlobalAutosaveBlocksPrismSelection;
    procedure TestVisiblePersistentContextAndKeyboardCards;
    procedure TestCustomRootCatalogPersistenceAndRemoval;
    procedure TestRootChangesBlockOnDirtySaveFailure;
    procedure TestEmptyLibraryLocatorAndCorruptRoots;
    procedure TestCloneNormalizesAndIsolatesProfiles;
    procedure TestCloneFallbackAndExplicitOverwrite;
    procedure TestCloneFailuresPreserveProfileAndControls;
    procedure TestCloneDirtyFailureAndTypedGuards;
    procedure TestCloneSourceAliasRejectedBeforeDirtySave;
  end;
implementation
uses overlayunit, gamecontext, configmanager, test_isolation, SHA1, ExtCtrls, StdCtrls, prismroots, BaseUnix, ComCtrls,
  Forms, prismpreview, prismsnapshot, mangohud_ui, games_tab, lossless_scaling_tab, reshade_tab, optiscaler_tab,
  tweaks_md3, Graphics, FileUtil, overlay_utils, Controls, LCLType, goverlay_strings;

procedure TPrismGuiTests.Put(const P, S: string);
var L: TStringList;
begin
  ForceDirectories(ExtractFileDir(P)); L := TStringList.Create;
  try L.Text := S; L.SaveToFile(P); finally L.Free; end;
end;
function TPrismGuiTests.ReadText(const P: string): string;
var L: TStringList;
begin
  Result := ''; if not FileExists(P) then Exit;
  L := TStringList.Create;
  try L.LoadFromFile(P); Result := L.Text; finally L.Free; end;
end;
function TPrismGuiTests.Snapshot(const P: string): string;
var S: TSearchRec; L: TStringList; Path: string;
begin
  Result := ''; if not DirectoryExists(P) then Exit;
  L := TStringList.Create;
  try
    if FindFirst(P + '/*', faAnyFile, S) = 0 then
    try repeat
      if (S.Name = '.') or (S.Name = '..') then Continue;
      Path := P + '/' + S.Name;
      if (S.Attr and faDirectory) <> 0 then L.Add('D:' + Path + Snapshot(Path))
      else L.Add('F:' + Path + SHA1Print(SHA1File(Path)));
    until FindNext(S) <> 0;
    finally FindClose(S); end;
    L.Sort; Result := L.Text;
  finally L.Free; end;
end;
procedure TPrismGuiTests.SetUp;
begin
  AssertTrue(IsSafeSandboxDir(IsolatedHome));
  goverlayform.gamesLabelClick(nil);
  Base := IsolatedHome + '/prism-gui-' + TestName;
  A := Default(TPrismInstance); A.DataRoot := Base + '/prism';
  A.DisplayName := 'Prism same label'; A.Folder := 'A';
  A.UUID := '0123456789abcdef0123456789abcdef';
  A.StableKey := 'prism-' + SHA1Print(SHA1String(A.DataRoot + #0 + 'uuid:' + A.UUID));
  A.ConfigPath := A.DataRoot + '/instances/A/instance.cfg';
  B := A; B.UUID := '1123456789abcdef0123456789abcdef'; B.Folder := 'B';
  B.StableKey := 'prism-' + SHA1Print(SHA1String(B.DataRoot + #0 + 'uuid:' + B.UUID));
  B.ConfigPath := B.DataRoot + '/instances/B/instance.cfg';
  Put(A.ConfigPath, '[General]' + LineEnding + 'ConfigVersion=1.3' + LineEnding + 'InstanceType=OneSix' + LineEnding + 'name=' + A.DisplayName + LineEnding + 'uuid=' + A.UUID + LineEnding + 'JavaPath=/same/java');
  Put(B.ConfigPath, '[General]' + LineEnding + 'ConfigVersion=1.3' + LineEnding + 'InstanceType=OneSix' + LineEnding + 'name=' + B.DisplayName + LineEnding + 'uuid=' + B.UUID + LineEnding + 'JavaPath=/same/java');
  LegacyPath := goverlayform.GetGameConfigDir(A.DisplayName) + 'bgmod.conf';
  Put(LegacyPath, 'legacy wrapper sentinel');
  GlobalPath := goverlayform.GetGameConfigDir('') + 'MangoHud.conf';
  GlobalBefore := ReadText(GlobalPath);
  NativePath := IncludeTrailingPathDelimiter(GetMangoHudConfigDir) + 'MangoHud.conf';
  Put(NativePath, 'native global sentinel'); NativeBefore := ReadText(NativePath);
  GlobalWrapperPath := goverlayform.GetGameConfigDir('') + 'bgmod.conf';
  GlobalWrapperBefore := ReadText(GlobalWrapperPath);
  BlacklistPath := IncludeTrailingPathDelimiter(overlay_utils.GetUserConfigDir) + 'goverlay/blacklist.conf';
  Put(BlacklistPath, 'blacklist sentinel'); BlacklistBefore := ReadText(BlacklistPath);
  FlatpakPath := GetUserDir + '.var/app/com.valvesoftware.Steam/config/MangoHud/MangoHud.conf';
  Put(FlatpakPath, 'flatpak global sentinel'); FlatpakBefore := ReadText(FlatpakPath);
end;
procedure TPrismGuiTests.TearDown;
var Blocker: string;
begin
  if goverlayform.IsPrismContext and Assigned(goverlayform.FPrismTweaksPage) and
    (goverlayform.goverlayPageControl.ActivePage=goverlayform.FPrismTweaksPage) then
    goverlayform.mangohudLabelClick(nil);
  goverlayform.autoSaveTimer.Enabled := False;
  if goverlayform.IsPrismContext and goverlayform.FProfileDirty then
  begin
    Blocker := ExcludeTrailingPathDelimiter(goverlayform.ActiveProfileConfigDir);
    AssertTrue(Pos(IncludeTrailingPathDelimiter(IsolatedHome), Blocker) = 1);
    if FileExists(Blocker) then DeleteFile(Blocker);
    goverlayform.TrySaveMangoHudConfig;
  end;
  goverlayform.gamesLabelClick(nil);
end;
procedure TPrismGuiTests.AssertSentinels;
begin
  AssertEquals('global managed sentinel', GlobalBefore, ReadText(GlobalPath));
  AssertEquals('native global sentinel', NativeBefore, ReadText(NativePath));
  AssertEquals('global wrapper sentinel', GlobalWrapperBefore, ReadText(GlobalWrapperPath));
  AssertEquals('blacklist sentinel', BlacklistBefore, ReadText(BlacklistPath));
  AssertEquals('Steam Flatpak sentinel', FlatpakBefore, ReadText(FlatpakPath));
  AssertEquals('legacy wrapper sentinel' + LineEnding,
    ReadText(LegacyPath));
end;
procedure TPrismGuiTests.TestDistinctLocalProfilesAndReadonlySelection;
var Before, ADir, BDir, TextA: string;
begin
  Before := Snapshot(Base); AssertTrue(goverlayform.SelectPrismInstance(A));
  ADir := goverlayform.ActiveProfileConfigDir;
  AssertFalse(DirectoryExists(ADir));
  AssertFalse(goverlayform.frametimedetailedCheckBox.Enabled);
  AssertFalse(DirectoryExists(goverlayform.ActiveProfileLogDir));
  AssertEquals(Before, Snapshot(Base));
  goverlayform.FLoadingConfig := True;
  goverlayform.hudtitleEdit.Text := 'Alpha'; goverlayform.fpsCheckBox.Checked := True;
  goverlayform.FLoadingConfig := False;
  goverlayform.saveBitBtnClick(nil); TextA := ReadText(ADir + 'MangoHud.conf');
  AssertTrue(Pos('Alpha', TextA) > 0);
  AssertTrue(goverlayform.SelectPrismInstance(B)); BDir := goverlayform.ActiveProfileConfigDir;
  AssertTrue(ADir <> BDir); AssertEquals('', goverlayform.hudtitleEdit.Text);
  goverlayform.fpsonlyBitBtnClick(nil);
  AssertTrue(Pos('fps_only', ReadText(BDir + 'MangoHud.conf')) > 0);
  AssertEquals(TextA, ReadText(ADir + 'MangoHud.conf'));
  A.DisplayName := 'Renamed 日本語'; AssertTrue(goverlayform.SelectPrismInstance(A));
  AssertEquals(ADir, goverlayform.ActiveProfileConfigDir); AssertEquals('Alpha', goverlayform.hudtitleEdit.Text);
  AssertEquals(goverlayform.ActiveProfileLogDir, goverlayform.logfolderEdit.Text);
  AssertEquals(ADir + 'custom.conf', goverlayform.GetTargetCustomConfigFile);
  AssertFalse(FileExists(ADir + 'bgmod.conf')); AssertFalse(FileExists(ADir + 'bgmod'));
  AssertEquals(Before, Snapshot(Base)); AssertSentinels;
end;
procedure TPrismGuiTests.TestPendingEditAndFailurePreserveContext;
var ADir: string; Context: TActiveProfileContext;
begin
  AssertTrue(goverlayform.SelectPrismInstance(A)); ADir := goverlayform.ActiveProfileConfigDir;
  goverlayform.FLoadingConfig := True; goverlayform.hudtitleEdit.Text := 'Pending Alpha';
  goverlayform.FLoadingConfig := False; goverlayform.StartAutoSaveTimer;
  AssertTrue(goverlayform.SelectPrismInstance(B));
  AssertTrue(Pos('Pending Alpha', ReadText(ADir + 'MangoHud.conf')) > 0);
  AssertFalse(goverlayform.autoSaveTimer.Enabled); AssertEquals('', goverlayform.hudtitleEdit.Text);
  goverlayform.FLoadingConfig := True; goverlayform.hudtitleEdit.Text := 'Pending Beta';
  goverlayform.FLoadingConfig := False; goverlayform.StartAutoSaveTimer;
  goverlayform.gamesLabelClick(nil);
  AssertFalse(goverlayform.IsPrismContext);
  AssertTrue(PrismProfileContext(B, TConfigManager.GetHostDataDir, Context));
  AssertTrue(Pos('Pending Beta', ReadText(Context.ConfigDir + 'MangoHud.conf')) > 0);
  B.StableKey := 'prism-' + StringOfChar('e', 40);
  AssertTrue(PrismProfileContext(B, TConfigManager.GetHostDataDir, Context));
  Put(ExcludeTrailingPathDelimiter(Context.ConfigDir), 'file prevents profile directory');
  AssertTrue(goverlayform.SelectPrismInstance(B));
  AssertFalse(goverlayform.TrySaveMangoHudConfig);
  AssertTrue(Pos('could not be saved', goverlayform.statusBar.SimpleText) > 0);
  AssertTrue(goverlayform.FPrismContextMessage.Visible);
  AssertTrue(Pos('could not be saved', goverlayform.FPrismContextMessage.Caption) > 0);
  AssertEquals(rsPrismLocalOnly, goverlayform.FPrismContextWarning.Caption);
  AssertTrue(Pos('saved locally', goverlayform.statusBar.SimpleText) = 0);
  goverlayform.StartAutoSaveTimer;
  goverlayform.autoSaveTimerTimer(nil);
  AssertFalse(goverlayform.autoSaveTimer.Enabled);
  AssertTrue(goverlayform.FProfileDirty);
  AssertFalse(goverlayform.SelectPrismInstance(A));
  AssertEquals(B.StableKey, goverlayform.FActiveProfile.StableKey);
  AssertTrue(goverlayform.autoSaveTimer.Enabled);
  goverlayform.autoSaveTimer.Enabled := False; AssertSentinels;
end;
procedure TPrismGuiTests.TestDeniedHandlersAndHelpers;
var Before, LegacyBefore, Dir: string;
begin
  Before := Snapshot(Base); AssertTrue(goverlayform.SelectPrismInstance(A));
  Dir := goverlayform.ActiveProfileConfigDir;
  LegacyBefore := Snapshot(goverlayform.GetGameConfigDir(A.DisplayName));
  goverlayform.tweaksLabelClick(nil); goverlayform.vkbasaltLabelClick(nil);
  goverlayform.optiscalerLabelClick(nil); goverlayform.NavToolToggleClick(nil);
  goverlayform.PreviewBtnClick(nil); goverlayform.StartCube;
  goverlayform.CloneGlobalDockMenuItemClick(nil); goverlayform.usercustomBitBtnClick(nil);
  goverlayform.savecustomMenuItemClick(nil); goverlayform.saveasMenuItemClick(nil);
  goverlayform.loadconfigMenuItemClick(nil); goverlayform.openLogFileMenuItemClick(nil);
  goverlayform.logfolderBitBtnClick(nil); goverlayform.globalenableMenuItemClick(nil);
  goverlayform.SaveOptiScalerConfig; goverlayform.SaveTweaksConfig;
  goverlayform.SaveVkBasaltConfig; goverlayform.SaveVkSumiConfig;
  TLosslessScalingTabHelper(goverlayform.FLosslessScalingHelper).SaveLosslessConfig;
  TReshadeTabHelper(goverlayform.FReshadeHelper).SaveConfig;
  TTweaksMD3Helper(goverlayform.FTweaksHelper).SaveTweaksConfig;
  TOptiScalerTabHelper(goverlayform.FOptiScalerHelper).SaveOptiScalerConfig;
  AssertEquals('', TLosslessScalingTabHelper(goverlayform.FLosslessScalingHelper).WriteMakoTomlConfig(Dir));
  AssertEquals('', goverlayform.GetLaunchCommand);
  AssertFalse(goverlayform.FFADock.PreviewVisible);
  goverlayform.NavToggleClick(nil);
  goverlayform.ApplyNavCollapsed;
  AssertFalse(goverlayform.FNavToolBtns[0].Visible);
  AssertFalse(goverlayform.FNavItems[2].Visible); AssertFalse(goverlayform.FNavToolBtns[0].Visible);
  AssertFalse(DirectoryExists(Dir)); AssertEquals(Before, Snapshot(Base));
  AssertEquals(LegacyBefore, Snapshot(goverlayform.GetGameConfigDir(A.DisplayName))); AssertSentinels;
end;
procedure TPrismGuiTests.TestTypedCatalogAndLegacyReturn;
var Root: string; I, Count: Integer; Card: TPrismCardPanel;
begin
  Root := GetUserDir + '.local/share/PrismLauncher';
  Put(Root + '/prismlauncher.cfg', '[General]' + LineEnding + 'ConfigVersion=1.3' + LineEnding + 'InstanceDir=' + A.DataRoot + '/instances');
  TGamesTabHelper(goverlayform.FGamesHelper).RefreshGameCards; Count := 0; Card := nil;
  for I := 0 to goverlayform.FCardPanels.Count - 1 do
    if TObject(goverlayform.FCardPanels[I]) is TPrismCardPanel then
    begin Inc(Count); Card := TPrismCardPanel(goverlayform.FCardPanels[I]); end;
  AssertEquals(2, Count); AssertTrue(Card <> nil);
  Card.Hint := '(999) Misleading legacy name';
  goverlayform.GameCardClick(Card);
  AssertTrue(goverlayform.IsPrismContext); AssertEquals(A.DisplayName, goverlayform.FActiveGameName);
  goverlayform.gamesLabelClick(nil); AssertFalse(goverlayform.IsPrismContext);
  AssertTrue(goverlayform.FNavItems[2].Visible);
  goverlayform.mangohudLabelClick(nil);
  AssertEquals(goverlayform.GetGameConfigDir('') + 'MangoHud.conf', MANGOHUDCFGFILE);
  AssertTrue(goverlayform.FFADock.PreviewVisible);
end;
procedure TPrismGuiTests.TestImportedLogPathAndHelperFailure;
var Context: TActiveProfileContext; Before: string;
  Helper: TMangoHudUiHelper;
begin
  AssertTrue(PrismProfileContext(A, TConfigManager.GetHostDataDir, Context));
  Put(Context.ConfigDir + 'MangoHud.conf', 'fps' + LineEnding +
    'output_folder=' + Base + '/forbidden-logs' + LineEnding +
    'wine' + LineEnding + 'engine_version' + LineEnding + 'fex_stats' + LineEnding +
    'fsr' + LineEnding + 'dx_api');
  Before := Snapshot(Base);
  AssertTrue(goverlayform.SelectPrismInstance(A));
  Helper := TMangoHudUiHelper(goverlayform.FMangoHelper);
  AssertFalse(DirectoryExists(Base + '/forbidden-logs'));
  AssertFalse(DirectoryExists(Context.LogDir));
  AssertEquals(Context.LogDir, goverlayform.logfolderEdit.Text);
  AssertFalse(Helper.FwineToggle.Visible); AssertFalse(Helper.FengineversionToggle.Visible);
  AssertFalse(Helper.FfsrToggle.Visible); AssertFalse(Helper.FfexstatsToggle.Visible);
  AssertFalse(goverlayform.wineLabel.Visible);
  AssertTrue(goverlayform.TrySaveMangoHudConfig);
  AssertTrue(Pos(LineEnding + 'wine' + LineEnding, ReadText(Context.ConfigDir + 'MangoHud.conf')) = 0);
  AssertTrue(Pos('engine_version', ReadText(Context.ConfigDir + 'MangoHud.conf')) = 0);
  DeleteFile(Context.ConfigDir + 'MangoHud.conf'); RemoveDir(ExcludeTrailingPathDelimiter(Context.ConfigDir));
  Put(ExcludeTrailingPathDelimiter(Context.ConfigDir), 'block profile');
  goverlayform.autoSaveTimer.Enabled := False;
  Helper.MetricGraphClick(nil);
  AssertTrue(goverlayform.FProfileDirty);
  AssertFalse(goverlayform.autoSaveTimer.Enabled);
  AssertFalse(goverlayform.SelectPrismInstance(B));
  AssertEquals(A.StableKey, goverlayform.FActiveProfile.StableKey);
  AssertEquals(Before, Snapshot(Base)); AssertSentinels;
end;

procedure TPrismGuiTests.TestPendingLegacySelectionAndInvalidKey;
var Invalid: TPrismInstance; Dir, Before: string; Card: TPanel;
begin
  Invalid := A; Invalid.StableKey := '../escape';
  Before := Snapshot(Base);
  AssertFalse('invalid key must refuse selection', goverlayform.SelectPrismInstance(Invalid));
  AssertEquals(Before, Snapshot(Base));
  AssertTrue(goverlayform.SelectPrismInstance(A)); Dir := goverlayform.ActiveProfileConfigDir;
  AssertTrue('selected label in status', Pos(A.DisplayName, goverlayform.statusBar.SimpleText) > 0);
  AssertTrue('instance root in status', Pos(ExtractFileDir(A.ConfigPath), goverlayform.statusBar.SimpleText) > 0);
  goverlayform.FLoadingConfig := True;
  goverlayform.hudtitleEdit.Text := 'Pending legacy';
  goverlayform.FLoadingConfig := False; goverlayform.StartAutoSaveTimer;
  Card := TPanel.Create(nil);
  try
    Card.Hint := '(123) Legacy transition fixture' + LineEnding + Base + '/legacy-game';
    goverlayform.GameCardClick(Card);
    AssertFalse('legacy card must clear Prism context', goverlayform.IsPrismContext);
    AssertEquals('Legacy transition fixture', goverlayform.FActiveGameName);
    AssertTrue('pending title saved in old profile', Pos('Pending legacy', ReadText(Dir + 'MangoHud.conf')) > 0);
    AssertEquals('legacy selection must reset title', '', goverlayform.hudtitleEdit.Text);
    AssertFalse('transition must not leave autosave scheduled', goverlayform.autoSaveTimer.Enabled);
    AssertTrue('legacy navigation restored', goverlayform.FNavItems[2].Visible);
    AssertTrue('legacy preview restored', goverlayform.FFADock.PreviewVisible);
    AssertSentinels;
  finally Card.Free; end;
end;

procedure TPrismGuiTests.TestFailedGlobalAutosaveBlocksPrismSelection;
var OriginalTarget, Blocker: string;
begin
  goverlayform.gamesLabelClick(nil);
  goverlayform.mangohudLabelClick(nil);
  AssertFalse(goverlayform.IsPrismContext);
  OriginalTarget := MANGOHUDCFGFILE;
  Blocker := Base + '/blocked-global';
  Put(Blocker, 'file blocks parent directory');
  MANGOHUDCFGFILE := Blocker + '/MangoHud.conf';
  try
    goverlayform.FLoadingConfig := True;
    goverlayform.hudtitleEdit.Text := 'Unsaved global';
    goverlayform.FLoadingConfig := False;
    goverlayform.StartAutoSaveTimer;
    goverlayform.autoSaveTimerTimer(nil);
    AssertFalse('failed timer stops scheduling', goverlayform.autoSaveTimer.Enabled);
    AssertTrue('failed global edit remains dirty', goverlayform.FProfileDirty);
    AssertFalse('failed global save blocks Prism transition', goverlayform.SelectPrismInstance(A));
    AssertFalse('failed transition retains global context', goverlayform.IsPrismContext);
    AssertEquals('failed transition retains unsaved fields', 'Unsaved global', goverlayform.hudtitleEdit.Text);
    AssertFalse('no target profile created after failed transition', DirectoryExists(
      IncludeTrailingPathDelimiter(TConfigManager.GetHostDataDir) + 'goverlay/gameconfig/prism/' + A.StableKey));
    AssertSentinels;
  finally
    goverlayform.autoSaveTimer.Enabled := False;
    MANGOHUDCFGFILE := OriginalTarget;
    DeleteFile(Blocker);
  end;
  AssertTrue('global save recovers after path repair', goverlayform.TrySaveMangoHudConfig);
  AssertFalse('successful save clears global dirty state', goverlayform.FProfileDirty);
  AssertTrue('Prism transition succeeds after recovery', goverlayform.SelectPrismInstance(A));
end;

procedure TPrismGuiTests.TestPrismGamesSubmenuCatalog;
var Root,NativeCfg,OldNative,NonSteamFile,OldNonSteam,Manifest:string;
  HadNative,HadNonSteam:Boolean; I,PrismCount,MixedCount,OldWidth,OldMin,OldHeight:Integer;
  SteamCard,GogCard:TPanel; Header:TComponent; OldCollapsed:Boolean;
  procedure FindLegacy;
  var J:Integer; C:TPanel;
  begin
    SteamCard:=nil; GogCard:=nil;
    for J:=0 to goverlayform.FCardPanels.Count-1 do
    begin
      C:=TPanel(goverlayform.FCardPanels[J]);
      if C is TPrismCardPanel then Continue;
      if Pos('Synthetic Steam submenu',C.Hint)>0 then SteamCard:=C;
      if Pos('Synthetic GOG submenu',C.Hint)>0 then GogCard:=C;
    end;
  end;
begin
  Root:=GetUserDir+'.local/share/PrismLauncher'; NativeCfg:=Root+'/prismlauncher.cfg';
  HadNative:=FileExists(NativeCfg); OldNative:=ReadText(NativeCfg);
  NonSteamFile:=IncludeTrailingPathDelimiter(TConfigManager.GetGoverlayFolder)+'nonsteam_folders.txt';
  HadNonSteam:=FileExists(NonSteamFile); OldNonSteam:=ReadText(NonSteamFile);
  Manifest:=GetUserDir+'.local/share/Steam/steamapps/appmanifest_98765321.acf';
  AssertFalse(FileExists(Manifest));
  OldWidth:=goverlayform.Width; OldMin:=goverlayform.Constraints.MinWidth; OldHeight:=goverlayform.Height;
  OldCollapsed:=goverlayform.FNavCollapsed;
  try
    Put(NativeCfg,'[General]'+LineEnding+'ConfigVersion=1.3'+LineEnding+'InstanceDir='+A.DataRoot+'/instances');
    ForceDirectories(Base+'/legacy/Synthetic GOG submenu'); Put(NonSteamFile,Base+'/legacy');
    Put(Manifest,'"AppState"'+LineEnding+'{'+LineEnding+'"appid" "98765321"'+LineEnding+
      '"name" "Synthetic Steam submenu"'+LineEnding+'"installdir" "SyntheticSteamSubmenu"'+LineEnding+'}');
    TGamesTabHelper(goverlayform.FGamesHelper).RefreshGameCards;
    MixedCount:=goverlayform.FCardPanels.Count; AssertTrue(MixedCount>=4); FindLegacy;
    AssertTrue(SteamCard<>nil); AssertTrue(GogCard<>nil);
    AssertTrue(goverlayform.FPrismGamesButton.TabStop);
    AssertTrue(Assigned(goverlayform.FPrismGamesButton.OnClick));
    goverlayform.FGamesLoaded:=False;
    goverlayform.FPrismGamesButton.Click;
    AssertTrue('child first load completes',goverlayform.FGamesLoaded);
    AssertTrue(goverlayform.FGamesPrismOnly); AssertEquals(0,goverlayform.FNavActive);
    PrismCount:=0;
    for I:=0 to goverlayform.FCardPanels.Count-1 do
    begin AssertTrue(TObject(goverlayform.FCardPanels[I]) is TPrismCardPanel); Inc(PrismCount); end;
    AssertEquals(2,PrismCount);
    AssertTrue(fsBold in goverlayform.FPrismGamesButton.Font.Style);
    Header:=goverlayform.FindComponent('PrismLibraryHeader'); AssertTrue(Header<>nil);
    AssertTrue(Header.FindComponent('PrismLocateRootButton') is TButton);
    AssertTrue(Header.FindComponent('PrismManageRootsButton') is TButton);
    AssertTrue(goverlayform.FPrismGamesButton.Left>goverlayform.FNavItems[0].Left);
    AssertTrue(goverlayform.FPrismGamesButton.Top>=goverlayform.FNavItems[0].Top+goverlayform.FNavItems[0].Height);
    AssertTrue(goverlayform.FPrismGamesButton.Top+goverlayform.FPrismGamesButton.Height<=goverlayform.FNavItems[1].Top);
    goverlayform.FNavCollapsed:=True; goverlayform.ApplyNavCollapsed;
    AssertTrue(goverlayform.FPrismGamesButton.Visible);
    AssertTrue(goverlayform.FPrismGamesButton.Left+goverlayform.FPrismGamesButton.Width<=goverlayform.goverlayPaintBox.Width);
    AssertEquals(rsPrismLibraryHint,goverlayform.FPrismGamesButton.Hint);
    goverlayform.FNavCollapsed:=False; goverlayform.ApplyNavCollapsed;
    goverlayform.Constraints.MinWidth:=800; goverlayform.Width:=800;
    goverlayform.Height:=goverlayform.Constraints.MinHeight; goverlayform.OnResize(goverlayform);
    AssertTrue('nav leaves room for global/footer controls',goverlayform.FNavItems[4].Top+
      goverlayform.FNavItems[4].Height<goverlayform.goverlayPaintBox.Top+goverlayform.goverlayPaintBox.Height-80);
    AssertTrue(goverlayform.FPrismGamesButton.Left+goverlayform.FPrismGamesButton.Width<=goverlayform.goverlayPaintBox.Width);
    goverlayform.gamesLabelClick(nil);
    AssertFalse(goverlayform.FGamesPrismOnly); AssertEquals(MixedCount,goverlayform.FCardPanels.Count);
    FindLegacy; AssertTrue(SteamCard<>nil); AssertTrue(GogCard<>nil);
    goverlayform.GameCardClick(SteamCard);
    AssertFalse(goverlayform.IsPrismContext); AssertFalse(goverlayform.FActiveGameIsNonSteam);
    AssertEquals('Synthetic Steam submenu',goverlayform.FActiveGameName);
    goverlayform.gamesLabelClick(nil); FindLegacy;
    goverlayform.GameCardClick(GogCard); AssertTrue(goverlayform.FActiveGameIsNonSteam);
    goverlayform.gamesLabelClick(nil); AssertEquals('',goverlayform.FActiveGameName);
    ForceDirectories(Base+'/empty-prism');
    Put(NativeCfg,'[General]'+LineEnding+'ConfigVersion=1.3'+LineEnding+'InstanceDir='+Base+'/empty-prism');
    goverlayform.FPrismGamesButton.Click;
    AssertEquals('empty child only',0,goverlayform.FCardPanels.Count);
    Header:=goverlayform.FindComponent('PrismLibraryHeader'); AssertTrue(Header<>nil);
    AssertTrue(TButton(Header.FindComponent('PrismLocateRootButton')).Enabled);
    AssertTrue(TButton(Header.FindComponent('PrismManageRootsButton')).Enabled);
    AssertTrue(goverlayform.FindComponent('PrismEmptyLibraryLabel')<>nil);
    AssertSentinels;
  finally
    goverlayform.autoSaveTimer.Enabled:=False;
    goverlayform.gamesLabelClick(nil);
    goverlayform.Width:=OldWidth; goverlayform.Height:=OldHeight; goverlayform.Constraints.MinWidth:=OldMin;
    goverlayform.FNavCollapsed:=OldCollapsed; goverlayform.ApplyNavCollapsed;
    DeleteFile(Manifest);
    if HadNative then Put(NativeCfg,OldNative) else DeleteFile(NativeCfg);
    if HadNonSteam then Put(NonSteamFile,OldNonSteam) else DeleteFile(NonSteamFile);
  end;
end;

procedure TPrismGuiTests.TestPrismGamesSubmenuDirtyGuard;
var Before,ProfileBefore,Summary,Root,OldNative:string; HadNative:Boolean;
  OldPage:TTabSheet; Card:TPrismCardPanel; I:Integer;
begin
  Root:=GetUserDir+'.local/share/PrismLauncher/prismlauncher.cfg';
  HadNative:=FileExists(Root); OldNative:=ReadText(Root);
  try
    Put(Root,'[General]'+LineEnding+'ConfigVersion=1.3'+LineEnding+'InstanceDir='+A.DataRoot+'/instances');
    TGamesTabHelper(goverlayform.FGamesHelper).RefreshGameCards; Card:=nil;
    for I:=0 to goverlayform.FCardPanels.Count-1 do
      if TObject(goverlayform.FCardPanels[I]) is TPrismCardPanel then Card:=TPrismCardPanel(goverlayform.FCardPanels[I]);
    AssertTrue(Card<>nil); goverlayform.GameCardClick(Card); AssertTrue(goverlayform.IsPrismContext);
    goverlayform.FPrismGamesButton.Click;
    AssertTrue(goverlayform.FGamesPrismOnly); AssertFalse(goverlayform.IsPrismContext);
    AssertTrue(goverlayform.SelectPrismInstance(A));
    goverlayform.FLoadingConfig:=True; goverlayform.hudtitleEdit.Text:='Menu pending';
    goverlayform.FLoadingConfig:=False; goverlayform.StartAutoSaveTimer;
    goverlayform.tweaksLabelClick(nil); OldPage:=goverlayform.goverlayPageControl.ActivePage;
    Before:=Snapshot(Base); ProfileBefore:=Snapshot(goverlayform.ActiveProfileConfigDir);
    Summary:=goverlayform.FPrismTweaksText.Text;
    goverlayform.gamesLabelClick(nil); goverlayform.FPrismGamesButton.Click;
    AssertTrue(goverlayform.FGamesPrismOnly); AssertEquals(4,goverlayform.FNavActive);
    AssertTrue(OldPage=goverlayform.goverlayPageControl.ActivePage);
    AssertEquals(A.StableKey,goverlayform.FActiveProfile.StableKey);
    AssertEquals(Summary,goverlayform.FPrismTweaksText.Text);
    AssertTrue(goverlayform.FProfileDirty); AssertTrue(goverlayform.FPrismDeferredAutoSave);
    AssertEquals(Before,Snapshot(Base)); AssertEquals(ProfileBefore,Snapshot(goverlayform.ActiveProfileConfigDir));
    goverlayform.mangohudLabelClick(nil); AssertEquals('Menu pending',goverlayform.hudtitleEdit.Text);
    goverlayform.autoSaveTimerTimer(nil); goverlayform.gamesLabelClick(nil);
    AssertFalse(goverlayform.FGamesPrismOnly); AssertFalse(goverlayform.IsPrismContext);
    AssertEquals('',goverlayform.FActiveGameName);
    AssertTrue(goverlayform.SelectPrismInstance(A));
    goverlayform.FLoadingConfig:=True; goverlayform.hudtitleEdit.Text:='Parent menu edit';
    goverlayform.FLoadingConfig:=False; goverlayform.StartAutoSaveTimer;
    goverlayform.tweaksLabelClick(nil);
    Before:=Snapshot(Base); ProfileBefore:=Snapshot(goverlayform.ActiveProfileConfigDir);
    goverlayform.FPrismGamesButton.Click;
    AssertFalse('failed child entry preserves mixed filter',goverlayform.FGamesPrismOnly);
    AssertEquals(4,goverlayform.FNavActive); AssertTrue(goverlayform.FProfileDirty);
    AssertEquals(Before,Snapshot(Base)); AssertEquals(ProfileBefore,Snapshot(goverlayform.ActiveProfileConfigDir));
    goverlayform.mangohudLabelClick(nil); AssertEquals('Parent menu edit',goverlayform.hudtitleEdit.Text);
    goverlayform.autoSaveTimerTimer(nil); goverlayform.gamesLabelClick(nil); AssertSentinels;
  finally
    if HadNative then Put(Root,OldNative) else DeleteFile(Root);
  end;
end;

procedure TPrismGuiTests.TestPrismTweaksCategoriesAndRefresh;
var Before,Mango,Tweaks:string; OldWidth,OldMin:Integer;
begin
  A.InstallationKey:='prism-root-'+SHA1Print(SHA1String(A.DataRoot));
  Put(A.DataRoot+'/prismlauncher.cfg','[General]'+LineEnding+'ConfigVersion=1.3'+LineEnding+
    'UseDiscreteGpu=true'+LineEnding+'UseZink=false'+LineEnding+'EnableFeralGamemode=true');
  AssertTrue(goverlayform.SelectPrismInstance(A));
  Before:=Snapshot(Base);
  goverlayform.PrismReviewChangesClick(nil);
  Mango:=goverlayform.FPrismPreviewText.Text; Tweaks:=goverlayform.FPrismTweaksText.Text;
  AssertTrue(Pos(rsPrismPreviewMangoHud+':',Mango)>0);
  AssertEquals(0,Pos(rsPrismPreviewMesa+':',Mango));
  AssertEquals(0,Pos(rsPrismPreviewZink+':',Mango));
  AssertEquals(0,Pos(rsPrismPreviewGameMode+':',Mango));
  AssertEquals(0,Pos(rsPrismPreviewPerformanceGate+':',Mango));
  AssertTrue(Pos(rsPrismPreviewEnvGate+':',Mango)>0);
  AssertTrue(Pos(Format(rsPrismPreviewBool,[rsPrismPreviewMesa,rsPrismPreviewTrue,rsPrismPreviewTrue]),Tweaks)>0);
  AssertTrue(Pos(Format(rsPrismPreviewBool,[rsPrismPreviewZink,rsPrismPreviewFalse,rsPrismPreviewFalse]),Tweaks)>0);
  AssertTrue(Pos(rsPrismPreviewGameMode+':',Tweaks)>0);
  AssertTrue(Pos(rsPrismPreviewPerformanceGate+':',Tweaks)>0);
  AssertTrue(Pos(rsPrismTweaksSiblings,Tweaks)>0);
  AssertTrue(goverlayform.FPrismPreviewDTO.PerformanceFreeze);
  goverlayform.tweaksLabelClick(nil);
  AssertTrue(goverlayform.goverlayPageControl.ActivePage=goverlayform.FPrismTweaksPage);
  AssertTrue(goverlayform.FPrismTweaksText.ReadOnly);
  AssertTrue(goverlayform.FNavItems[4].Visible);
  AssertFalse(goverlayform.tweaksTabSheet.TabVisible);
  AssertFalse(goverlayform.launchArgsTabSheet.TabVisible);
  AssertFalse(goverlayform.FNavToolBtns[3].Visible);
  AssertEquals(Before,Snapshot(Base));
  AssertEquals(Tweaks,goverlayform.FPrismTweaksText.Text);
  { Navigation reuses the advisory DTO, never performs a hidden refresh. }
  Put(A.DataRoot+'/prismlauncher.cfg','malformed SECRET_REFRESH_CANARY');
  goverlayform.mangohudLabelClick(nil); goverlayform.tweaksLabelClick(nil);
  AssertEquals(Tweaks,goverlayform.FPrismTweaksText.Text);
  AssertEquals(Mango,goverlayform.FPrismPreviewText.Text);
  Before:=Snapshot(Base);
  goverlayform.PrismReviewChangesClick(nil);
  AssertTrue(Pos(rsPrismPreviewUnsupported,goverlayform.FPrismTweaksText.Text)>0);
  AssertTrue(Pos(rsPrismPreviewUnsupported,goverlayform.FPrismPreviewText.Text)>0);
  AssertEquals(0,Pos('SECRET_REFRESH_CANARY',goverlayform.FPrismTweaksText.Text));
  AssertEquals('',goverlayform.FPrismPreviewDTO.GeneratedSelector);
  AssertEquals(Before,Snapshot(Base));
  OldWidth:=goverlayform.Width; OldMin:=goverlayform.Constraints.MinWidth;
  try
    goverlayform.Constraints.MinWidth:=800; goverlayform.Width:=800;
    goverlayform.OnResize(goverlayform);
    AssertTrue(goverlayform.FPrismTweaksText.Width<=goverlayform.FPrismTweaksPage.ClientWidth);
    AssertTrue(goverlayform.FPrismReviewButton.Left+goverlayform.FPrismReviewButton.Width<=goverlayform.FPrismContextPanel.ClientWidth);
  finally goverlayform.Width:=OldWidth; goverlayform.Constraints.MinWidth:=OldMin; end;
  goverlayform.gamesLabelClick(nil);
  AssertFalse(goverlayform.FPrismHasPreview);
  AssertEquals('',goverlayform.FPrismTweaksText.Text);
  AssertFalse(goverlayform.FPrismTweaksPage.TabVisible);
  AssertSentinels;
end;

procedure TPrismGuiTests.TestPrismTweaksDirtyRoundTrip;
var Before,ProfileBefore,Dir,ErrorText:string; CloseAction:TCloseAction;
begin
  A.InstallationKey:='prism-root-'+SHA1Print(SHA1String(A.DataRoot)); B.InstallationKey:=A.InstallationKey;
  Put(A.DataRoot+'/prismlauncher.cfg','[General]'+LineEnding+'ConfigVersion=1.3'+LineEnding);
  AssertTrue(goverlayform.SelectPrismInstance(B));
  goverlayform.FLoadingConfig:=True; goverlayform.hudtitleEdit.Text:='Saved B';
  goverlayform.FLoadingConfig:=False; goverlayform.saveBitBtnClick(nil);
  AssertTrue(goverlayform.SelectPrismInstance(A));
  goverlayform.FLoadingConfig:=True; goverlayform.hudtitleEdit.Text:='Original A';
  goverlayform.FLoadingConfig:=False; goverlayform.saveBitBtnClick(nil);
  Dir:=goverlayform.ActiveProfileConfigDir;
  goverlayform.FLoadingConfig:=True; goverlayform.hudtitleEdit.Text:='Pending Tweaks';
  goverlayform.FLoadingConfig:=False; goverlayform.StartAutoSaveTimer;
  Before:=Snapshot(Base); ProfileBefore:=Snapshot(Dir);
  goverlayform.tweaksLabelClick(nil);
  AssertFalse(goverlayform.autoSaveTimer.Enabled);
  AssertTrue(goverlayform.FPrismDeferredAutoSave);
  AssertTrue(goverlayform.FProfileDirty);
  goverlayform.PrismReviewChangesClick(nil);
  goverlayform.autoSaveTimerTimer(nil);
  goverlayform.tweaksTabSheetShow(nil); goverlayform.launchArgsTabSheetShow(nil);
  goverlayform.SaveTweaksConfig; TTweaksMD3Helper(goverlayform.FTweaksHelper).SaveTweaksConfig;
  goverlayform.PrismCloneGlobalClick(nil);
  AssertFalse(goverlayform.FPrismCloneButton.Visible);
  AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(True,ErrorText));
  AssertFalse('dirty switch safely aborts',goverlayform.SelectPrismInstance(B));
  goverlayform.HomeGlobalBtnClick(nil); goverlayform.gamesLabelClick(nil);
  CloseAction:=caFree;
  goverlayform.FormClose(nil,CloseAction);
  AssertEquals('dirty Tweaks close blocked',Ord(caNone),Ord(CloseAction));
  AssertFalse('closing state untouched',goverlayform.FClosing);
  AssertTrue(goverlayform.FPrismDeferredAutoSave);
  AssertFalse(goverlayform.autoSaveTimer.Enabled);
  AssertTrue(goverlayform.FProfileDirty);
  AssertTrue(goverlayform.IsPrismContext);
  AssertEquals(A.StableKey,goverlayform.FActiveProfile.StableKey);
  AssertEquals('Pending Tweaks',goverlayform.hudtitleEdit.Text);
  AssertEquals(Before,Snapshot(Base)); AssertEquals(ProfileBefore,Snapshot(Dir));
  goverlayform.mangohudLabelClick(nil);
  AssertEquals('Pending Tweaks',goverlayform.hudtitleEdit.Text);
  AssertTrue(goverlayform.autoSaveTimer.Enabled); AssertTrue(goverlayform.FProfileDirty);
  AssertEquals(Before,Snapshot(Base)); AssertEquals(ProfileBefore,Snapshot(Dir));
  { Ordinary MangoHud autosave remains available after returning. }
  goverlayform.autoSaveTimerTimer(nil);
  AssertTrue(Pos('Pending Tweaks',ReadText(Dir+'MangoHud.conf'))>0);
  AssertFalse(goverlayform.FProfileDirty);
  goverlayform.tweaksLabelClick(nil);
  AssertTrue('clean switch succeeds',goverlayform.SelectPrismInstance(B));
  AssertEquals('Saved B',goverlayform.hudtitleEdit.Text);
  AssertFalse(goverlayform.FPrismHasPreview);
  goverlayform.tweaksLabelClick(nil); goverlayform.HomeGlobalBtnClick(nil);
  AssertFalse(goverlayform.IsPrismContext);
  AssertFalse(goverlayform.FPrismTweaksPage.TabVisible);
  AssertTrue('legacy Tweaks navigation restored',goverlayform.FNavItems[4].Visible);
  AssertSentinels;
end;

procedure TPrismGuiTests.TestReadOnlyPreviewAndContext;
var Before, ProfileBefore, Summary:string;
begin
  A.InstallationKey:='prism-root-'+SHA1Print(SHA1String(A.DataRoot));
  B.InstallationKey:=A.InstallationKey;
  Put(A.DataRoot+'/prismlauncher.cfg','[General]'+LineEnding+'ConfigVersion=1.3'+LineEnding);
  AssertTrue('select A',goverlayform.SelectPrismInstance(A));
  AssertFalse('no stale or initial summary',goverlayform.FPrismPreviewText.Visible);
  goverlayform.hudtitleEdit.Text:='UNSAVED editor';
  goverlayform.StartAutoSaveTimer;
  AssertTrue('timer starts',goverlayform.autoSaveTimer.Enabled);
  Before:=Snapshot(Base); ProfileBefore:=Snapshot(goverlayform.ActiveProfileConfigDir);
  goverlayform.PrismReviewChangesClick(nil);
  Summary:=goverlayform.FPrismPreviewText.Text;
  AssertTrue('notice',Pos(rsPrismPreviewNotice,Summary)>0);
  AssertTrue('ready: '+Summary,Pos(rsPrismPreviewReady,Summary)>0);
  AssertEquals('UNSAVED editor',goverlayform.hudtitleEdit.Text);
  AssertTrue('summary is read only',goverlayform.FPrismPreviewText.ReadOnly);
  AssertTrue('review button fits panel',goverlayform.FPrismReviewButton.Left+
    goverlayform.FPrismReviewButton.Width<=goverlayform.FPrismContextPanel.ClientWidth);
  AssertFalse('launch binding stays unavailable',pcLaunchBinding in goverlayform.FActiveProfile.Capabilities);
  AssertTrue('pending timer preserved',goverlayform.autoSaveTimer.Enabled);
  AssertTrue('dirty state preserved',goverlayform.FProfileDirty);
  AssertEquals(Before,Snapshot(Base));
  AssertEquals(ProfileBefore,Snapshot(goverlayform.ActiveProfileConfigDir));
  goverlayform.autoSaveTimer.Enabled:=False;
  Put(A.ConfigPath,ReadText(A.ConfigPath)+LineEnding+'OverrideEnv=true'+LineEnding+
    'Env="{\"MANGOHUD_CONFIGFILE\":\"SECRET_FOREIGN_PATH\"}"'+LineEnding);
  goverlayform.PrismReviewChangesClick(nil);
  AssertTrue('conflict: '+goverlayform.FPrismPreviewText.Text,Pos(rsPrismPreviewConflict,goverlayform.FPrismPreviewText.Text)>0);
  AssertEquals(0,Pos('SECRET_FOREIGN_PATH',goverlayform.FPrismPreviewText.Text));
  AssertTrue('select B',goverlayform.SelectPrismInstance(B));
  AssertEquals('',goverlayform.FPrismPreviewText.Text);
  goverlayform.PrismReviewChangesClick(nil);
  AssertTrue('B ready',Pos(rsPrismPreviewReady,goverlayform.FPrismPreviewText.Text)>0);
  Put(B.ConfigPath,'invalid');
  goverlayform.PrismReviewChangesClick(nil);
  AssertTrue('unsupported',Pos(rsPrismPreviewUnsupported,goverlayform.FPrismPreviewText.Text)>0);
  goverlayform.gamesLabelClick(nil);
  AssertEquals('',goverlayform.FSelectedPrismInstance.StableKey);
  AssertEquals('',goverlayform.FPrismPreviewText.Text);
  Before:=Snapshot(Base);
  goverlayform.PrismReviewChangesClick(nil);
  AssertEquals('',goverlayform.FPrismPreviewText.Text);
  AssertEquals(Before,Snapshot(Base));
  AssertSentinels;
end;

procedure TPrismGuiTests.TestVisiblePersistentContextAndKeyboardCards;
var Root: string; I, OldWidth, OldMin, OldGap: Integer; Card: TPrismCardPanel;
  Key: Word; C: TControl; OldCollapsed: Boolean;
  procedure AssertVisibleTree(Control: TControl);
  begin
    C := Control;
    while Assigned(C) do begin AssertTrue('context ancestor visible: ' + C.Name, C.Visible); C := C.Parent; end;
  end;
begin
  OldWidth := goverlayform.Width; OldMin := goverlayform.Constraints.MinWidth;
  OldCollapsed := goverlayform.FNavCollapsed;
  OldGap := goverlayform.goverlayPageControl.BorderSpacing.Top;
  Root := GetUserDir + '.local/share/PrismLauncher';
  A.DisplayName := 'A very long duplicate instance name ' + StringOfChar('x', 100);
  B.DisplayName := A.DisplayName;
  Put(A.ConfigPath, '[General]' + LineEnding + 'ConfigVersion=1.3' + LineEnding +
    'InstanceType=OneSix' + LineEnding + 'name=' + A.DisplayName + LineEnding + 'uuid=' + A.UUID);
  Put(B.ConfigPath, '[General]' + LineEnding + 'ConfigVersion=1.3' + LineEnding +
    'InstanceType=OneSix' + LineEnding + 'name=' + B.DisplayName + LineEnding + 'uuid=' + B.UUID);
  Put(Root + '/prismlauncher.cfg', '[General]' + LineEnding + 'ConfigVersion=1.3' + LineEnding + 'InstanceDir=' + A.DataRoot + '/instances');
  TGamesTabHelper(goverlayform.FGamesHelper).RefreshGameCards;
  Card := nil;
  for I := 0 to goverlayform.FCardPanels.Count - 1 do
    if TObject(goverlayform.FCardPanels[I]) is TPrismCardPanel then
      Card := TPrismCardPanel(goverlayform.FCardPanels[I]);
  AssertTrue(Card <> nil); AssertTrue('Prism card participates in keyboard traversal', Card.TabStop);
  AssertTrue('card hint distinguishes same-name instances', Pos(ExtractFileDir(Card.Instance.ConfigPath), Card.Hint) > 0);
  AssertTrue(Assigned(Card.OnKeyDown));
  Key := VK_RETURN; Card.OnKeyDown(Card, Key, []);
  AssertEquals(0, Integer(Key)); AssertEquals(Card.Instance.StableKey, goverlayform.FActiveProfile.StableKey);
  try
    goverlayform.Constraints.MinWidth := 800; goverlayform.Width := 800;
    goverlayform.FNavCollapsed := True; goverlayform.ApplyNavCollapsed; goverlayform.OnResize(goverlayform);
    AssertVisibleTree(goverlayform.FPrismContextTitle);
    AssertVisibleTree(goverlayform.FPrismContextRoot);
    AssertVisibleTree(goverlayform.FPrismContextWarning);
    AssertEquals(rsPrismCardSource + ' · ' + A.DisplayName, goverlayform.FPrismContextTitle.Caption);
    AssertEquals(ExtractFileDir(Card.Instance.ConfigPath), goverlayform.FPrismContextRoot.Caption);
    AssertEquals(rsPrismLocalOnly, goverlayform.FPrismContextWarning.Caption);
    AssertTrue(goverlayform.FPrismContextWarning.Width >= 500);
    goverlayform.PrismReviewChangesClick(nil);
    AssertTrue('narrow review button fits',goverlayform.FPrismReviewButton.Left+
      goverlayform.FPrismReviewButton.Width<=goverlayform.FPrismContextPanel.ClientWidth);
    AssertTrue('narrow summary fits',goverlayform.FPrismPreviewText.Left+
      goverlayform.FPrismPreviewText.Width<=goverlayform.FPrismContextPanel.ClientWidth);
    AssertTrue('narrow plain text notice',Pos(rsPrismPreviewNotice,goverlayform.FPrismPreviewText.Text)>0);
    AssertTrue(goverlayform.goverlayPageControl.Top >= goverlayform.FPrismContextPanel.Height);
    goverlayform.ShowStatusMessage(rsPrismLocalSaved);
    goverlayform.StatusTimerTick(nil);
    AssertVisibleTree(goverlayform.FPrismContextWarning);
    AssertEquals(rsPrismLocalOnly, goverlayform.FPrismContextWarning.Caption);
    goverlayform.gamesLabelClick(nil);
    AssertFalse('legacy return hides context surface', goverlayform.FPrismContextPanel.Visible);
    AssertEquals('legacy top gap restored', OldGap, goverlayform.goverlayPageControl.BorderSpacing.Top);
    Key := VK_SPACE; Card.OnKeyDown(Card, Key, []);
    AssertEquals(0, Integer(Key)); AssertTrue(goverlayform.IsPrismContext);
  finally
    goverlayform.gamesLabelClick(nil);
    goverlayform.Constraints.MinWidth := OldMin; goverlayform.Width := OldWidth;
    goverlayform.FNavCollapsed := OldCollapsed; goverlayform.ApplyNavCollapsed; goverlayform.OnResize(goverlayform);
  end;
  AssertSentinels;
end;

procedure TPrismGuiTests.TestCustomRootCatalogPersistenceAndRemoval;
var H: TGamesTabHelper; Error, RootPath, RootsFile, Before, ProfileDir: string;
  Saved: TPrismRootPaths; I, Count: Integer; Card: TPrismCardPanel;
begin
  H := TGamesTabHelper(goverlayform.FGamesHelper);
  RootPath := A.DataRoot; RootsFile := IncludeTrailingPathDelimiter(TConfigManager.GetGoverlayFolder) + 'prism_roots.json';
  AssertFalse(FileExists(RootsFile));
  Put(RootPath + '/prismlauncher.cfg', '[General]' + LineEnding + 'ConfigVersion=1.3' + LineEnding + 'InstanceDir=instances');
  Before := Snapshot(Base);
  try
    AssertTrue(H.AddPrismRoot(RootPath + '/./', Error));
    AssertTrue(LoadPrismRoots(RootsFile, Saved, Error)); AssertEquals(1, Length(Saved));
    AssertEquals(RootPath, Saved[0]);
    AssertTrue(H.AddPrismRoot(RootPath, Error));
    AssertTrue(LoadPrismRoots(RootsFile, Saved, Error)); AssertEquals(1, Length(Saved));
    H.RefreshGameCards;
    Card := nil; Count := 0;
    for I := 0 to goverlayform.FCardPanels.Count - 1 do
      if TObject(goverlayform.FCardPanels[I]) is TPrismCardPanel then
        if TPrismCardPanel(goverlayform.FCardPanels[I]).Instance.DataRoot = RootPath then
        begin Inc(Count); Card := TPrismCardPanel(goverlayform.FCardPanels[I]); end;
    AssertEquals(2, Count); AssertTrue(Card <> nil);
    AssertTrue(Pos(RootPath, Card.Hint) > 0);
    AssertTrue(goverlayform.SelectPrismInstance(Card.Instance));
    ProfileDir := goverlayform.ActiveProfileConfigDir;
    goverlayform.FLoadingConfig := True; goverlayform.hudtitleEdit.Text := 'retained profile';
    goverlayform.FLoadingConfig := False; goverlayform.StartAutoSaveTimer;
    AssertTrue(RenameFile(RootPath + '/prismlauncher.cfg', RootPath + '/prismlauncher.cfg.hidden'));
    H.RefreshGameCards;
    AssertTrue(H.RemovePrismRoot(RootPath, Error));
    AssertTrue(FileExists(ProfileDir + 'MangoHud.conf'));
    AssertTrue(goverlayform.IsPrismContext);
    AssertEquals(ProfileDir, goverlayform.ActiveProfileConfigDir);
    for I := 0 to goverlayform.FCardPanels.Count - 1 do
      if TObject(goverlayform.FCardPanels[I]) is TPrismCardPanel then
        AssertTrue(TPrismCardPanel(goverlayform.FCardPanels[I]).Instance.DataRoot <> RootPath);
    AssertTrue(RenameFile(RootPath + '/prismlauncher.cfg.hidden', RootPath + '/prismlauncher.cfg'));
    AssertTrue(H.AddPrismRoot(RootPath, Error));
    AssertEquals(ProfileDir, goverlayform.ActiveProfileConfigDir);
    AssertTrue(Pos('retained profile', ReadText(ProfileDir + 'MangoHud.conf')) > 0);
    AssertEquals(Before, Snapshot(Base)); AssertSentinels;
  finally
    DeleteFile(RootsFile); H.RefreshGameCards;
  end;
end;

procedure TPrismGuiTests.TestRootChangesBlockOnDirtySaveFailure;
var H: TGamesTabHelper; Error, RootsFile, ProfileDir, Before: string; Count: Integer;
begin
  H := TGamesTabHelper(goverlayform.FGamesHelper);
  RootsFile := IncludeTrailingPathDelimiter(TConfigManager.GetGoverlayFolder) + 'prism_roots.json';
  Put(A.DataRoot + '/prismlauncher.cfg', '[General]' + LineEnding + 'ConfigVersion=1.3');
  AssertTrue(H.AddPrismRoot(A.DataRoot, Error));
  AssertTrue(goverlayform.SelectPrismInstance(A));
  ProfileDir := ExcludeTrailingPathDelimiter(goverlayform.ActiveProfileConfigDir);
  Put(ProfileDir, 'file blocks local profile saves');
  try
    Before := ReadText(RootsFile); Count := goverlayform.FCardPanels.Count;
    goverlayform.FLoadingConfig := True; goverlayform.hudtitleEdit.Text := 'pending';
    goverlayform.FLoadingConfig := False; goverlayform.StartAutoSaveTimer;
    AssertFalse(H.RemovePrismRoot(A.DataRoot, Error)); AssertTrue(Error <> '');
    AssertFalse(H.AddPrismRoot(Base + '/other', Error));
    H.RefreshGameCards;
    AssertEquals(Count, goverlayform.FCardPanels.Count);
    AssertEquals(Before, ReadText(RootsFile));
    AssertEquals(A.StableKey, goverlayform.FActiveProfile.StableKey);
    AssertTrue(goverlayform.FProfileDirty); AssertSentinels;
  finally
    DeleteFile(ProfileDir); goverlayform.TrySaveMangoHudConfig;
    DeleteFile(RootsFile); H.RefreshGameCards;
  end;
end;

procedure TPrismGuiTests.TestEmptyLibraryLocatorAndCorruptRoots;
var H: TGamesTabHelper; RootCfg, RootBefore, RootsFile, Error: string; Header: TComponent;
begin
  H := TGamesTabHelper(goverlayform.FGamesHelper);
  RootCfg := GetUserDir + '.local/share/PrismLauncher/prismlauncher.cfg';
  RootBefore := ReadText(RootCfg); DeleteFile(RootCfg);
  RootsFile := IncludeTrailingPathDelimiter(TConfigManager.GetGoverlayFolder) + 'prism_roots.json';
  try
    H.RefreshGameCards;
    Header := goverlayform.FindComponent('PrismLibraryHeader');
    AssertTrue(Header <> nil);
    AssertTrue('locator exists in empty library', Header.FindComponent('PrismLocateRootButton') is TButton);
    AssertTrue(TButton(Header.FindComponent('PrismLocateRootButton')).Visible);
    AssertEquals('no internal panel name is displayed', '', TPanel(Header).Caption);
    AssertTrue('notice stays below locator buttons',
      TLabel(Header.FindComponent('PrismRootsNotice')).Top >=
      TButton(Header.FindComponent('PrismLocateRootButton')).Height);
    AssertEquals(0, goverlayform.FCardPanels.Count);
    AssertTrue(goverlayform.FindComponent('PrismEmptyLibraryLabel') <> nil);
    Put(RootsFile, '{corrupt'); H.RefreshGameCards;
    Header := goverlayform.FindComponent('PrismLibraryHeader');
    AssertTrue(Pos('preserved', TLabel(Header.FindComponent('PrismRootsNotice')).Caption) > 0);
    AssertFalse(H.AddPrismRoot(A.DataRoot, Error));
    AssertEquals('{corrupt' + LineEnding, ReadText(RootsFile));
    AssertSentinels;
  finally
    DeleteFile(RootsFile);
    if RootBefore <> '' then Put(RootCfg, RootBefore);
    H.RefreshGameCards;
  end;
end;

procedure TPrismGuiTests.TestCloneNormalizesAndIsolatesProfiles;
var Error, OldGlobal, Before, ADir, TextA, TextB, Outside: string; SourceHash: string;
  Lines: TStringList;
begin
  OldGlobal := GlobalBefore; Outside := Base + '/external-logs';
  Put(GlobalPath, 'custom_text_center=Cloned global' + LineEnding + 'fps' + LineEnding +
    'gpu_stats' + LineEnding + 'cpu_stats' + LineEnding + 'time' + LineEnding +
    'time_format=%H:%M' + LineEnding + 'font_size=18' + LineEnding + 'text_color=FF0000' + LineEnding +
    'position=bottom-left' + LineEnding + 'gl_vsync=1' + LineEnding +
    'output_folder=' + Outside + LineEnding + 'output_folder=/unrelated/logs' + LineEnding +
    'wine' + LineEnding + 'winesync' + LineEnding + 'engine_version' + LineEnding +
    'engine_short_names' + LineEnding + 'vulkan_driver' + LineEnding + 'vsync=0' + LineEnding +
    'dxapi' + LineEnding + 'fex_stats' + LineEnding + 'vkbasalt' + LineEnding + 'fsr' + LineEnding +
    'hdr' + LineEnding + 'fcat' + LineEnding + 'unknown_custom_key=discarded');
  GlobalBefore := ReadText(GlobalPath); SourceHash := SHA1Print(SHA1File(GlobalPath));
  Before := Snapshot(Base);
  try
    AssertTrue(goverlayform.SelectPrismInstance(A));
    AssertTrue('clone action visible', goverlayform.FPrismCloneButton.Visible);
    AssertTrue('clone explains normalization', Pos('Unknown custom keys', goverlayform.FPrismCloneButton.Hint) > 0);
    AssertTrue(goverlayform.CloneGlobalMangoHudToPrism(False, Error));
    ADir := goverlayform.ActiveProfileConfigDir; TextA := ReadText(ADir + 'MangoHud.conf');
    AssertTrue(Pos('custom_text_center=Cloned global', TextA) > 0);
    AssertTrue(Pos('font_size=18', TextA) > 0); AssertTrue(Pos('TEXT_COLOR=FF0000', UpperCase(TextA)) > 0);
    AssertTrue(Pos('position=bottom-left', TextA) > 0); AssertTrue(Pos('gl_vsync=1', TextA) > 0);
    AssertTrue(Pos('time_format=%H:%M', TextA) > 0);
    AssertTrue(Pos('output_folder=' + goverlayform.ActiveProfileLogDir, TextA) > 0);
    AssertFalse(DirectoryExists(Outside)); AssertFalse(Pos('unknown_custom_key', TextA) > 0);
    Lines := TStringList.Create;
    try
      Lines.Text := TextA;
      AssertEquals(-1, Lines.IndexOf('wine')); AssertEquals(-1, Lines.IndexOf('winesync'));
      AssertEquals(-1, Lines.IndexOf('engine_version')); AssertEquals(-1, Lines.IndexOf('engine_short_names'));
      AssertEquals(-1, Lines.IndexOf('vulkan_driver')); AssertEquals(-1, Lines.IndexOf('vsync=0'));
      AssertEquals(-1, Lines.IndexOf('dxapi')); AssertEquals(-1, Lines.IndexOf('fex_stats'));
      AssertEquals(-1, Lines.IndexOf('vkbasalt')); AssertEquals(-1, Lines.IndexOf('fsr'));
      AssertEquals(-1, Lines.IndexOf('hdr')); AssertEquals(-1, Lines.IndexOf('fcat'));
    finally Lines.Free; end;
    AssertEquals('Cloned global', goverlayform.hudtitleEdit.Text);
    AssertFalse(goverlayform.vulkandriverCheckBox.Visible);
    AssertEquals(rsPrismLocalOnly, goverlayform.FPrismContextWarning.Caption);
    AssertEquals(rsPrismCloneSaved, goverlayform.FPrismContextMessage.Caption);
    AssertEquals(SourceHash, SHA1Print(SHA1File(GlobalPath)));
    goverlayform.FLoadingConfig := True;
    goverlayform.vulkandriverCheckBox.Checked := True; goverlayform.vsyncComboBox.ItemIndex := 0;
    goverlayform.FLoadingConfig := False; goverlayform.saveBitBtnClick(nil);
    AssertEquals('ordinary Prism save shares capability filtering', TextA, ReadText(ADir + 'MangoHud.conf'));
    AssertTrue(goverlayform.SelectPrismInstance(B));
    AssertTrue(goverlayform.CloneGlobalMangoHudToPrism(False, Error));
    TextB := ReadText(goverlayform.ActiveProfileConfigDir + 'MangoHud.conf');
    AssertTrue(goverlayform.ActiveProfileConfigDir <> ADir);
    AssertTrue(TextA <> TextB); AssertEquals(TextA, ReadText(ADir + 'MangoHud.conf'));
    AssertFalse(FileExists(ADir + 'bgmod.conf')); AssertFalse(FileExists(ADir + 'vkBasalt.conf'));
    AssertFalse(FileExists(ADir + 'OptiScaler.ini')); AssertFalse(FileExists(ADir + 'lsfg-vk.conf'));
    AssertEquals(Before, Snapshot(Base)); AssertSentinels;
  finally
    Put(GlobalPath, OldGlobal); GlobalBefore := OldGlobal;
  end;
end;

procedure TPrismGuiTests.TestCloneFallbackAndExplicitOverwrite;
var Error, OldGlobal, OldNative, Target, Before, SourceHash: string;
begin
  OldGlobal := GlobalBefore; OldNative := NativeBefore;
  DeleteFile(GlobalPath); GlobalBefore := '';
  Put(NativePath, 'custom_text_center=Native fallback' + LineEnding + 'fps');
  NativeBefore := ReadText(NativePath); SourceHash := SHA1Print(SHA1File(NativePath));
  try
    AssertTrue(goverlayform.SelectPrismInstance(A)); Target := goverlayform.ActiveProfileConfigDir + 'MangoHud.conf';
    AssertTrue(goverlayform.CloneGlobalMangoHudToPrism(False, Error)); Before := ReadText(Target);
    AssertEquals('Native fallback', goverlayform.hudtitleEdit.Text);
    AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(False, Error));
    AssertEquals(rsPrismCloneExists, Error); AssertEquals(Before, ReadText(Target));
    AssertEquals(SourceHash, SHA1Print(SHA1File(NativePath)));
    Put(GlobalPath, 'fps_only'); GlobalBefore := ReadText(GlobalPath);
    AssertTrue(goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    AssertEquals('fps_only' + LineEnding, ReadText(Target));
    AssertFalse(goverlayform.FProfileDirty); AssertSentinels;
    goverlayform.saveBitBtnClick(nil);
    AssertEquals('fps_only' + LineEnding, ReadText(Target));
  finally
    Put(GlobalPath, OldGlobal); Put(NativePath, OldNative);
    GlobalBefore := OldGlobal; NativeBefore := OldNative;
  end;
end;

procedure TPrismGuiTests.TestCloneFailuresPreserveProfileAndControls;
var Error, OldGlobal, Target, Dir, Before, OriginalHash: string;
begin
  OldGlobal := GlobalBefore;
  Put(GlobalPath, 'custom_text_center=Global replacement' + LineEnding + 'fps');
  GlobalBefore := ReadText(GlobalPath);
  AssertTrue(goverlayform.SelectPrismInstance(A));
  goverlayform.FLoadingConfig := True; goverlayform.hudtitleEdit.Text := 'Original local';
  goverlayform.FLoadingConfig := False; AssertTrue(goverlayform.TrySaveMangoHudConfig);
  Dir := goverlayform.ActiveProfileConfigDir; Target := Dir + 'MangoHud.conf';
  Before := ReadText(Target); OriginalHash := SHA1Print(SHA1File(Target));
  try
    AssertEquals(0, fpChmod(PChar(GlobalPath), 0));
    AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    AssertEquals(rsPrismCloneSourceFailed, Error);
    AssertEquals('Original local', goverlayform.hudtitleEdit.Text);
    AssertEquals(0, fpChmod(PChar(GlobalPath), &600));
    AssertEquals(0, fpChmod(PChar(ExcludeTrailingPathDelimiter(Dir)), &500));
    AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    AssertEquals('Original local', goverlayform.hudtitleEdit.Text);
    AssertEquals(OriginalHash, SHA1Print(SHA1File(Target)));
    AssertEquals(A.StableKey, goverlayform.FActiveProfile.StableKey);
    AssertEquals(0, fpChmod(PChar(ExcludeTrailingPathDelimiter(Dir)), &700));
    DeleteFile(Target); AssertEquals(0, fpSymlink(PChar(GlobalPath), PChar(Target)));
    AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    DeleteFile(Target); Put(Target, Before);
    AssertEquals('Original local', goverlayform.hudtitleEdit.Text);
    AssertSentinels;
    DeleteFile(GlobalPath); DeleteFile(NativePath);
    AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    AssertEquals(Before, ReadText(Target));
  finally
    fpChmod(PChar(ExcludeTrailingPathDelimiter(Dir)), &700);
    Put(GlobalPath, OldGlobal); GlobalBefore := OldGlobal;
    Put(NativePath, NativeBefore);
  end;
end;

procedure TPrismGuiTests.TestCloneDirtyFailureAndTypedGuards;
var Error, OldGlobal, Target, Before: string; Context: TActiveProfileContext;
begin
  OldGlobal := GlobalBefore;
  Put(GlobalPath, 'custom_text_center=Do not copy'); GlobalBefore := ReadText(GlobalPath);
  try
    AssertFalse('legacy direct clone denied', goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    AssertTrue(goverlayform.SelectPrismInstance(A));
    AssertTrue(goverlayform.TrySaveMangoHudConfig);
    Target := goverlayform.ActiveProfileConfigDir + 'MangoHud.conf'; Before := ReadText(Target);
    Context := goverlayform.FActiveProfile;
    goverlayform.FActiveProfile.Capabilities := [];
    AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    goverlayform.FActiveProfile := Context; goverlayform.FActiveProfile.StableKey := 'invalid';
    AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    goverlayform.FActiveProfile := Context;
    AssertEquals(0, fpChmod(PChar(Target), &400));
    goverlayform.FLoadingConfig := True; goverlayform.hudtitleEdit.Text := 'Unsaved local';
    goverlayform.FLoadingConfig := False; goverlayform.StartAutoSaveTimer;
    AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    AssertTrue(goverlayform.FProfileDirty); AssertEquals('Unsaved local', goverlayform.hudtitleEdit.Text);
    AssertEquals(Before, ReadText(Target)); AssertSentinels;
  finally
    if Target <> '' then fpChmod(PChar(Target), &600);
    goverlayform.TrySaveMangoHudConfig;
    Put(GlobalPath, OldGlobal); GlobalBefore := OldGlobal;
  end;
end;

procedure TPrismGuiTests.TestCloneSourceAliasRejectedBeforeDirtySave;
var Error, OldGlobal, Target, SourceHash: string;
begin
  OldGlobal := GlobalBefore;
  AssertTrue(goverlayform.SelectPrismInstance(A));
  AssertTrue(goverlayform.TrySaveMangoHudConfig);
  Target := goverlayform.ActiveProfileConfigDir + 'MangoHud.conf';
  DeleteFile(GlobalPath);
  AssertEquals(0, fpSymlink(PChar(Target), PChar(GlobalPath)));
  GlobalBefore := ReadText(GlobalPath); SourceHash := SHA1Print(SHA1File(GlobalPath));
  try
    goverlayform.FLoadingConfig := True; goverlayform.hudtitleEdit.Text := 'Keep unsaved edits';
    goverlayform.FLoadingConfig := False; goverlayform.StartAutoSaveTimer;
    AssertFalse(goverlayform.CloneGlobalMangoHudToPrism(True, Error));
    AssertEquals(rsPrismCloneSourceAlias, Error);
    AssertTrue(goverlayform.FProfileDirty);
    AssertEquals('Keep unsaved edits', goverlayform.hudtitleEdit.Text);
    AssertEquals(SourceHash, SHA1Print(SHA1File(GlobalPath))); AssertSentinels;
  finally
    DeleteFile(GlobalPath); Put(GlobalPath, OldGlobal); GlobalBefore := OldGlobal;
    goverlayform.TrySaveMangoHudConfig;
  end;
end;

initialization
  RegisterTest(TPrismGuiTests);
end.
