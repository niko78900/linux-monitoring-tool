from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from pathlib import Path

import yaml

from ..models.devices import DeviceProbeStatus
from ..models.hosts import (
    ManagedHostConfig,
    ManagedHostsConfigDocument,
    ManagedHostsResponse,
    ManagedHostStatus,
)
from .device_probe import run_probe
from .tailscale_peers import TailscalePeerStatus


def load_managed_hosts(path: Path) -> list[ManagedHostConfig]:
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"Could not read managed hosts config: {path}") from error

    try:
        payload = yaml.safe_load(raw_text) or {}
    except yaml.YAMLError as error:
        raise ValueError("Managed hosts config is not valid YAML") from error

    document = ManagedHostsConfigDocument.model_validate(payload)
    hosts = [host for host in document.hosts if host.enabled]
    ids = [host.id for host in hosts]
    duplicate_ids = {host_id for host_id in ids if ids.count(host_id) > 1}
    if duplicate_ids:
        duplicates = ", ".join(sorted(duplicate_ids))
        raise ValueError(f"Managed host IDs must be unique: {duplicates}")
    return hosts


async def probe_managed_hosts(
    configs: list[ManagedHostConfig],
    tailscale_peers: dict[str, TailscalePeerStatus] | None = None,
) -> ManagedHostsResponse:
    peers = tailscale_peers or {}
    hosts = await asyncio.gather(
        *[probe_managed_host(config, tailscale_peers=peers) for config in configs]
    )
    return ManagedHostsResponse(hosts=hosts)


async def probe_managed_host(
    config: ManagedHostConfig,
    tailscale_peers: dict[str, TailscalePeerStatus] | None = None,
) -> ManagedHostStatus:
    peers = tailscale_peers or {}
    probe_tasks = [run_probe(_host_as_probe_target(config), probe) for probe in config.probes]
    probe_results = await asyncio.gather(*probe_tasks) if probe_tasks else []

    online = any(result.reachable for result in probe_results)
    latency_ms = next(
        (result.latency_ms for result in probe_results if result.latency_ms is not None),
        None,
    )

    peer_status = None
    if config.tailscale_ip:
        peer_status = peers.get(config.tailscale_ip)
        if peer_status and peer_status.online:
            online = True

    checked_at = datetime.now(timezone.utc)
    summary_parts = [result.summary for result in probe_results]
    if peer_status is None and config.tailscale_ip:
        summary_parts.append("Tailscale peer status unavailable")
    elif peer_status is not None:
        summary_parts.append(
            f"Tailscale peer {'online' if peer_status.online else 'offline'}"
        )

    if not summary_parts:
        summary_parts.append("No probes configured")

    return ManagedHostStatus(
        id=config.id,
        display_name=config.display_name,
        category=config.category,
        description=config.description,
        lan_ip=config.lan_ip,
        tailscale_ip=config.tailscale_ip,
        tailscale_hostname=config.tailscale_hostname,
        monitoring_api_url=config.monitoring_api_url,
        control_api_url=config.control_api_url,
        enabled=config.enabled,
        online=online,
        latency_ms=latency_ms,
        last_checked=checked_at,
        last_seen=checked_at if online else None,
        capabilities=list(config.capabilities),
        services=list(config.services),
        tags=list(config.tags),
        probes=probe_results,
        probe_summary="; ".join(summary_parts),
    )


def _host_as_probe_target(config: ManagedHostConfig) -> ManagedHostConfigProbeAdapter:
    return ManagedHostConfigProbeAdapter(
        lan_ip=config.lan_ip,
        tailscale_ip=config.tailscale_ip,
    )


class ManagedHostConfigProbeAdapter:
    def __init__(self, *, lan_ip: str | None, tailscale_ip: str | None) -> None:
        self.lan_ip = lan_ip
        self.tailscale_ip = tailscale_ip
