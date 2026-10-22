unit prismprovider;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils;

const
  PrismMaxFileBytes = 1024 * 1024;
  PrismMaxEntries = 4096;
  PrismMaxRoots = 64;
  PrismMaxTextBytes = 4096;

type
  TPrismInstallationKind = (pikNative, pikFlatpak, pikCustom);
  TPrismIssueKind = (piInvalidInput, piUnsafePath, piReadError,
    piMalformedConfig, piUnsupportedVersion, piUnsupportedInstanceType, piInvalidUUID, piDuplicateUUID,
    piInvalidMetadata, piLimitExceeded);
  TPrismIssue = record
    Kind: TPrismIssueKind;
    Path: string;
  end;
  TPrismIssues = array of TPrismIssue;
  TPrismInstallation = record
    DataRoot, InstanceRoot, StableKey: string;
    Kind: TPrismInstallationKind;
  end;
  TPrismInstallations = array of TPrismInstallation;
  TPrismInstance = record
    InstallationKey, DataRoot, Folder, UUID, StableKey, DisplayName: string;
    MinecraftVersion, Loader, IconKey, ConfigPath: string;
    UsesFolderIdentity: Boolean;
  end;
  TPrismInstances = array of TPrismInstance;
  TPrismDiscoveryInput = record
    HomeDir, XdgDataHome: string;
    AdditionalRoots: array of string;
  end;
  TPrismDiscoveryResult = record
    Installations: TPrismInstallations;
    Instances: TPrismInstances;
    Issues: TPrismIssues;
  end;

{ Explicit inputs only: no environment lookup, application state, or writes.
  Custom roots and an absolute InstanceDir explicitly authorize external paths.
  Symlinks are refused, including in every existing ancestor. This is discovery,
  not a filesystem transaction; callers must revalidate before future writes. }
function DiscoverPrism(const Input: TPrismDiscoveryInput): TPrismDiscoveryResult;

implementation

uses BaseUnix, SHA1, fpjson, jsonparser;

procedure Issue(var R: TPrismDiscoveryResult; K: TPrismIssueKind; const P: string);
var N: SizeInt;
begin
  N := Length(R.Issues);
  if N >= PrismMaxEntries then Exit;
  SetLength(R.Issues, N + 1);
  R.Issues[N].Kind := K;
  R.Issues[N].Path := Copy(P, 1, PrismMaxTextBytes);
end;

function Hash(const S: string): string;
begin
  Result := SHA1Print(SHA1String(S));
end;

