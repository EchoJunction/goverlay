program dev_probe;
{$mode objfpc}{$H+}
uses cthreads, Interfaces, Forms, SysUtils, Classes, overlayunit,
  prismprovider, prismroots, configmanager, games_tab;
var Input: TPrismDiscoveryInput; Discovery: TPrismDiscoveryResult;
  Roots: TPrismRootPaths; ErrorText, Expected, Before, After: string;
  I, Cards: Integer; Paths: TStringList;

function ReadText(const P: string): string;
var S: TFileStream;
begin
  S := TFileStream.Create(P, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then S.ReadBuffer(Result[1], S.Size);
  finally S.Free; end;
end;

procedure Require(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

procedure Run;
begin
  Require(GetEnvironmentVariable('HOME') = '/home/tester', 'Unexpected HOME');
  Require(FileExists('/home/tester/.goverlay-synthetic-dev-v1'), 'Missing dev marker');
  Require((ParamStr(1) = 'write') or (ParamStr(1) = 'read'), 'Expected write/read');
  Input := Default(TPrismDiscoveryInput);
  Input.HomeDir := '/home/tester'; Input.XdgDataHome := '/home/tester/.local/share';
  Require(LoadPrismRoots('/home/tester/.config/goverlay/prism_roots.json', Roots, ErrorText), 'Cannot read synthetic roots');
  Input.AdditionalRoots := Roots; Discovery := DiscoverPrism(Input);
  Require(Length(Discovery.Installations) = 3, 'Expected three synthetic installations');
  Require(Length(Discovery.Instances) = 6, 'Expected six synthetic instances');
  Require(Length(Discovery.Issues) = 0, 'Unexpected synthetic discovery issue');
  RequireDerivedFormResource := True; Application.Scaled := True;
  Application.Initialize; Application.CreateForm(Tgoverlayform, goverlayform);
  goverlayform.Show;
  for I := 1 to 20 do begin Application.ProcessMessages; Sleep(25); end;
  Cards := 0;
  for I := 0 to goverlayform.FCardPanels.Count - 1 do
    if TObject(goverlayform.FCardPanels[I]) is TPrismCardPanel then Inc(Cards);
  Require(Cards = 6, 'Expected six actual synthetic Prism GUI cards');
  Paths := TStringList.Create;
  try
    for I := 0 to High(Discovery.Instances) do
    begin
      WriteLn('Probe ', ParamStr(1), ' fixture ', I + 1); Flush(Output);
      Before := ReadText(Discovery.Instances[I].ConfigPath);
      Require(goverlayform.SelectPrismInstance(Discovery.Instances[I]), 'Synthetic selection failed');
      Expected := 'DEV profile ' + IntToStr(I + 1);
      if ParamStr(1) = 'write' then
      begin
        goverlayform.FLoadingConfig := True;
        goverlayform.hudtitleEdit.Text := Expected;
        goverlayform.fpsCheckBox.Checked := True;
        goverlayform.FLoadingConfig := False;
        goverlayform.saveBitBtnClick(nil);
      end;
      Require(goverlayform.hudtitleEdit.Text = Expected, 'Persisted local title differs');
      Require(FileExists(goverlayform.ActiveProfileConfigDir + 'MangoHud.conf'), 'Missing local config');
      Require(Paths.IndexOf(goverlayform.ActiveProfileConfigDir) < 0, 'Profile paths collided');
      Paths.Add(goverlayform.ActiveProfileConfigDir);
      After := ReadText(Discovery.Instances[I].ConfigPath);
      Require(Before = After, 'Synthetic Prism cfg changed');
    end;
    goverlayform.gamesLabelClick(nil);
    WriteLn('PASS: 3 roots / 6 distinct local profiles; ', ParamStr(1),
      ' in a fresh GUI process; exact Prism cfg bytes preserved');
  finally Paths.Free; end;
end;
begin
  try
    Run;
  except
    on E: Exception do
    begin WriteLn(StdErr, 'FAIL: ', E.Message); Halt(1); end;
  end;
  Halt(0);
end.
