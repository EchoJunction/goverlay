unit prismselectedreader;
{$mode objfpc}{$H+}
interface
uses prismprovider;
const PrismSelectedMetadataBudget=16*1024*1024;
type
  TPrismSelectedReadReason=(psrrNone,psrrInvalidSelection,psrrReadUnavailable,
    psrrUnsafeRead,psrrLimit,psrrObservedChange,psrrInvalidMetadata,
    psrrIdentityChanged,psrrAmbiguousIdentity);
  TPrismSelectedDocuments=record
    Current:TPrismInstance;
    GlobalBytes,InstanceBytes:RawByteString;
  end;
{ Shared adapter-internal pinned selected-root/catalog read. Raw documents are
  ephemeral inputs to pure planners, never a UI DTO or write authority. Same
  depth, file, entry and16MiB aggregate bounds as the original enable preview;
  identity/UUID/catalog metadata rechecks remain fail-closed. Advisory only,
  not a coherent-live snapshot/CAS guarantee. Failure clears documents. }
function ReadSelectedPrismDocuments(const Selected:TPrismInstance;
  const HostDataDir:string; out Documents:TPrismSelectedDocuments;
  out Reason:TPrismSelectedReadReason):Boolean;
implementation
uses Classes,SysUtils,SHA1,gamecontext,prismreadonly,prismdocument;
function ReadSelectedPrismDocuments(const Selected:TPrismInstance;
  const HostDataDir:string; out Documents:TPrismSelectedDocuments;
  out Reason:TPrismSelectedReadReason):Boolean;
var Current:TPrismInstance; Context:TActiveProfileContext;
  Global,Raw,Local:RawByteString; C,InstanceRoot,EntryPath,Expected,UUID,Identity:string;
  Names:TPrismEntryNames; Stamps:array of TPrismNodeStamp;
  Stamp:TPrismNodeStamp; RE:TPrismReadError; ME:TPrismMetadataError;
  Settings:TStringList;
  I,N,BytesRead,Matches,Found:SizeInt;
  procedure Keep(const S:TPrismNodeStamp);
  begin N:=Length(Stamps); SetLength(Stamps,N+1); Stamps[N]:=S; end;
  function FailRead:Boolean;
  begin
    case RE of
      preUnavailable:Reason:=psrrReadUnavailable;
      preUnsafe,preInvalidPath:Reason:=psrrUnsafeRead;
      preLimit:Reason:=psrrLimit;
      preChanged:Reason:=psrrObservedChange;
      else Reason:=psrrUnsafeRead;
    end;
    FailRead:=False;
  end;
  function ReadMetadata(const Path:string; out Bytes:RawByteString):Boolean;
  var Allowed:SizeInt;
  begin
    ReadMetadata:=False;
    Allowed:=PrismSelectedMetadataBudget-BytesRead;
    if Allowed<=0 then begin Reason:=psrrLimit; Exit; end;
    if Allowed>PrismDocumentMaxBytes then Allowed:=PrismDocumentMaxBytes;
    if not ReadPrismFile(Path,Allowed,Bytes,Stamp,RE) then
    begin FailRead; Exit; end;
    Inc(BytesRead,Length(Bytes));
    if BytesRead>PrismSelectedMetadataBudget then begin Reason:=psrrLimit; Exit; end;
    Keep(Stamp); Settings.Clear;
    if not ParsePrismMetadata(Bytes,Settings,ME) then
    begin Reason:=psrrInvalidMetadata; Exit; end;
    ReadMetadata:=True;
  end;
