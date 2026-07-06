#!/usr/bin/env python3
"""PrivateLM terminal bridge — PTY over WebSocket on ws://127.0.0.1:7681

Auth: the first WebSocket message must equal the contents of
TOKEN_PATH, written by the app immediately before this script is
started. Connections that don't authenticate within AUTH_TIMEOUT
seconds, or send the wrong token, are closed before any shell is
spawned.
"""
import asyncio, hmac, os, pty, subprocess, sys, signal

try:
    import websockets
except ImportError:
    subprocess.check_call(
        [sys.executable, '-m', 'pip', 'install', 'websockets', '-q'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    import websockets

SHELL = '/data/data/com.termux/files/usr/bin/bash'
if not os.path.exists(SHELL):
    SHELL = '/bin/bash'
HOST  = '127.0.0.1'
PORT  = 7681
TOKEN_PATH = os.path.expanduser('~/.privatelm_bridge.token')
AUTH_TIMEOUT = 5

with open(TOKEN_PATH, 'r') as f:
    EXPECTED_TOKEN = f.read().strip()

async def handle(ws):
    try:
        first = await asyncio.wait_for(ws.recv(), timeout=AUTH_TIMEOUT)
    except Exception:
        await ws.close(code=4001, reason='auth timeout')
        return
    if not isinstance(first, str) or not hmac.compare_digest(first, EXPECTED_TOKEN):
        await ws.close(code=4001, reason='unauthorized')
        return

    master_fd, slave_fd = pty.openpty()
    env = os.environ.copy()
    env.update({'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'})

    proc = subprocess.Popen(
        [SHELL, '--login', '-i'],
        stdin=slave_fd, stdout=slave_fd, stderr=slave_fd,
        close_fds=True, env=env,
        preexec_fn=os.setsid,
    )
    os.close(slave_fd)
    loop = asyncio.get_event_loop()

    async def pty_to_ws():
        while True:
            try:
                data = await loop.run_in_executor(
                    None, lambda: os.read(master_fd, 4096))
                await ws.send(data.decode('utf-8', errors='replace'))
            except Exception:
                break

    async def ws_to_pty():
        try:
            async for msg in ws:
                os.write(master_fd, msg.encode() if isinstance(msg, str) else msg)
        except Exception:
            pass

    t1 = asyncio.create_task(pty_to_ws())
    t2 = asyncio.create_task(ws_to_pty())
    await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
    for t in (t1, t2):
        t.cancel()
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except Exception:
        pass
    try:
        os.close(master_fd)
    except Exception:
        pass

async def main():
    async with websockets.serve(handle, HOST, PORT):
        print(f'PrivateLM bridge ready on ws://{HOST}:{PORT}', flush=True)
        await asyncio.Future()

if __name__ == '__main__':
    asyncio.run(main())
