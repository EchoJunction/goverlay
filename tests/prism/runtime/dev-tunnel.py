#!/usr/bin/env python3
"""Fixed container-local browser endpoint; binary stdin/stdout only."""
import os
import select
import socket
import sys
from pathlib import Path
import time

if sys.argv[1:] == ['--count']:
    count = 0
    for process in Path('/proc').iterdir():
        if not process.name.isdecimal() or int(process.name) == os.getpid():
            continue
        try:
            if b'/dev-tools/dev-tunnel.py' in (process / 'cmdline').read_bytes().split(b'\0'):
                count += 1
        except (FileNotFoundError, PermissionError):
            pass
    print(count)
    raise SystemExit(0)
if len(sys.argv) != 1:
    raise SystemExit('Unsupported tunnel arguments')

with socket.create_connection(('127.0.0.1', 6080), timeout=5) as connection:
    connection.settimeout(5)
    reading = True; last = time.monotonic(); drain_until = None
    while True:
        now = time.monotonic()
        if now - last > 120 or (drain_until is not None and now > drain_until):
            break
        sources = [connection] + ([0] if reading else [])
        readable, _, _ = select.select(sources, [], [], .5)
        for source in readable:
            if source == 0:
                data = os.read(0, 65536)
                if not data:
                    connection.shutdown(socket.SHUT_WR); reading = False
                    drain_until = time.monotonic() + 5
                    continue
                connection.sendall(data)
            else:
                data = connection.recv(65536)
                if not data:
                    raise SystemExit(0)
                while data:
                    written = os.write(1, data)
                    if written <= 0:
                        raise SystemExit(1)
                    data = data[written:]
            last = time.monotonic()
