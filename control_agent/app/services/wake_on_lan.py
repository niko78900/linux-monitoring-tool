from __future__ import annotations

import socket


def normalize_mac_address(raw_mac: str) -> str:
    normalized = raw_mac.replace("-", "").replace(":", "").strip().lower()
    if len(normalized) != 12 or any(char not in "0123456789abcdef" for char in normalized):
        raise ValueError("Invalid MAC address")
    return normalized


def build_magic_packet(mac_address: str) -> bytes:
    normalized = normalize_mac_address(mac_address)
    mac_bytes = bytes.fromhex(normalized)
    return b"\xff" * 6 + mac_bytes * 16


def send_magic_packet(mac_address: str, broadcast_host: str, port: int) -> None:
    packet = build_magic_packet(mac_address)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(packet, (broadcast_host, port))
