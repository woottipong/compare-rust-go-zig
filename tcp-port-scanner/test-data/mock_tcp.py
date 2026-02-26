#!/usr/bin/env python3
import socket
import threading

HOST = "0.0.0.0"
PORTS = [54000, 54002, 54004, 54006, 54008]


def serve(port: int):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, port))
    s.listen(64)
    while True:
        conn, _ = s.accept()
        conn.close()


def main():
    threads = []
    for p in PORTS:
        t = threading.Thread(target=serve, args=(p,), daemon=True)
        t.start()
        threads.append(t)
    print(f"mock tcp server listening on ports: {PORTS}")
    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
