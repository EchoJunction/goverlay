unit prismreadonly;
{$mode objfpc}{$H+}
interface
uses BaseUnix;
const PrismReadMaxDepth=128;
type
  TPrismReadError=(preNone,preInvalidPath,preUnavailable,preUnsafe,preLimit,preChanged,preIO);
  TPrismNodeKind=(pnFile,pnDirectory);
  TPrismNodeStamp=record
    Path:string;
    Kind:TPrismNodeKind;
    Info:Stat;
    Ancestors:array of Stat;
  end;
  TPrismEntryNames=array of string;
{ Linux descriptor-pinned advisory reads only. No creates/writes/logging.
  Paths are canonical absolute lexical spellings. Each ancestor and final node
  opens via openat+NOFOLLOW; nonblocking regular files only. Reopen/path identity
  and metadata checks reject observed changes, not every possible live race. }
function ReadPrismFile(const Path:string; MaxBytes:SizeInt; out Bytes:RawByteString;
  out Stamp:TPrismNodeStamp; out Error:TPrismReadError):Boolean;
function InspectPrismNode(const Path:string; out Stamp:TPrismNodeStamp;
  out Error:TPrismReadError):Boolean;
function RecheckPrismNode(const Stamp:TPrismNodeStamp; out Error:TPrismReadError):Boolean;
function ListPrismDirectory(const Path:string; MaxEntries:SizeInt; out Names:TPrismEntryNames;
  out Stamp:TPrismNodeStamp; out Error:TPrismReadError):Boolean;
{$ifdef PRISM_PREVIEW_TESTS}
type TPrismReadTestHook=procedure(const Path:string);
var PrismReadAfterReadHook:TPrismReadTestHook=nil;
{$endif}
implementation
uses SysUtils,Linux,prismprovider;
{$push}{$packrecords c}
type
  TLibcDirent64=record
    Inode:QWord; Offset:Int64; RecordLength:Word; NodeType:Byte;
    Name:array[0..255] of Char;
  end;
  PLibcDirent64=^TLibcDirent64;
{$pop}
function c_openat(Fd:cint; Path:PChar; Flags:cint; Mode:mode_t):cint;cdecl;external 'c' name 'openat';
function c_fdopendir(Fd:cint):Pointer;cdecl;external 'c' name 'fdopendir';
function c_readdir64(Dir:Pointer):PLibcDirent64;cdecl;external 'c' name 'readdir64';
function c_closedir(Dir:Pointer):cint;cdecl;external 'c' name 'closedir';
function c_errno:Pcint;cdecl;external 'c' name '__errno_location';
type TDescriptors=array of cint;
procedure CloseAll(var Fds:TDescriptors);
var I:SizeInt;
begin for I:=High(Fds) downto 0 do fpClose(Fds[I]); Fds:=nil; end;
function SameNode(const A,B:Stat):Boolean;
begin Result:=(A.st_dev=B.st_dev) and (A.st_ino=B.st_ino) and (A.st_mode=B.st_mode); end;
function SameContent(const A,B:Stat):Boolean;
begin
  Result:=SameNode(A,B) and (A.st_nlink=B.st_nlink) and (A.st_size=B.st_size) and
    (A.st_mtime=B.st_mtime) and (A.st_mtime_nsec=B.st_mtime_nsec) and
    (A.st_ctime=B.st_ctime) and (A.st_ctime_nsec=B.st_ctime_nsec);
end;
function OpenPinned(const Path:string; out Fds:TDescriptors;
  out Stamp:TPrismNodeStamp; out Error:TPrismReadError):Boolean;
var C,Part:string; P,E,N:SizeInt; F,Flags:cint; Info:Stat;
  procedure Add(Fd:cint);
  begin N:=Length(Fds); SetLength(Fds,N+1); Fds[N]:=Fd; end;
begin
  Result:=False; Fds:=nil; Stamp:=Default(TPrismNodeStamp); Error:=preInvalidPath;
  if not CanonicalPrismPath(Path,C,False) or (C<>Path) then Exit;
  Error:=preIO; F:=fpOpen(PChar('/'),O_RDONLY or O_DIRECTORY or O_CLOEXEC or O_NOFOLLOW);
  if F<0 then Exit; Add(F); P:=2;
  try
    while P<=Length(Path) do
    begin
      if Length(Fds)>=PrismReadMaxDepth then begin Error:=preLimit; Exit; end;
      E:=P; while (E<=Length(Path)) and (Path[E]<>'/') do Inc(E);
      Part:=Copy(Path,P,E-P); Flags:=O_RDONLY or O_CLOEXEC or O_NOFOLLOW or O_NONBLOCK;
      if E<=Length(Path) then Flags:=Flags or O_DIRECTORY;
      F:=c_openat(Fds[High(Fds)],PChar(Part),Flags,0);
      if F<0 then
      begin
        case c_errno^ of ESysENOENT:Error:=preUnavailable; ESysELOOP:Error:=preUnsafe;
          ESysENOTDIR:Error:=preUnsafe; else Error:=preIO; end;
        Exit;
      end;
      Add(F); P:=E+1;
    end;
    if fpFStat(Fds[High(Fds)],Info)<>0 then Exit;
    if FPS_ISREG(Info.st_mode) then Stamp.Kind:=pnFile
    else if FPS_ISDIR(Info.st_mode) then Stamp.Kind:=pnDirectory
    else begin Error:=preUnsafe; Exit; end;
    Stamp.Path:=Path; Stamp.Info:=Info; SetLength(Stamp.Ancestors,Length(Fds)-1);
    for P:=0 to High(Stamp.Ancestors) do
      if fpFStat(Fds[P],Stamp.Ancestors[P])<>0 then Exit;
    Error:=preNone; Result:=True;
  finally
    if not Result then begin CloseAll(Fds); Stamp:=Default(TPrismNodeStamp); end;
  end;
