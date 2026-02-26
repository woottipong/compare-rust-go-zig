#!/usr/bin/env python3
import socket

HOST = "0.0.0.0"
PORT = 56000


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((HOST, PORT))
    print(f"mock udp ping server listening on {HOST}:{PORT}")
    while True:
        data, addr = sock.recvfrom(2048)
        if data == b"PING":
            sock.sendto(b"PONG", addr)


if __name__ == "__main__":
    main()
