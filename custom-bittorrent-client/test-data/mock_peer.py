#!/usr/bin/env python3
import socket

HOST = "0.0.0.0"
PORT = 6881
HANDSHAKE_LEN = 68
PROTOCOL = b"BitTorrent protocol"


def handle_client(conn: socket.socket) -> None:
    with conn:
        data = b""
        while len(data) < HANDSHAKE_LEN:
            chunk = conn.recv(HANDSHAKE_LEN - len(data))
            if not chunk:
                return
            data += chunk

        if len(data) != HANDSHAKE_LEN:
            return

        if data[0] != len(PROTOCOL) or data[1:20] != PROTOCOL:
            return

        conn.sendall(data)


def main() -> None:
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(256)

    while True:
        conn, _ = server.accept()
        handle_client(conn)


if __name__ == "__main__":
    main()
