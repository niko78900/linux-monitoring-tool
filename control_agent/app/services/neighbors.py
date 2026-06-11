from __future__ import annotations

import subprocess

from ..models.network import ObservedNeighbor


def read_neighbors(subprocess_runner=subprocess.run) -> list[ObservedNeighbor]:
    try:
        result = subprocess_runner(
            ["ip", "neigh", "show"],
            capture_output=True,
            check=True,
            text=True,
            timeout=2,
        )
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return []

    neighbors: list[ObservedNeighbor] = []
    for line in result.stdout.splitlines():
        parsed = _parse_neighbor_line(line)
        if parsed is not None:
            neighbors.append(parsed)
    return neighbors


def _parse_neighbor_line(line: str) -> ObservedNeighbor | None:
    parts = line.split()
    if len(parts) < 4:
        return None

    ip_address = parts[0]
    interface_name = parts[2] if len(parts) >= 3 and parts[1] == "dev" else None
    mac_address = None
    state = parts[-1] if parts else None

    if "lladdr" in parts:
        index = parts.index("lladdr")
        if index + 1 < len(parts):
            mac_address = parts[index + 1]

    if state == "FAILED":
        mac_address = mac_address or None

    return ObservedNeighbor(
        ip=ip_address,
        mac_address=mac_address,
        interface_name=interface_name,
        state=state,
    )
