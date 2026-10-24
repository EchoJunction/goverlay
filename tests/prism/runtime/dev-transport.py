#!/usr/bin/env python3
"""Loopback-only noVNC HTTP/WebSocket transport probe; no password access."""
import base64
import hashlib
import os
import socket
import sys
import urllib.request

def require(condition, message='Development verification failed'):
    if not condition:
        raise SystemExit(message)

port = int(sys.argv[1])
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
with opener.open(f'http://127.0.0.1:{port}/vnc.html', timeout=5) as response:
    require(response.status == 200 and b'noVNC' in response.read())
key = base64.b64encode(os.urandom(16)).decode()
with socket.create_connection(('127.0.0.1', port), timeout=5) as connection:
    connection.sendall((f'GET /websockify HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n'
        'Upgrade: websocket\r\nConnection: Upgrade\r\n'
        f'Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
    received = b''
    while b'\r\n\r\n' not in received:
        chunk = connection.recv(4096)
        require(bool(chunk), 'WebSocket closed before complete headers')
        received += chunk
        require(len(received) <= 65536, 'Oversized WebSocket headers')
    headers, frame = received.split(b'\r\n\r\n', 1)
    accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
    require(b'101 Switching Protocols' in headers and accept in headers)
    stream = b''

    def rfb_bytes(count):
        global frame, stream
        while len(stream) < count:
            while len(frame) < 2:
                chunk = connection.recv(4096)
                require(bool(chunk), 'WebSocket closed before RFB data')
                frame += chunk
            opcode = frame[0] & 15
            require(not (frame[1] & 128), 'Unexpected masked server frame')
            length = frame[1] & 127; header = 2
            if length == 126:
                header = 4
            elif length == 127:
                header = 10
            while len(frame) < header:
                chunk = connection.recv(4096)
                require(bool(chunk), 'Incomplete frame header')
                frame += chunk
            if header > 2:
                length = int.from_bytes(frame[2:header], 'big')
            require(length <= 1024 * 1024, 'Oversized server frame')
            while len(frame) < header + length:
                chunk = connection.recv(4096)
                require(bool(chunk), 'Incomplete server frame')
                frame += chunk
            require(opcode == 2, 'Expected binary RFB frame')
            stream += frame[header:header + length]
            frame = frame[header + length:]
        result, stream = stream[:count], stream[count:]
        return result

    def send_rfb(data):
        require(len(data) < 126)
        mask = os.urandom(4)
        connection.sendall(bytes([0x82, 0x80 | len(data)]) + mask +
            bytes(value ^ mask[index % 4] for index, value in enumerate(data)))

    greeting = rfb_bytes(12)
    require(greeting == b'RFB 003.008\n', 'Unexpected RFB protocol')
    send_rfb(greeting)
    security_count = rfb_bytes(1)[0]
    require(security_count > 0, 'RFB security negotiation failed')
    security_types = rfb_bytes(security_count)
    require(2 in security_types and 1 not in security_types, 'VNC password authentication is not required')
    send_rfb(b'\x02')
    require(len(rfb_bytes(16)) == 16, 'Missing VNC authentication challenge')
print('PASS: loopback noVNC HTTP200 + WebSocket101 + RFB3.8; VNC password challenge required, None auth absent')
