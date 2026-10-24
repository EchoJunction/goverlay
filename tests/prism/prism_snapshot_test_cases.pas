unit prism_snapshot_test_cases;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, fpcunit, testregistry, prismdocument, prismenv, prismsnapshot;
type
  TPrismSnapshotTests = class(TTestCase)
  private
    procedure Ready(const G, L: RawByteString; out S: TPrismSettingsSnapshot);
    procedure Refuses(const G, L: RawByteString; Status: TPrismAssessmentStatus;
      Reason: TPrismAssessmentReason);
  published
    procedure DefaultsAndRawDocuments;
    procedure AllPerformanceSources;
    procedure DormantSemanticValues;
    procedure SelectedSemanticValues;
    procedure GatesAndAliases;
    procedure EnvSourcesAndExactValues;
    procedure EffectiveCollisions;
    procedure EffectiveWrapperAndPreload;
    procedure StructuralAndVersionGates;
  end;
implementation
const H: RawByteString = '[General]'#10'ConfigVersion=1.3'#10;
  Names: array[TPrismPerformanceFlag] of RawByteString =
    ('EnableMangoHud','UseDiscreteGpu','UseZink','EnableFeralGamemode');
{ Synthetic fixture convenience: JSON objects are always Qt whole-quoted.
  Non-object strings remain literal to exercise semantic/structural refusals. }
