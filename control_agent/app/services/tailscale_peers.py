from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class TailscalePeer:
    raw_id: str | None = None
    host_name: str | None = None
    dns_name: str | None = None
    tailscale_ips: tuple[str, ...] = ()
    online: bool = False
    os: str | None = None
    user: str | None = None
    last_seen: datetime | None = None
    tags: tuple[str, ...] = ()


TailscalePeerStatus = TailscalePeer


def read_tailscale_peers(
    subprocess_runner=subprocess.run,
) -> dict[str, TailscalePeer]:
    try:
        result = subprocess_runner(
            ["tailscale", "status", "--json"],
            capture_output=True,
            check=True,
            text=True,
            timeout=2,
        )
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return {}

    try:
        payload = json.loads(result.stdout or "{}")
    except json.JSONDecodeError:
        return {}

    raw_peers = payload.get("Peer", {})
    if not isinstance(raw_peers, dict):
        return {}

    peers: dict[str, TailscalePeer] = {}
    for raw_id, peer in raw_peers.items():
        if not isinstance(peer, dict):
            continue
        tailscale_ips = tuple(str(value) for value in (peer.get("TailscaleIPs") or []))
        if not tailscale_ips:
            continue
        status = TailscalePeer(
            raw_id=str(raw_id),
            host_name=_optional_string(peer.get("HostName")),
            dns_name=_optional_string(peer.get("DNSName")),
            tailscale_ips=tailscale_ips,
            online=bool(peer.get("Online", False)),
            os=_optional_string(peer.get("OS")),
            user=_optional_string(peer.get("User")),
            last_seen=_parse_datetime(peer.get("LastSeen")),
            tags=tuple(str(value) for value in (peer.get("Tags") or [])),
        )
        for ip_address in tailscale_ips:
            peers[ip_address] = status
    return peers


def _optional_string(value: object) -> str | None:
    return value if isinstance(value, str) and value else None


def _parse_datetime(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
