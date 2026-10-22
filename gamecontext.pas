unit gamecontext;
{$mode objfpc}{$H+}
interface
uses SysUtils, prismprovider;
type
  TProfileSource = (psLegacy, psPrism);
  TProfileCapability = (pcMangoHudEdit, pcLegacyTools, pcLaunchBinding);
  TProfileCapabilities = set of TProfileCapability;
  TActiveProfileContext = record
    Source: TProfileSource;
    StableKey, DisplayName, ConfigDir, LogDir, InstanceRoot: string;
    Capabilities: TProfileCapabilities;
  end;
function PrismProfileContext(const Instance: TPrismInstance; const HostDataDir: string;
  out Context: TActiveProfileContext): Boolean;
implementation
function PrismProfileContext(const Instance: TPrismInstance; const HostDataDir: string;
  out Context: TActiveProfileContext): Boolean;
var I: Integer;
begin
  Context := Default(TActiveProfileContext); Result := False;
  if (Length(Instance.StableKey) <> 46) or (Copy(Instance.StableKey, 1, 6) <> 'prism-') then Exit;
  for I := 7 to Length(Instance.StableKey) do
    if not (Instance.StableKey[I] in ['0'..'9', 'a'..'f']) then Exit;
  if (HostDataDir = '') or (HostDataDir[1] <> '/') then Exit;
  Context.Source := psPrism; Context.StableKey := Instance.StableKey;
  Context.DisplayName := Instance.DisplayName;
  Context.ConfigDir := IncludeTrailingPathDelimiter(HostDataDir) + 'goverlay/gameconfig/prism/' + Instance.StableKey + '/';
  Context.LogDir := IncludeTrailingPathDelimiter(HostDataDir) + 'goverlay/logs/prism/' + Instance.StableKey + '/';
  Context.InstanceRoot := ExcludeTrailingPathDelimiter(ExtractFilePath(Instance.ConfigPath));
  Context.Capabilities := [pcMangoHudEdit]; Result := True;
end;
end.
