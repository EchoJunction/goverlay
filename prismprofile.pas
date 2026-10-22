unit prismprofile;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, gamecontext;

function PrismCloneTarget(const Context: TActiveProfileContext; const HostDataDir: string;
  out Target, Error: string): Boolean;
function ReadMangoHudCloneSource(const FileName, Target: string; Output: TStrings;
  out Error: string): Boolean;
function WritePrismClone(const Context: TActiveProfileContext; const HostDataDir: string;
  const Lines: TStrings; ReplaceExisting: Boolean; out Error: string): Boolean;

implementation
uses BaseUnix, Unix, prismprovider, goverlay_strings;

function PrismCloneTarget(const Context: TActiveProfileContext; const HostDataDir: string;
  out Target, Error: string): Boolean;
var Instance: TPrismInstance; Expected: TActiveProfileContext; C: string;
begin
  Result := False; Target := ''; Error := rsPrismCloneFailed;
  if (Context.Source <> psPrism) or not (pcMangoHudEdit in Context.Capabilities) then Exit;
  Instance := Default(TPrismInstance); Instance.StableKey := Context.StableKey;
  if not PrismProfileContext(Instance, HostDataDir, Expected) or
    (Context.ConfigDir <> Expected.ConfigDir) or (Context.LogDir <> Expected.LogDir) then Exit;
  Target := Context.ConfigDir + 'MangoHud.conf';
  if not CanonicalPrismPath(Target, C) or not CanonicalPrismPath(Context.LogDir, C) then Exit;
  Result := True; Error := '';
end;

function ReadMangoHudCloneSource(const FileName, Target: string; Output: TStrings;
  out Error: string): Boolean;
var Fd: Integer; St, TargetStat: Stat; Text: string; Count, Got: Int64;
begin
  Result := False; Error := rsPrismCloneSourceFailed;
  if Output = nil then Exit;
  Fd := fpOpen(PChar(FileName), O_RDONLY or O_NONBLOCK);
  if Fd < 0 then Exit;
  try
    if (fpFStat(Fd, St) <> 0) or not FPS_ISREG(St.st_mode) or
      (St.st_size < 0) or (St.st_size > PrismMaxFileBytes) then Exit;
    if (fpStat(PChar(Target), TargetStat) = 0) and
      (St.st_dev = TargetStat.st_dev) and (St.st_ino = TargetStat.st_ino) then
    begin Error := rsPrismCloneSourceAlias; Exit; end;
    SetLength(Text, St.st_size + 1); Count := 0;
    repeat
      Got := fpRead(Fd, Text[Count + 1], Length(Text) - Count);
      if Got < 0 then Exit;
      Inc(Count, Got);
    until (Got = 0) or (Count = Length(Text));
    if Count > St.st_size then Exit;
    SetLength(Text, Count);
    if Pos(#0, Text) <> 0 then Exit;
    Output.Text := Text;
    Result := True; Error := '';
  finally fpClose(Fd); end;
end;

function WritePrismClone(const Context: TActiveProfileContext; const HostDataDir: string;
  const Lines: TStrings; ReplaceExisting: Boolean; out Error: string): Boolean;
var Target, C, TempName, Text: string; Fd, I: Integer; St: Stat; Offset, Wrote: Int64;
begin
  Result := False; Error := rsPrismCloneFailed;
  if (Lines = nil) or not PrismCloneTarget(Context, HostDataDir, Target, Error) then Exit;
  Error := rsPrismCloneFailed;
  if fpLStat(PChar(Target), St) = 0 then
  begin
    if not FPS_ISREG(St.st_mode) then Exit;
    if not ReplaceExisting then begin Error := rsPrismCloneExists; Exit; end;
  end
  else if fpGetErrNo <> ESysENOENT then Exit;
  if not ForceDirectories(Context.ConfigDir) or not CanonicalPrismPath(Target, C) then Exit;
  Text := Lines.Text;
  if Length(Text) > PrismMaxFileBytes then Exit;
  Fd := -1; TempName := '';
  for I := 0 to 99 do
  begin
    TempName := Target + '.clone-' + IntToStr(fpGetPid) + '-' + IntToStr(I);
    Fd := fpOpen(PChar(TempName), O_WRONLY or O_CREAT or O_EXCL or O_NOFOLLOW, &600);
    if Fd >= 0 then Break;
    if fpGetErrNo <> ESysEEXIST then Exit;
  end;
  if Fd < 0 then Exit;
  try
    Offset := 0;
    while Offset < Length(Text) do
    begin
      Wrote := fpWrite(Fd, Text[Offset + 1], Length(Text) - Offset);
      if Wrote <= 0 then Exit;
      Inc(Offset, Wrote);
    end;
    if fpFsync(Fd) <> 0 then Exit;
    if not CanonicalPrismPath(Target, C) then Exit;
    if fpLStat(PChar(Target), St) = 0 then
    begin
      if not FPS_ISREG(St.st_mode) then Exit;
      if not ReplaceExisting then begin Error := rsPrismCloneExists; Exit; end;
    end
    else if fpGetErrNo <> ESysENOENT then Exit;
    if ReplaceExisting then Result := fpRename(PChar(TempName), PChar(Target)) = 0
    else
    begin
      { A link publishes the completed file atomically without replacing a
        destination created since the checks above. }
      Result := fpLink(PChar(TempName), PChar(Target)) = 0;
      if not Result and (fpGetErrNo = ESysEEXIST) then Error := rsPrismCloneExists;
    end;
    if Result then Error := '';
  finally
    fpClose(Fd);
    if not Result or not ReplaceExisting then fpUnlink(PChar(TempName));
  end;
end;

end.
