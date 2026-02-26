#!/usr/bin/env python3
import socket
import struct

HOST = "0.0.0.0"
PORT = 53535


def build_response(query: bytes) -> bytes:
    if len(query) < 12:
        return b""
    tid = query[0:2]
    flags = b"\x81\x80"
    qdcount = b"\x00\x01"
    ancount = b"\x00\x01"
    nscount = b"\x00\x00"
    arcount = b"\x00\x00"

    i = 12
    while i < len(query) and query[i] != 0:
        i += query[i] + 1
    i += 1
    question = query[12 : i + 4]

    answer = b"\xc0\x0c" + b"\x00\x01" + b"\x00\x01" + struct.pack("!I", 60) + b"\x00\x04" + socket.inet_aton("93.184.216.34")

    return tid + flags + qdcount + ancount + nscount + arcount + question + answer


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((HOST, PORT))
    print(f"mock dns server listening on {HOST}:{PORT}")
    while True:
        data, addr = sock.recvfrom(512)
        resp = build_response(data)
        if resp:
            sock.sendto(resp, addr)


if __name__ == "__main__":
    main()
