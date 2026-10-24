#!/usr/bin/env python3
"""Private loopback browser relay over Podman exec stdio; never logs payloads."""
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import socketserver
import subprocess
import sys
import threading
import time

def require(condition, message='Development verification failed'):
    if not condition:
        raise SystemExit(message)

script = Path(__file__).resolve()
action, raw_state = sys.argv[1:3]
state = Path(raw_state)
require(state.is_absolute() and state.resolve() == state and not state.is_symlink())
require(state.name.startswith('goverlay-prism-runtime.'))
require(state.stat().st_uid == os.getuid() and state.stat().st_mode & 0o777 == 0o700)
require(not (state / 'marker').is_symlink())
require((state / 'marker').read_text() == 'GOverlay disposable Prism engine v1\n')
metadata = state / 'dev-relay.json'
require(not metadata.is_symlink())

def starttime(pid):
    return Path(f'/proc/{pid}/stat').read_text().rpartition(')')[2].split()[19]

def argv(pid):
    return Path(f'/proc/{pid}/cmdline').read_bytes().rstrip(b'\0').split(b'\0')

if action == 'stop':
    if not metadata.exists():
        raise SystemExit(0)
    require(metadata.stat().st_uid == os.getuid() and metadata.stat().st_mode & 0o777 == 0o600)
    saved = json.loads(metadata.read_text()); pid = saved['pid']
    try:
        pidfd = os.pidfd_open(pid)
    except ProcessLookupError:
        metadata.unlink(); raise SystemExit(0)
    try:
        require(Path(f'/proc/{pid}').stat().st_uid == os.getuid())
        require(starttime(pid) == saved['starttime'])
        require(argv(pid) == [s.encode() for s in saved['argv']])
        require(argv(pid)[1:4] == [str(script).encode(), b'serve', str(state).encode()])
        signal.pidfd_send_signal(pidfd, signal.SIGTERM)
        require(select.select([pidfd], [], [], 12)[0], 'Relay did not finish cleanup')
    finally:
        os.close(pidfd)
    if metadata.exists():
        metadata.unlink()
    print('Dev loopback relay and its client exec processes stopped')
    raise SystemExit(0)

require(action == 'serve')
cid, raw_port = sys.argv[3:5]
require(re.fullmatch('[0-9a-f]{12,64}', cid))
port = int(raw_port)
require(1024 <= port <= 65535)
wrapper = state / 'dev-podman'
require(wrapper.is_absolute() and wrapper.is_file() and not wrapper.is_symlink())
require(wrapper.stat().st_uid == os.getuid())
require(not metadata.exists(), 'Existing relay metadata; stop it first')
stopping = threading.Event()
gate = threading.BoundedSemaphore(8)

def request_stop(_signum, _frame):
    stopping.set()

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        if not gate.acquire(blocking=False):
            return
        process = None
        self.request.settimeout(5)
        try:
            process = subprocess.Popen([str(wrapper), 'exec', '-i', cid,
                'python', '/dev-tools/dev-tunnel.py'], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
            os.set_blocking(process.stdin.fileno(), False)
            pending = b''
            last = time.monotonic(); reading = True; drain_until = None
            while not stopping.is_set():
                now = time.monotonic()
                if now - last > 120 or (drain_until is not None and now > drain_until):
                    break
                sources = [process.stdout] + ([self.request] if reading and not pending else [])
                readable, writable, _ = select.select(sources, [process.stdin] if pending else [], [], .5)
                if writable:
                    sent = os.write(process.stdin.fileno(), pending)
                    pending = pending[sent:]
                    last = time.monotonic()
                for source in readable:
                    if source is self.request:
                        data = self.request.recv(65536)
                        if not data:
                            process.stdin.close(); reading = False
                            drain_until = time.monotonic() + 5
                            continue
                        pending = data
                    else:
                        data = os.read(process.stdout.fileno(), 65536)
                        if not data:
                            self.request.shutdown(socket.SHUT_WR)
                            return
                        self.request.sendall(data)
                    last = time.monotonic()
        except (OSError, ValueError):
            # Browser disconnects and failed execs contain no diagnostic payload.
            pass
        finally:
            if process is not None:
                if not process.stdin.closed:
                    process.stdin.close()
                process.stdout.close()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        process.kill(); process.wait()
            gate.release()

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = False
    request_queue_size = 8

signal.signal(signal.SIGTERM, request_stop)
signal.signal(signal.SIGINT, request_stop)
# Binding failure leaves any existing listener/process untouched.
with Server(('127.0.0.1', port), Handler) as server:
    server.timeout = .2
    with os.fdopen(os.open(metadata, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as target:
        json.dump({'pid': os.getpid(), 'starttime': starttime(os.getpid()),
            'argv': [s.decode() for s in argv(os.getpid())], 'cid': cid, 'port': port}, target)
    print('Dev browser relay ready on 127.0.0.1 only', flush=True)
    try:
        while not stopping.is_set():
            server.handle_request()
    finally:
        stopping.set()
# server_close waits for handlers; each closes/reaps its exec process first.
if metadata.exists() and json.loads(metadata.read_text())['pid'] == os.getpid():
    metadata.unlink()
