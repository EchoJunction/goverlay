#!/usr/bin/env python3
"""Inspect the actual dev GUI process without exporting its environment/logs."""
import ctypes
import hashlib
import os
from pathlib import Path
import pwd
import socket
import sys

def require(condition, message='Development verification failed'):
    if not condition:
        raise SystemExit(message)

require(os.getuid() == 1000 and pwd.getpwuid(1000).pw_dir == '/home/tester')
require(os.environ['HOME'] == '/home/tester')
host_home = Path(sys.argv[1])
if host_home != Path('/home/tester'):
    require(not host_home.exists(), 'Host HOME unexpectedly visible')
try:
    with open('/source/Makefile', 'r+b'):
        raise AssertionError('Source is writable')
except OSError as error:
    require(error.errno in (13, 30), error)
for variable in ('HOST_XDG_CONFIG_HOME', 'HOST_XDG_DATA_HOME'):
    require(not os.environ.get(variable), 'Host XDG override unexpectedly set')
for line in Path('/proc/net/route').read_text().splitlines()[1:]:
    require(line.split()[1] != '00000000', 'Unexpected IPv4 default route')
for line in Path('/proc/net/ipv6_route').read_text().splitlines():
    fields = line.split()
    require(not (fields[0] == '0' * 32 and fields[1] == '00' and fields[-1] != 'lo'), 'Unexpected IPv6 default route')
try:
    with socket.create_connection(('1.1.1.1', 443), timeout=2):
        raise AssertionError('Unexpected Internet egress')
except OSError:
    pass
pids = []
for candidate in Path('/proc').iterdir():
    if candidate.name.isdecimal():
        try:
            if (candidate / 'comm').read_text().strip() == 'goverlay':
                pids.append(candidate)
        except (FileNotFoundError, PermissionError):
            pass
require(len(pids) == 1, 'Expected one actual built GOverlay process')
process = pids[0]
require((process / 'cwd').resolve() == Path('/build/source'))
expected = Path('/build/binary.sha256').read_text().split()[0]
require(hashlib.sha256((process / 'exe').read_bytes()).hexdigest() == expected)
status = dict(line.split(':', 1) for line in (process / 'status').read_text().splitlines() if ':' in line)
require(int(status['CapEff'].strip(), 16) == 0)
require(status['NoNewPrivs'].strip() == '1')
env = (process / 'environ').read_bytes().split(b'\0')
require(b'GOVERLAY_TEST=1' not in env, 'Actual launcher unexpectedly in test mode')

# Confirm a visible named X window on the container Xvfb, independently of the
# offscreen production-form probes. No host X/Wayland socket is used.
x = ctypes.CDLL('libX11.so.6')
x.XOpenDisplay.argtypes = [ctypes.c_char_p]; x.XOpenDisplay.restype = ctypes.c_void_p
x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]; x.XDefaultRootWindow.restype = ctypes.c_ulong
x.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_char_p)]
x.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
    ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)), ctypes.POINTER(ctypes.c_uint)]
x.XFree.argtypes = [ctypes.c_void_p]
x.XCloseDisplay.argtypes = [ctypes.c_void_p]
display = x.XOpenDisplay(os.environ['DISPLAY'].encode())
require(display, 'Cannot inspect dev X display')
queue = [x.XDefaultRootWindow(display)]; found = False
for _ in range(1000):
    if not queue:
        break
    window = queue.pop(); name = ctypes.c_char_p()
    if x.XFetchName(display, window, ctypes.byref(name)) and name.value:
        found |= b'goverlay' in name.value.lower()
        x.XFree(name)
    root = ctypes.c_ulong(); parent = ctypes.c_ulong()
    children = ctypes.POINTER(ctypes.c_ulong)(); count = ctypes.c_uint()
    if x.XQueryTree(display, window, ctypes.byref(root), ctypes.byref(parent), ctypes.byref(children), ctypes.byref(count)):
        queue.extend(children[i] for i in range(count.value))
        if children:
            x.XFree(children)
x.XCloseDisplay(display)
require(found, 'Actual GOverlay window not found')
print('PASS: actual built binary alive/window present; hash matches manifest; UID1000, CapEff0, NoNewPrivs1')
print('PASS: source write denied, host HOME absent, host XDG overrides absent; no default route or direct Internet egress')