function Fixture(const Bytes: RawByteString): RawByteString;
var P, E, I: SizeInt; Line, Q: RawByteString;
begin
  Result := ''; P := 1;
  while P <= Length(Bytes) do
  begin
    E := P; while (E <= Length(Bytes)) and (Bytes[E] <> #10) do Inc(E);
    Line := Copy(Bytes,P,E-P);
    if Copy(Line,1,5) = 'Env={' then
    begin
      Q := 'Env="';
      for I := 5 to Length(Line) do
      begin
        if Line[I] in ['"', '\'] then Q += '\';
        Q += Line[I];
      end;
      Line := Q + '"';
    end;
    Result += Line; if E <= Length(Bytes) then Result += #10;
    P := E + 1;
  end;
end;
procedure TPrismSnapshotTests.Ready(const G, L: RawByteString; out S: TPrismSettingsSnapshot);
var R: TPrismAssessmentReason;
begin
  AssertEquals(Ord(psaReady), Ord(AssessPrismSettings(Fixture(H+G),Fixture(H+L),S,R)));
  AssertEquals(Ord(psrNone), Ord(R)); AssertFalse(S.AmbientEnvironmentVerified);
  AssertEquals('Exact global bytes', Fixture(H+G), S.GlobalDocument.Bytes);
  AssertEquals('Exact instance bytes', Fixture(H+L), S.InstanceDocument.Bytes);
end;
procedure TPrismSnapshotTests.Refuses(const G, L: RawByteString;
  Status: TPrismAssessmentStatus; Reason: TPrismAssessmentReason);
var S: TPrismSettingsSnapshot; R: TPrismAssessmentReason; F: TPrismPerformanceFlag;
  K: TPrismManagedKey; GB, LB: RawByteString;
begin
  Ready('EnableMangoHud=true'#10'Env={"SECRET":"prior"}'#10,
    'OverridePerformance=true'#10, S);
  GB := Fixture(G); LB := Fixture(L);
  AssertEquals(Ord(Status), Ord(AssessPrismSettings(GB,LB,S,R)));
  AssertEquals('Fixed sanitized reason', Ord(Reason), Ord(R));
  AssertEquals(Fixture(G), GB); AssertEquals(Fixture(L), LB);
  AssertEquals('', S.GlobalDocument.Bytes); AssertEquals('', S.InstanceDocument.Bytes);
  AssertEquals(0, S.GlobalDocument.GeneralInsertOffset);
  AssertEquals(0, S.InstanceDocument.GeneralInsertOffset);
  for K := Low(K) to High(K) do
  begin
    AssertFalse(S.GlobalDocument.Managed[K].Present);
    AssertFalse(S.InstanceDocument.Managed[K].Present);
    AssertEquals('', S.GlobalDocument.Managed[K].RawScalar);
    AssertEquals('', S.InstanceDocument.Managed[K].DecodedScalar);
  end;
  AssertFalse(S.PerformanceGate.Raw.Present); AssertFalse(S.PerformanceGate.Value);
  AssertFalse(S.EnvGate.Raw.Present); AssertFalse(S.EnvGate.Value);
  AssertFalse(S.CommandsGate.Raw.Present); AssertFalse(S.CommandsGate.Value);
  for F := Low(F) to High(F) do
  begin
    AssertFalse(S.Performance[F].Value); AssertEquals(Ord(pesDefault),Ord(S.Performance[F].Source));
    AssertFalse(S.Performance[F].GlobalRaw.Present); AssertFalse(S.Performance[F].InstanceRaw.Present);
  end;
  AssertEquals(0, Length(S.Env.Entries)); AssertFalse(S.Env.GlobalRaw.Present);
  AssertFalse(S.Env.InstanceRaw.Present); AssertEquals('', S.Wrapper.Value);
  AssertFalse(S.Wrapper.GlobalRaw.Present); AssertFalse(S.Wrapper.InstanceRaw.Present);
  AssertFalse(S.AmbientEnvironmentVerified);
end;
procedure TPrismSnapshotTests.DefaultsAndRawDocuments;
var S: TPrismSettingsSnapshot; F: TPrismPerformanceFlag;
begin
  Ready('; global'#10, '; instance'#10'[Other]'#10'keep = bytes'#10,S);
  for F := Low(F) to High(F) do
  begin AssertFalse(S.Performance[F].Value); AssertEquals(Ord(pesDefault),Ord(S.Performance[F].Source)); end;
  AssertEquals(0,Length(S.Env.Entries)); AssertEquals(Ord(pesDefault),Ord(S.Env.Source));
  AssertEquals('',S.Wrapper.Value); AssertEquals(Ord(pesDefault),Ord(S.Wrapper.Source));
end;
procedure TPrismSnapshotTests.AllPerformanceSources;
var S: TPrismSettingsSnapshot; F: TPrismPerformanceFlag; G,L: RawByteString;
begin
  G := ''; L := '';
  for F := Low(F) to High(F) do begin G += Names[F]+'=true'#10; L += Names[F]+'=false'#10; end;
  Ready(G,L,S);
  for F := Low(F) to High(F) do begin AssertTrue(S.Performance[F].Value); AssertEquals(Ord(pesGlobal),Ord(S.Performance[F].Source)); AssertEquals('false',S.Performance[F].InstanceRaw.DecodedScalar); end;
  Ready(G,'OverridePerformance=false'#10+L,S);
  for F := Low(F) to High(F) do begin AssertTrue(S.Performance[F].Value); AssertEquals(Ord(pesGlobal),Ord(S.Performance[F].Source)); end;
  Ready(G,'OverridePerformance=true'#10+L,S);
  for F := Low(F) to High(F) do begin AssertFalse(S.Performance[F].Value); AssertEquals(Ord(pesInstance),Ord(S.Performance[F].Source)); end;
  Ready(G,'OverridePerformance=true'#10,S);
  for F := Low(F) to High(F) do begin AssertTrue(S.Performance[F].Value); AssertEquals(Ord(pesGlobal),Ord(S.Performance[F].Source)); end;
  Ready('','OverridePerformance=true'#10,S);
  for F := Low(F) to High(F) do AssertEquals(Ord(pesDefault),Ord(S.Performance[F].Source));
end;
procedure TPrismSnapshotTests.DormantSemanticValues;
var S: TPrismSettingsSnapshot; F: TPrismPerformanceFlag; L: RawByteString;
begin
  L := 'OverridePerformance=false'#10'OverrideEnv=false'#10'Env=not JSON secret'#10;
  for F := Low(F) to High(F) do L += Names[F]+'=secret-invalid'#10;
  Ready('',L,S); AssertEquals('not JSON secret',S.Env.InstanceRaw.RawScalar);
  Ready('','EnableMangoHud='#10'Env='#10,S);
  AssertTrue(S.Env.InstanceRaw.Present); AssertEquals('',S.Env.InstanceRaw.RawScalar);
  Ready('','Env={"duplicate":"one","duplicate":"two"}'#10,S);
  Ready('EnableMangoHud=invalid'#10'Env=invalid'#10,
    'OverridePerformance=true'#10'EnableMangoHud=false'#10'OverrideEnv=true'#10'Env={}'#10,S);
  AssertFalse(S.Performance[ppfMangoHud].Value); AssertEquals(Ord(pesInstance),Ord(S.Env.Source));
end;
procedure TPrismSnapshotTests.SelectedSemanticValues;
var F: TPrismPerformanceFlag;
begin
  for F := Low(F) to High(F) do
  begin
    Refuses(H+Names[F]+'='#10,H,psaUnsupported,psrPerformanceValue);
    Refuses(H,H+'OverridePerformance=true'#10+Names[F]+'=0'#10,psaUnsupported,psrPerformanceValue);
    Refuses(H+Names[F]+'=1'#10,H+'OverridePerformance=true'#10,psaUnsupported,psrPerformanceValue);
  end;
  Refuses(H+'Env='#10,H,psaUnsupported,psrEnvValue);
  Refuses(H,H+'OverrideEnv=true'#10'Env={"secret":17}'#10,psaUnsupported,psrEnvValue);
  Refuses(H+'Env=invalid'#10,H+'OverrideEnv=true'#10,psaUnsupported,psrEnvValue);
end;
procedure TPrismSnapshotTests.GatesAndAliases;
var S: TPrismSettingsSnapshot;
begin
  Refuses(H,H+'OverridePerformance='#10,psaUnsupported,psrPerformanceGate);
  Refuses(H,H+'OverrideEnv=1'#10,psaUnsupported,psrEnvGate);
  Refuses(H,H+'OverrideCommands=0'#10,psaUnsupported,psrCommandsGate);
  Refuses(H,H+'OverrideLaunchCmd='#10,psaUnsupported,psrCommandsGate);
  Refuses(H,H+'OverrideCommands=false'#10'OverrideLaunchCmd=true'#10,psaUnsupported,psrCommandsAliases);
  Ready('OverrideCommands=invalid'#10'OverrideLaunchCmd=also-invalid'#10,
    'OverrideLaunchCmd=true'#10'WrapperCommand='#10,S);
  AssertEquals(Ord(pmkOverrideLaunchCmd),Ord(S.CommandsGate.Key)); AssertTrue(S.CommandsGate.Value);
  Ready('','OverrideCommands=false'#10,S); AssertEquals(Ord(pmkOverrideCommands),Ord(S.CommandsGate.Key));
  Ready('','OverridePerformance="true"'#10'EnableMangoHud="false"'#10,S);
  AssertTrue(S.PerformanceGate.Value); AssertFalse(S.Performance[ppfMangoHud].Value);
end;
procedure TPrismSnapshotTests.EnvSourcesAndExactValues;
var S: TPrismSettingsSnapshot; M: TPrismEnvMap; E: TPrismEnvError; V: RawByteString;
begin
  SetLength(M,2); M[0].Key := '保留'; M[0].Value := '日本語 😀'+#0#10;
  M[1].Key := 'KEEP'; M[1].Value := ' spaces "quote" \ ';
  AssertTrue(EncodePrismEnv(M,V,E));
  Ready('Env='+V+#10,'OverrideEnv=true'#10,S);
  AssertEquals(Ord(pesGlobal),Ord(S.Env.Source)); AssertEquals(2,Length(S.Env.Entries));
  AssertEquals(M[0].Value,S.Env.Entries[0].Value); AssertEquals(M[1].Value,S.Env.Entries[1].Value);
  Ready('Env='+V+#10,'OverrideEnv=true'#10'Env={}'#10,S);
  AssertEquals(0,Length(S.Env.Entries)); AssertEquals(Ord(pesInstance),Ord(S.Env.Source));
  Ready('','OverrideEnv=true'#10,S); AssertEquals(Ord(pesDefault),Ord(S.Env.Source));
end;
procedure TPrismSnapshotTests.EffectiveCollisions;
var S: TPrismSettingsSnapshot; Key: RawByteString; I: Integer; R: TPrismAssessmentReason;
begin
  for I := 0 to 1 do
  begin
    if I=0 then begin Key:='MANGOHUD_CONFIG'; R:=psrMangoHudConfig; end
    else begin Key:='MANGOHUD_CONFIGFILE'; R:=psrMangoHudSelector; end;
    Refuses(H+'Env={"'+Key+'":""}'#10,H,psaConflict,R);
    Refuses(H,H+'OverrideEnv=true'#10'Env={"'+Key+'":"/synthetic/same-selector"}'#10,psaConflict,R);
    Ready('','Env={"'+Key+'":"secret dormant"}'#10,S);
    AssertEquals(0,Length(S.Env.Entries)); AssertTrue(S.Env.InstanceRaw.Present);
    Ready('Env={"'+Key+'":"unused"}'#10,'OverrideEnv=true'#10'Env={}'#10,S);
  end;
  Refuses(H+'Env={"LD_PRELOAD":"secret","MANGOHUD_CONFIGFILE":"x","MANGOHUD_CONFIG":"y"}'#10,
    H+'WrapperCommand=secret-wrapper'#10,psaConflict,psrMangoHudConfig);
  Ready('Env={"mangohud_config":"case sensitive"}'#10,'',S);
end;
procedure TPrismSnapshotTests.EffectiveWrapperAndPreload;
var S: TPrismSettingsSnapshot;
begin
  Refuses(H+'WrapperCommand=opaque secret'#10,H,psaUnsupported,psrWrapperCommand);
  Refuses(H+'WrapperCommand=opaque'#10,H+'OverrideCommands=true'#10,psaUnsupported,psrWrapperCommand);
  Refuses(H,H+'OverrideLaunchCmd=true'#10'WrapperCommand=opaque'#10,psaUnsupported,psrWrapperCommand);
  Ready('','WrapperCommand=secret dormant'#10'Env={"LD_PRELOAD":"dormant"}'#10,S);
  AssertEquals('secret dormant',S.Wrapper.InstanceRaw.DecodedScalar);
  Ready('WrapperCommand=unused'#10'Env={"LD_PRELOAD":"unused"}'#10,
    'OverrideCommands=true'#10'WrapperCommand='#10'OverrideEnv=true'#10'Env={"LD_PRELOAD":""}'#10,S);
  AssertEquals(1,Length(S.Env.Entries)); AssertEquals('',S.Wrapper.Value);
  Refuses(H+'Env={"LD_PRELOAD":"libsecret.so"}'#10,H,psaUnsupported,psrPreload);
end;
procedure TPrismSnapshotTests.StructuralAndVersionGates;
begin
  Refuses('[General]'#10,H,psaUnsupported,psrGlobalDocument);
  Refuses(H,'[General]'#10'ConfigVersion=1.2'#10,psaUnsupported,psrInstanceDocument);
  Refuses(H,H+'OverrideEnv=false'#10'Env="unterminated'#10,psaUnsupported,psrInstanceDocument);
  Refuses(H+'Env='+#255+#10,H+'OverrideEnv=true'#10'Env={}'#10,psaUnsupported,psrGlobalDocument);
  Refuses(H,H+'EnableMangoHud=true'#10'EnableMangoHud=false'#10,psaUnsupported,psrInstanceDocument);
  Refuses(H+StringOfChar('x',PrismDocumentMaxBytes),H,psaUnsupported,psrGlobalDocument);
end;
initialization
  RegisterTest(TPrismSnapshotTests);
end.