begin
  Result:=False; Documents:=Default(TPrismSelectedDocuments);
  Reason:=psrrInvalidSelection;
  Settings:=nil;
  try
   try
    if not CanonicalPrismPath(Selected.DataRoot,C,False) or (C<>Selected.DataRoot) or
      not CanonicalPrismPath(Selected.ConfigPath,C,False) or (C<>Selected.ConfigPath) or
      not CanonicalPrismPath(HostDataDir,C,False) or (C<>HostDataDir) or
      not PrismProfileContext(Selected,HostDataDir,Context) or
      (Selected.Folder='') or (Selected.Folder='.') or (Selected.Folder='..') or
      (Pos('/',Selected.Folder)>0) or (Pos(#0,Selected.Folder)>0) then Exit;
    Settings:=TStringList.Create; Settings.CaseSensitive:=True;
    BytesRead:=0; Matches:=0; Found:=0; Stamps:=nil;
    if not ReadMetadata(IncludeTrailingPathDelimiter(Selected.DataRoot)+'prismlauncher.cfg',Global) then Exit;
    InstanceRoot:=Settings.Values['InstanceDir']; if InstanceRoot='' then InstanceRoot:='instances';
    if InstanceRoot[1]<>'/' then InstanceRoot:=IncludeTrailingPathDelimiter(Selected.DataRoot)+InstanceRoot;
    if not CanonicalPrismPath(InstanceRoot,C,False) then begin Reason:=psrrInvalidMetadata; Exit; end;
    InstanceRoot:=C; Expected:=IncludeTrailingPathDelimiter(InstanceRoot)+Selected.Folder+'/instance.cfg';
    if Expected<>Selected.ConfigPath then begin Reason:=psrrIdentityChanged; Exit; end;
    if not ListPrismDirectory(InstanceRoot,PrismMaxEntries,Names,Stamp,RE) then begin FailRead; Exit; end;
    Keep(Stamp);
    for I:=0 to High(Names) do
    begin
      EntryPath:=IncludeTrailingPathDelimiter(InstanceRoot)+Names[I];
      if not InspectPrismNode(EntryPath,Stamp,RE) then begin FailRead; Exit; end;
      Keep(Stamp); if Stamp.Kind<>pnDirectory then Continue;
      if not ReadMetadata(EntryPath+'/instance.cfg',Raw) then Exit;
      if Settings.Values['InstanceType']<>'OneSix' then Continue;
      UUID:=LowerCase(Settings.Values['uuid']);
      if UUID<>'' then
      begin
        if Length(UUID)<>32 then begin Reason:=psrrInvalidMetadata; Exit; end;
        for N:=1 to Length(UUID) do if not (UUID[N] in ['0'..'9','a'..'f']) then
        begin Reason:=psrrInvalidMetadata; Exit; end;
        if UUID=Selected.UUID then Inc(Matches);
      end;
      if EntryPath+'/instance.cfg'=Expected then
      begin
        Inc(Found); Current:=Selected; Current.UUID:=UUID; Current.UsesFolderIdentity:=UUID='';
        Current.InstallationKey:='prism-root-'+SHA1Print(SHA1String(Selected.DataRoot));
        if UUID='' then Identity:='folder:'+EntryPath else Identity:='uuid:'+UUID;
        Current.StableKey:='prism-'+SHA1Print(SHA1String(Selected.DataRoot+#0+Identity));
        Local:=Raw;
      end;
    end;
    Reason:=psrrIdentityChanged;
    if (Found<>1) or (Current.UUID<>Selected.UUID) or
      (Current.UsesFolderIdentity<>Selected.UsesFolderIdentity) or
      (Current.StableKey<>Selected.StableKey) or (Current.InstallationKey<>Selected.InstallationKey) then Exit;
    if (Current.UUID<>'') and (Matches<>1) then begin Reason:=psrrAmbiguousIdentity; Exit; end;
    for I:=0 to High(Stamps) do
      if not RecheckPrismNode(Stamps[I],RE) then begin FailRead; Exit; end;
    Documents.Current:=Current; Documents.GlobalBytes:=Global;
    Documents.InstanceBytes:=Local; Reason:=psrrNone; Result:=True;
  except
    Documents:=Default(TPrismSelectedDocuments); Reason:=psrrUnsafeRead;
    Result:=False;
  end;
  finally Settings.Free; end;
end;
end.
