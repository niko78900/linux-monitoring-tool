from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class TailscalePeerStatus:
    online: bool
    host_name: str | None = None
    os: str | None = None
    last_seen: datetime | None = None


def read_tailscale_peers(
    subprocess_runner=subprocess.run,
) -> dict[str, TailscalePeerStatus]:
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

    peers: dict[str, TailscalePeerStatus] = {}
    for peer in payload.get("Peer", {}).values():
        tailscale_ips = peer.get("TailscaleIPs") or []
        if not tailscale_ips:
            continue
        status = TailscalePeerStatus(
            online=bool(peer.get("Online", False)),
            host_name=peer.get("HostName"),
            os=peer.get("OS"),
            last_seen=_parse_datetime(peer.get("LastSeen")),
        )
        for ip_address in tailscale_ips:
            peers[str(ip_address)] = status
    return peers


def _parse_datetime(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
