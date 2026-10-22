unit prismroots;

{$mode objfpc}{$H+}

interface

uses SysUtils, prismprovider;

const
  PrismMaxAdditionalRoots = PrismMaxRoots - 2;
  PrismRootsMaxBytes = PrismMaxFileBytes;
type
  TPrismRootPaths = array of string;

{ This file belongs to GOverlay only. Loading never changes it. A failed load
  prevents subsequent UI mutations; corrupt state is never silently replaced. }
function LoadPrismRoots(const FileName: string; out Roots: TPrismRootPaths;
  out Error: string): Boolean;
function SavePrismRoots(const FileName: string; const Roots: TPrismRootPaths;
  out Error: string): Boolean;
function ValidatePrismRoot(const Path: string; out Canonical, Error: string;
  out IssueCount: Integer): Boolean;

implementation

uses Classes, BaseUnix, Unix, fpjson, jsonparser, goverlay_strings;

function NormalizeRoots(const Input: TPrismRootPaths; out Output: TPrismRootPaths): Boolean;
var I, J, N: Integer; C: string; Duplicate: Boolean;
begin
  Result := False; Output := nil;
  if Length(Input) > PrismMaxAdditionalRoots then Exit;
  for I := 0 to High(Input) do
  begin
    { Retain unavailable selections so the user can remove them. Strict link
      and access validation still happens on explicit add and every scan. }
    if not CanonicalPrismPath(Input[I], C, False) then Exit;
    Duplicate := False;
    for J := 0 to High(Output) do if Output[J] = C then Duplicate := True;
    if Duplicate then Continue;
    N := Length(Output); SetLength(Output, N + 1); Output[N] := C;
  end;
  Result := True;
end;

function LoadPrismRoots(const FileName: string; out Roots: TPrismRootPaths;
  out Error: string): Boolean;
var C, Text: string; Fd: cint; St: Stat; Got, Count: Int64;
  Data, V, A: TJSONData; Raw: TPrismRootPaths; I, Depth: Integer;
  InString, Escaped, Started, Complete: Boolean; Ch: Char;
begin
  Result := False; Roots := nil; Error := rsPrismRootsReadFailed;
  if not CanonicalPrismPath(FileName, C) then Exit;
  Fd := fpOpen(PChar(C), O_RDONLY or O_NOFOLLOW or O_NONBLOCK);
  if Fd < 0 then
  begin
    if fpGetErrNo = ESysENOENT then begin Error := ''; Exit(True); end;
    Exit;
  end;
  try
    if (fpFStat(Fd, St) <> 0) or not FPS_ISREG(St.st_mode) or
      (St.st_size < 0) or (St.st_size > PrismRootsMaxBytes) then Exit;
    SetLength(Text, St.st_size + 1); Count := 0;
    repeat
      Got := fpRead(Fd, Text[Count + 1], Length(Text) - Count);
      if Got < 0 then Exit;
      Inc(Count, Got);
    until (Got = 0) or (Count = Length(Text));
    if Count > St.st_size then Exit;
    SetLength(Text, Count);
  finally fpClose(Fd); end;
  Data := nil;
  try
    try
      { GetJSON accepts a first JSON value without requiring EOF. Validate the
        document boundary here as well as bounding its recursive parse depth. }
      if Pos(#0, Text) <> 0 then Exit;
      Depth := 0; InString := False; Escaped := False;
      Started := False; Complete := False;
      for Ch in Text do
      begin
        if Complete then
        begin
          if not (Ch in [#9, #10, #13, ' ']) then Exit;
          Continue;
        end;
        if not Started then
        begin
          if Ch in [#9, #10, #13, ' '] then Continue;
          if Ch <> '{' then Exit;
          Started := True;
        end;
        if Escaped then Escaped := False
        else if InString and (Ch = '\') then Escaped := True
        else if Ch = '"' then InString := not InString
        else if not InString then
          case Ch of
            '[', '{': begin Inc(Depth); if Depth > 4 then Exit; end;
            ']', '}': begin Dec(Depth); if Depth = 0 then Complete := True; end;
          end;
      end;
      if not Complete or InString or Escaped then Exit;
      { Linux paths are UTF-8 byte strings. Avoid conversion to the process's
        locale code page, which can replace Unicode bytes in standalone tests. }
      Data := GetJSON(Text, False);
      if not (Data is TJSONObject) or (Data.Count <> 2) then Exit;
      V := TJSONObject(Data).Find('version'); A := TJSONObject(Data).Find('roots');
      if (V = nil) or (V.JSONType <> jtNumber) or (V.AsJSON <> '1') or
        not (A is TJSONArray) or (A.Count > PrismMaxAdditionalRoots) then Exit;
      SetLength(Raw, A.Count);
      for I := 0 to A.Count - 1 do
      begin
        if A.Items[I].JSONType <> jtString then Exit;
        Raw[I] := A.Items[I].AsString;
      end;
      if not NormalizeRoots(Raw, Roots) then begin Roots := nil; Exit; end;
      Result := True; Error := '';
    except Roots := nil; end;
  finally Data.Free; end;
end;

function SavePrismRoots(const FileName: string; const Roots: TPrismRootPaths;
  out Error: string): Boolean;
var Canonical, Parent, CheckedParent, TempName, Text: string; Normalized: TPrismRootPaths;
  Obj: TJSONObject; Arr: TJSONArray; I, Fd: Integer; St: Stat;
  Existing: TPrismRootPaths; Offset, Wrote: Int64;
begin
  Result := False; Error := rsPrismRootsWriteFailed;
  if not NormalizeRoots(Roots, Normalized) or not CanonicalPrismPath(FileName, Canonical) then Exit;
  { Independently guard callers against replacing corrupt or unsafe state. }
  if not LoadPrismRoots(Canonical, Existing, Error) then Exit;
  Error := rsPrismRootsWriteFailed;
  Parent := ExtractFileDir(Canonical);
  if not ForceDirectories(Parent) or not CanonicalPrismPath(Parent, CheckedParent) then Exit;
  Obj := TJSONObject.Create; Arr := TJSONArray.Create;
  try
    Obj.Add('version', 1); Obj.Add('roots', Arr);
    for I := 0 to High(Normalized) do Arr.Add(Normalized[I]);
    Text := Obj.AsJSON;
  finally Obj.Free; end;
  if Length(Text) > PrismRootsMaxBytes then Exit;
  Fd := -1; TempName := '';
  for I := 0 to 99 do
  begin
    TempName := Canonical + '.tmp-' + IntToStr(fpGetPid) + '-' + IntToStr(I);
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
    if (fpLStat(PChar(Canonical), St) = 0) and not FPS_ISREG(St.st_mode) then Exit;
    Result := fpRename(PChar(TempName), PChar(Canonical)) = 0;
    if Result then Error := '';
  finally
    fpClose(Fd);
    if not Result then fpUnlink(PChar(TempName));
  end;
end;

function ValidatePrismRoot(const Path: string; out Canonical, Error: string;
  out IssueCount: Integer): Boolean;
var Input: TPrismDiscoveryInput; Discovery: TPrismDiscoveryResult;
begin
  Result := False; Canonical := ''; Error := rsPrismRootInvalid; IssueCount := 0;
  if not CanonicalPrismPath(Path, Canonical) then Exit;
  Input := Default(TPrismDiscoveryInput);
  SetLength(Input.AdditionalRoots, 1); Input.AdditionalRoots[0] := Canonical;
  Discovery := DiscoverPrism(Input);
  IssueCount := Length(Discovery.Issues);
  Result := Length(Discovery.Installations) = 1;
  if Result then Error := '';
end;

end.
