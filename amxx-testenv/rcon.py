#!/usr/bin/env python3
"""GoldSrc rcon client: rcon.py [--host H] [--port P] [--password PW] <command...>

Prints the server's reply (the redirected console output). Run with `python3 -I`.
"""
import argparse
import socket
import sys

HDR = b"\xff\xff\xff\xff"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=27315)
    ap.add_argument("--password", default="amxxtest")
    ap.add_argument("--timeout", type=float, default=1.5)
    ap.add_argument("command", nargs="+")
    a = ap.parse_args()
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(5)
    addr = (a.host, a.port)
    s.sendto(HDR + b"challenge rcon\n", addr)
    reply = s.recv(4096)
    parts = reply[4:].split()
    if len(parts) < 3 or parts[0] != b"challenge" or parts[1] != b"rcon":
        print(f"unexpected challenge reply: {reply!r}", file=sys.stderr)
        return 1
    cmd = " ".join(a.command)
    s.sendto(HDR + b"rcon " + parts[2] + b' "' + a.password.encode() + b'" ' + cmd.encode() + b"\n", addr)
    s.settimeout(a.timeout)
    out = []
    try:
        while True:
            pkt = s.recv(65536)
            if pkt.startswith(HDR):
                pkt = pkt[5:] if pkt[4:5] == b"l" else pkt[4:]
            out.append(pkt.rstrip(b"\0").decode("utf-8", "replace"))
    except socket.timeout:
        pass
    sys.stdout.write("".join(out))
    return 0 if out else 2


if __name__ == "__main__":
    sys.exit(main())