end;
function SameStamp(const A,B:TPrismNodeStamp):Boolean;
var I:SizeInt;
begin
  Result:=False;
  if (A.Path<>B.Path) or (A.Kind<>B.Kind) or not SameContent(A.Info,B.Info) or
    (Length(A.Ancestors)<>Length(B.Ancestors)) then Exit;
  for I:=0 to High(A.Ancestors) do if not SameNode(A.Ancestors[I],B.Ancestors[I]) then Exit;
  Result:=True;
end;
function InspectPrismNode(const Path:string; out Stamp:TPrismNodeStamp;
  out Error:TPrismReadError):Boolean;
var Fds:TDescriptors;
begin
  Result:=OpenPinned(Path,Fds,Stamp,Error);
  if Result then CloseAll(Fds);
end;
function RecheckPrismNode(const Stamp:TPrismNodeStamp; out Error:TPrismReadError):Boolean;
var Fresh:TPrismNodeStamp;
begin
  Result:=InspectPrismNode(Stamp.Path,Fresh,Error);
  if not Result then begin Error:=preChanged; Exit; end;
  Result:=SameStamp(Stamp,Fresh); if not Result then Error:=preChanged;
end;
function ReadPrismFile(const Path:string; MaxBytes:SizeInt; out Bytes:RawByteString;
  out Stamp:TPrismNodeStamp; out Error:TPrismReadError):Boolean;
var Fds:TDescriptors; Before:TPrismNodeStamp; After:Stat;
  Buffer:RawByteString; Got,Used,Retries:SizeInt;
begin
  Result:=False; Bytes:=''; Stamp:=Default(TPrismNodeStamp); Error:=preLimit;
  if (MaxBytes<0) or (MaxBytes>PrismMaxFileBytes) then Exit;
  if not OpenPinned(Path,Fds,Before,Error) then Exit;
  try
    if Before.Kind<>pnFile then begin Error:=preUnsafe; Exit; end;
    if (Before.Info.st_size<0) or (Before.Info.st_size>MaxBytes) then begin Error:=preLimit; Exit; end;
    SetLength(Buffer,Before.Info.st_size+1); Used:=0; Retries:=0;
    while Used<Length(Buffer) do
    begin
      Got:=fpRead(Fds[High(Fds)],Buffer[Used+1],Length(Buffer)-Used);
      if Got<0 then
      begin
        if (fpGetErrNo=ESysEINTR) and (Retries<8) then begin Inc(Retries); Continue; end;
        Error:=preIO; Exit;
      end;
      if Got=0 then Break; Inc(Used,Got);
    end;
    {$ifdef PRISM_PREVIEW_TESTS}
    if Assigned(PrismReadAfterReadHook) then PrismReadAfterReadHook(Path);
    {$endif}
    Error:=preChanged;
    if (Used<>Before.Info.st_size) or (fpFStat(Fds[High(Fds)],After)<>0) or
      not SameContent(Before.Info,After) then Exit;
    if not RecheckPrismNode(Before,Error) then Exit;
    SetLength(Buffer,Used); Bytes:=Buffer; Stamp:=Before; Error:=preNone; Result:=True;
  finally
    CloseAll(Fds);
  end;
end;
function ListPrismDirectory(const Path:string; MaxEntries:SizeInt; out Names:TPrismEntryNames;
  out Stamp:TPrismNodeStamp; out Error:TPrismReadError):Boolean;
var Fds:TDescriptors; Before:TPrismNodeStamp; Dir:Pointer;
  Entry:PLibcDirent64; F:cint; Name:string; N,L:SizeInt; Candidate:TPrismEntryNames;
begin
  Result:=False; Names:=nil; Candidate:=nil; Stamp:=Default(TPrismNodeStamp); Error:=preLimit;
  if (MaxEntries<0) or (MaxEntries>PrismMaxEntries) then Exit;
  if not OpenPinned(Path,Fds,Before,Error) then Exit;
  Dir:=nil;
  try
    if Before.Kind<>pnDirectory then begin Error:=preUnsafe; Exit; end;
    F:=c_openat(Fds[High(Fds)],'.',O_RDONLY or O_DIRECTORY or O_NOFOLLOW or O_CLOEXEC,0);
    if F<0 then begin Error:=preIO; Exit; end;
    Dir:=c_fdopendir(F);
    if Dir=nil then begin fpClose(F); Error:=preIO; Exit; end;
    while True do
    begin
      c_errno^:=0; Entry:=c_readdir64(Dir);
      if Entry=nil then
      begin if c_errno^<>0 then begin Error:=preIO; Exit; end; Break; end;
      L:=0; while (L<=High(Entry^.Name)) and (Entry^.Name[L]<>#0) do Inc(L);
      if (L>High(Entry^.Name)) or (Entry^.RecordLength<19+L+1) then begin Error:=preUnsafe; Exit; end;
      SetString(Name,PChar(@Entry^.Name[0]),L);
      if (Name='.') or (Name='..') then Continue;
      N:=Length(Candidate); if N>=MaxEntries then begin Error:=preLimit; Exit; end;
      SetLength(Candidate,N+1); Candidate[N]:=Name;
    end;
    if not RecheckPrismNode(Before,Error) then Exit;
    Names:=Candidate; Stamp:=Before; Error:=preNone; Result:=True;
  finally
    if Dir<>nil then c_closedir(Dir);
    CloseAll(Fds);
  end;
end;
end.