function SafePath(const P: string; out Canonical: string): Boolean;
var Parts: TStringList; I: Integer; Current: string; St: Stat;
begin
  Result := False;
  Canonical := '';
  if (P = '') or (Length(P) > PrismMaxTextBytes) or (P[1] <> '/') or
     (Pos(#0, P) <> 0) then Exit;
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := '/';
    Parts.QuoteChar := #0;
    Parts.DelimitedText := P;
    Current := '';
    for I := 0 to Parts.Count - 1 do
    begin
      if Parts[I] = '..' then Exit;
      if (Parts[I] = '') or (Parts[I] = '.') then Continue;
      Current := Current + '/' + Parts[I];
      if fpLStat(PChar(Current), St) = 0 then
      begin
        if FPS_ISLNK(St.st_mode) then Exit;
      end
      else if fpGetErrNo <> ESysENOENT then Exit;
    end;
    if Current = '' then Current := '/';
    Canonical := Current;
    Result := True;
  finally
    Parts.Free;
  end;
end;

function ReadBounded(const P: string; out S: string;
  var R: TPrismDiscoveryResult): Boolean;
var Canonical: string; Fd: cint; St: Stat; Count, Got: Int64;
begin
  Result := False;
  S := '';
  if not SafePath(P, Canonical) then
  begin Issue(R, piUnsafePath, P); Exit; end;
  Fd := fpOpen(PChar(Canonical), O_RDONLY or O_NOFOLLOW or O_NONBLOCK);
  if Fd < 0 then
  begin Issue(R, piReadError, P); Exit; end;
  try
    if (fpFStat(Fd, St) <> 0) or not FPS_ISREG(St.st_mode) then
    begin Issue(R, piUnsafePath, P); Exit; end;
    if (St.st_size < 0) or (St.st_size > PrismMaxFileBytes) then
    begin Issue(R, piLimitExceeded, P); Exit; end;
    SetLength(S, St.st_size + 1);
    Count := 0;
    repeat
      Got := fpRead(Fd, S[Count + 1], Length(S) - Count);
      if Got < 0 then
      begin Issue(R, piReadError, P); Exit; end;
      Inc(Count, Got);
    until (Got = 0) or (Count = Length(S));
    if Count > St.st_size then
    begin Issue(R, piLimitExceeded, P); Exit; end;
    SetLength(S, Count);
    Result := Pos(#0, S) = 0;
    if not Result then Issue(R, piMalformedConfig, P);
  finally
    fpClose(Fd);
  end;
end;

function Hex(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
    else Result := -1;
  end;
end;

function DecodeKey(const S: string; out V: string): Boolean;
var I, J, N, Digits: Integer; U: UnicodeString;
begin
  V := ''; I := 1; Result := False;
  while I <= Length(S) do
  begin
    if S[I] <> '%' then V := V + S[I]
    else
    begin
      Inc(I); Digits := 2;
      if (I <= Length(S)) and (S[I] = 'U') then
      begin Inc(I); Digits := 4; end;
      N := 0;
      for J := 1 to Digits do
      begin
        if (I > Length(S)) or (Hex(S[I]) < 0) then Exit;
        N := N * 16 + Hex(S[I]); Inc(I);
      end;
      if Digits = 2 then V := V + Chr(N)
      else begin U := WideChar(N); V := V + UTF8Encode(U); end;
      Dec(I);
    end;
    Inc(I);
  end;
  Result := True;
end;

{ Qt IniFormat scalar QString subset. Lists and typed QVariant payloads fail
  closed for relevant keys. Hex escapes represent UTF-16 code units. }
function DecodeValue(const S: string; out V: string): Boolean;
var I, N, H, LowUnit: Integer; Quoted: Boolean; C: Char; U: UnicodeString;
begin
  Result := False; V := ''; Quoted := False; I := 1;
  while I <= Length(S) do
  begin
    C := S[I];
    if C = '"' then Quoted := not Quoted
    else if (C = ';') and not Quoted then Break
    else if (C = ',') and not Quoted then Exit
    else if C = '\' then
    begin
      Inc(I); if I > Length(S) then Exit;
      case S[I] of
        'a': V := V + #7;
        'b': V := V + #8;
        'f': V := V + #12;
        'n': V := V + #10;
        'r': V := V + #13;
        't': V := V + #9;
        'v': V := V + #11;
        '"', '\', '''', '?': V := V + S[I];
        'x': begin
          N := 0; H := 0;
          while (I < Length(S)) and (Hex(S[I + 1]) >= 0) do
          begin
            Inc(I); Inc(H); if H > 4 then Exit;
            N := N * 16 + Hex(S[I]);
          end;
          if H = 0 then Exit;
          if (N >= $D800) and (N <= $DBFF) then
          begin
            if (I + 2 > Length(S)) or (S[I + 1] <> '\') or (S[I + 2] <> 'x') then Exit;
            Inc(I, 2); LowUnit := 0; H := 0;
            while (I < Length(S)) and (Hex(S[I + 1]) >= 0) do
            begin
              Inc(I); Inc(H); if H > 4 then Exit;
              LowUnit := LowUnit * 16 + Hex(S[I]);
            end;
            if (LowUnit < $DC00) or (LowUnit > $DFFF) then Exit;
            U := WideChar(N) + WideChar(LowUnit);
          end
          else begin
            if (N >= $DC00) and (N <= $DFFF) then Exit;
            U := WideChar(N);
          end;
          V := V + UTF8Encode(U);
        end;
        else Exit;
      end;
    end
    else V := V + C;
    Inc(I);
  end;
  if Quoted or (Length(V) > PrismMaxTextBytes) or (Pos(#0, V) <> 0) then Exit;
  if Copy(V, 1, 2) = '@@' then Delete(V, 1, 1)
  else if (V <> '') and (V[1] = '@') then Exit;
  Result := True;
end;

function ReadSettings(const P: string; Values: TStrings;
  var R: TPrismDiscoveryResult): Boolean;
var S, L, Section, Key, V: string; Lines: TStringList; I, EqualPos: Integer;
  HasGeneral, Relevant, Malformed: Boolean;
begin
  Result := False;
  if not ReadBounded(P, S, R) then Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := S; Section := ''; HasGeneral := False; Malformed := False;
    if Lines.Count > 32768 then
    begin Issue(R, piLimitExceeded, P); Exit; end;
    for I := 0 to Lines.Count - 1 do
    begin
      L := Trim(Lines[I]);
      if (L = '') or (L[1] in [';', '#']) then Continue;
      if L[1] = '[' then
      begin
        if L[Length(L)] <> ']' then begin Malformed := True; Break; end;
        Section := Copy(L, 2, Length(L) - 2);
        if Section = 'General' then HasGeneral := True;
        Continue;
      end;
      EqualPos := Pos('=', L);
      if EqualPos = 0 then begin Malformed := True; Break; end;
      if not DecodeKey(Trim(Copy(L, 1, EqualPos - 1)), Key) then begin Malformed := True; Break; end;
      Relevant := (Section = 'General') and ((Key = 'ConfigVersion') or
        (Key = 'InstanceDir') or (Key = 'name') or (Key = 'uuid') or
        (Key = 'iconKey') or (Key = 'InstanceType'));
      if not Relevant then Continue;
      if (Values.IndexOfName(Key) >= 0) or
         not DecodeValue(Trim(Copy(L, EqualPos + 1, MaxInt)), V) then
      begin Malformed := True; Break; end;
      Values.Values[Key] := V;
      { TStringList.Values deletes empty values; preserve their presence. }
      if V = '' then Values.Add(Key + '=');
    end;
    if Malformed or not HasGeneral then
    begin Issue(R, piMalformedConfig, P); Exit; end;
    if Values.Values['ConfigVersion'] <> '1.3' then
    begin Issue(R, piUnsupportedVersion, P); Exit; end;
    Result := True;
  finally
    Lines.Free;
  end;
end;

function ValidUUID(const S: string): Boolean;
var C: Char;
begin
  Result := False;
  if Length(S) <> 32 then Exit;
  for C in S do if Hex(C) < 0 then Exit;
  Result := True;
end;

function SafeIcon(const S: string): Boolean;
var C: Char;
begin
  Result := (S <> '') and (Length(S) <= 128) and (S <> '.') and (S <> '..');
  for C in S do if not (C in ['a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.']) then Result := False;
end;

procedure Metadata(var Inst: TPrismInstance; var R: TPrismDiscoveryResult);
var P, S, Id, Version: string; Data, Components, Item: TJSONData; I, Depth: Integer;
  InString, Escape: Boolean; C: Char;
begin
  P := ExtractFilePath(Inst.ConfigPath) + 'mmc-pack.json';
  if not FileExists(P) then Exit;
  if not ReadBounded(P, S, R) then Exit;
  Data := nil;
  try
    try
      Depth := 0; InString := False; Escape := False;
      for C in S do
      begin
        if Escape then Escape := False
        else if InString and (C = '\') then Escape := True
        else if C = '"' then InString := not InString
        else if not InString then
          case C of
            '[', '{': begin Inc(Depth); if Depth > 32 then raise Exception.Create('depth'); end;
            ']', '}': Dec(Depth);
          end;
      end;
      Data := GetJSON(S);
      if Data.JSONType <> jtObject then raise Exception.Create('object');
      Components := TJSONObject(Data).Find('components');
      if (Components = nil) or (Components.JSONType <> jtArray) or
         (Components.Count > 256) then raise Exception.Create('components');
      for I := 0 to Components.Count - 1 do
      begin
        Item := Components.Items[I];
        if Item.JSONType <> jtObject then raise Exception.Create('component');
        if (TJSONObject(Item).Find('uid') = nil) or
           (TJSONObject(Item).Find('uid').JSONType <> jtString) or
           (TJSONObject(Item).Find('version') = nil) or
           (TJSONObject(Item).Find('version').JSONType <> jtString) then
          raise Exception.Create('fields');
        Id := TJSONObject(Item).Get('uid', '');
        Version := TJSONObject(Item).Get('version', '');
        if (Length(Id) > 256) or (Length(Version) > 256) then raise Exception.Create('length');
        if Id = 'net.minecraft' then Inst.MinecraftVersion := Version;
        if (Id = 'net.fabricmc.fabric-loader') or (Id = 'net.minecraftforge') or
           (Id = 'org.quiltmc.quilt-loader') or (Id = 'net.neoforged') then
          Inst.Loader := Id + ' ' + Version;
      end;
    except
      Inst.MinecraftVersion := ''; Inst.Loader := '';
      Issue(R, piInvalidMetadata, P);
    end;
  finally
    Data.Free;
  end;
end;

function DiscoverPrism(const Input: TPrismDiscoveryInput): TPrismDiscoveryResult;
var R: TPrismDiscoveryResult; Roots: TStringList; Kinds: array of TPrismInstallationKind;
  I, J, K, N, TotalSeen: Integer; Root, P, Canonical, Identity: string;
  Settings, UUIDs: TStringList; Installation: TPrismInstallation; Inst: TPrismInstance;
  Search: TSearchRec; Pending: TPrismInstances; Duplicate, Truncated: Boolean;
  procedure AddRoot(const Value: string; Kind: TPrismInstallationKind);
  var Index: Integer; C: string;
  begin
    if not SafePath(Value, C) then begin Issue(R, piUnsafePath, Value); Exit; end;
    if Roots.IndexOf(C) >= 0 then Exit;
    Index := Roots.Add(C); SetLength(Kinds, Index + 1); Kinds[Index] := Kind;
  end;
begin
  R := Default(TPrismDiscoveryResult);
  Roots := TStringList.Create; Settings := TStringList.Create; UUIDs := TStringList.Create;
  UUIDs.Sorted := True; UUIDs.Duplicates := dupAccept; TotalSeen := 0;
  Settings.CaseSensitive := True;
  Roots.CaseSensitive := True;
  try
    if Input.XdgDataHome <> '' then AddRoot(Input.XdgDataHome + '/PrismLauncher', pikNative)
    else if Input.HomeDir <> '' then AddRoot(Input.HomeDir + '/.local/share/PrismLauncher', pikNative);
    if Input.HomeDir <> '' then AddRoot(Input.HomeDir + '/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher', pikFlatpak);
    if Length(Input.AdditionalRoots) > PrismMaxRoots - 2 then
      Issue(R, piLimitExceeded, 'AdditionalRoots');
    for I := 0 to Length(Input.AdditionalRoots) - 1 do
    begin
      if I >= PrismMaxRoots - 2 then Break;
      AddRoot(Input.AdditionalRoots[I], pikCustom);
    end;
    for I := 0 to Roots.Count - 1 do
    begin
      Root := Roots[I];
      if not DirectoryExists(Root) then Continue;
      P := Root + '/prismlauncher.cfg'; Settings.Clear;
      if not ReadSettings(P, Settings, R) then Continue;
      Installation := Default(TPrismInstallation);
      Installation.DataRoot := Root; Installation.Kind := Kinds[I];
      Installation.StableKey := 'prism-root-' + Hash(Root);
      P := Settings.Values['InstanceDir'];
      if P = '' then P := 'instances';
      if P[1] <> '/' then P := Root + '/' + P;
      if not SafePath(P, Canonical) then
      begin Issue(R, piUnsafePath, P); Continue; end;
      Installation.InstanceRoot := Canonical;
      N := Length(R.Installations); SetLength(R.Installations, N + 1);
      R.Installations[N] := Installation;
      Pending := nil; UUIDs.Clear; Truncated := False;
      if not DirectoryExists(Canonical) then Continue;
      if FindFirst(Canonical + '/*', faAnyFile, Search) <> 0 then Continue;
      try
        repeat
          if (Search.Name = '.') or (Search.Name = '..') then Continue;
          Inc(TotalSeen);
          if TotalSeen > PrismMaxEntries then
          begin Issue(R, piLimitExceeded, Canonical); Truncated := True; Break; end;
          P := Canonical + '/' + Search.Name;
          if not SafePath(P, Identity) then begin Issue(R, piUnsafePath, P); Continue; end;
          if not DirectoryExists(P) then Continue;
          Settings.Clear;
          if not ReadSettings(P + '/instance.cfg', Settings, R) then Continue;
          if Settings.Values['InstanceType'] <> 'OneSix' then
          begin Issue(R, piUnsupportedInstanceType, P + '/instance.cfg'); Continue; end;
          Inst := Default(TPrismInstance);
          Inst.UUID := LowerCase(Settings.Values['uuid']);
          if (Settings.IndexOfName('uuid') >= 0) and not ValidUUID(Inst.UUID) then
          begin Issue(R, piInvalidUUID, P + '/instance.cfg'); Continue; end;
          Inst.UsesFolderIdentity := Inst.UUID = '';
          if Inst.UUID <> '' then UUIDs.Add(Inst.UUID);
          if Inst.UsesFolderIdentity then Identity := 'folder:' + P
          else Identity := 'uuid:' + Inst.UUID;
          Inst.StableKey := 'prism-' + Hash(Root + #0 + Identity);
          Inst.InstallationKey := Installation.StableKey;
          Inst.DataRoot := Root; Inst.Folder := Search.Name;
          Inst.ConfigPath := P + '/instance.cfg';
          Inst.DisplayName := Settings.Values['name'];
          if Inst.DisplayName = '' then Inst.DisplayName := Search.Name;
          Inst.IconKey := Settings.Values['iconKey'];
          if not SafeIcon(Inst.IconKey) then Inst.IconKey := 'default';
          Metadata(Inst, R);
          N := Length(Pending); SetLength(Pending, N + 1); Pending[N] := Inst;
        until FindNext(Search) <> 0;
      finally
        FindClose(Search);
      end;
      { An incomplete root cannot establish UUID uniqueness. Publish none of
        its candidates, and stop once the global scan budget is exhausted. }
      if Truncated then Break;
      for J := 0 to Length(Pending) - 1 do
      begin
        Duplicate := False;
        if Pending[J].UUID <> '' then
        begin
          K := UUIDs.IndexOf(Pending[J].UUID);
          Duplicate := ((K > 0) and (UUIDs[K - 1] = Pending[J].UUID)) or
            ((K < UUIDs.Count - 1) and (UUIDs[K + 1] = Pending[J].UUID));
        end;
        if Duplicate then Issue(R, piDuplicateUUID, Pending[J].ConfigPath)
        else begin
          N := Length(R.Instances); SetLength(R.Instances, N + 1); R.Instances[N] := Pending[J];
        end;
      end;
    end;
  finally
    UUIDs.Free; Settings.Free; Roots.Free;
  end;
  Result := R;
end;

end.
