from __future__ import annotations

import asyncio
import re
import socket
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml

from ..models.devices import (
    DeviceProbeConfig,
    DeviceProbeStatus,
    DevicesResponse,
    KnownDeviceConfig,
    KnownDevicesConfigDocument,
    KnownDeviceStatus,
)
from .tailscale_peers import TailscalePeer


def load_known_devices(path: Path) -> list[KnownDeviceConfig]:
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"Could not read known devices config: {path}") from error

    try:
        payload = yaml.safe_load(raw_text) or {}
    except yaml.YAMLError as error:
        raise ValueError("Known devices config is not valid YAML") from error

    document = KnownDevicesConfigDocument.model_validate(payload)
    return document.devices


async def probe_known_devices(
    configs: list[KnownDeviceConfig],
    tailscale_peers: dict[str, TailscalePeer] | None = None,
) -> DevicesResponse:
    peers = tailscale_peers or {}
    devices = await asyncio.gather(
        *[probe_device(config, tailscale_peers=peers) for config in configs]
    )
    devices.extend(_peer_only_devices(configs, peers))
    return DevicesResponse(devices=devices)


async def probe_device(
    config: KnownDeviceConfig,
    tailscale_peers: dict[str, TailscalePeer] | None = None,
) -> KnownDeviceStatus:
    peers = tailscale_peers or {}
    probe_tasks = [run_probe(config, probe) for probe in config.probes]
    probe_results = await asyncio.gather(*probe_tasks) if probe_tasks else []

    online = any(result.reachable for result in probe_results)
    latency_ms = next(
        (result.latency_ms for result in probe_results if result.latency_ms is not None),
        None,
    )

    peer_status = _find_peer_for_config(config, peers)
    if peer_status is not None:
        if peer_status.online:
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

    return KnownDeviceStatus(
        id=config.id,
        name=config.name,
        category=config.category,
        lan_ip=config.lan_ip,
        tailscale_ip=config.tailscale_ip,
        online=online,
        latency_ms=latency_ms,
        last_checked=checked_at,
        last_seen=checked_at if online else None,
        wol_enabled=config.wol_enabled,
        wake_action=config.wake_action,
        notes=config.notes,
        tailscale_host_name=peer_status.host_name if peer_status else None,
        tailscale_dns_name=peer_status.dns_name if peer_status else None,
        tailscale_os=peer_status.os if peer_status else None,
        tailscale_online=peer_status.online if peer_status else None,
        tailscale_last_seen=peer_status.last_seen if peer_status else None,
        probes=probe_results,
        probe_summary="; ".join(summary_parts),
    )


def _peer_only_devices(
    configs: list[KnownDeviceConfig],
    peers: dict[str, TailscalePeer],
) -> list[KnownDeviceStatus]:
    configured_peer_keys = {
        _peer_key(peer, fallback_ip=config.tailscale_ip)
        for config in configs
        if (peer := _find_peer_for_config(config, peers)) is not None
    }
    now = datetime.now(timezone.utc)
    devices: list[KnownDeviceStatus] = []
    seen_ids: set[str] = set()
    seen_peer_keys: set[str] = set()
    for ip_address, peer in sorted(peers.items()):
        peer_key = _peer_key(peer, fallback_ip=ip_address)
        if peer_key in configured_peer_keys or peer_key in seen_peer_keys:
            continue
        seen_peer_keys.add(peer_key)
        device_id = f"tailscale-{_normalize_name(peer.host_name or peer.dns_name) or ip_address.replace('.', '-')}"
        if device_id in seen_ids:
            continue
        seen_ids.add(device_id)
        name = peer.host_name or peer.dns_name or ip_address
        devices.append(
            KnownDeviceStatus(
                id=device_id,
                name=name,
                category="other",
                lan_ip=None,
                tailscale_ip=peer.tailscale_ips[0] if peer.tailscale_ips else ip_address,
                online=peer.online,
                latency_ms=None,
                last_checked=now,
                last_seen=peer.last_seen if peer.last_seen is not None else (now if peer.online else None),
                wol_enabled=False,
                wake_action=None,
                notes=f"Tailscale peer{f' ({peer.os})' if peer.os else ''}",
                tailscale_host_name=peer.host_name,
                tailscale_dns_name=peer.dns_name,
                tailscale_os=peer.os,
                tailscale_online=peer.online,
                tailscale_last_seen=peer.last_seen,
                probes=[],
                probe_summary=f"Tailscale peer {'online' if peer.online else 'offline'}",
            )
        )
    return devices


def _find_peer_for_config(
    config: KnownDeviceConfig,
    peers: dict[str, TailscalePeer],
) -> TailscalePeer | None:
    if config.tailscale_ip:
        peer = peers.get(config.tailscale_ip)
        if peer is not None:
            return peer

    config_tokens = _config_identity_tokens(config)
    for peer in peers.values():
        if config.tailscale_ip and config.tailscale_ip in peer.tailscale_ips:
            return peer
        if config_tokens.intersection(_peer_identity_tokens(peer)):
            return peer
    return None


def _config_identity_tokens(config: KnownDeviceConfig) -> set[str]:
    return {
        normalized
        for value in (config.id, config.name, *config.aliases)
        if (normalized := _normalize_name(value))
    }


def _peer_identity_tokens(peer: TailscalePeer) -> set[str]:
    values = [peer.host_name, peer.dns_name, peer.raw_id]
    if peer.dns_name and "." in peer.dns_name:
        values.append(peer.dns_name.split(".", 1)[0])
    return {
        normalized for value in values if (normalized := _normalize_name(value))
    }


def _peer_key(peer: TailscalePeer, fallback_ip: str | None) -> str:
    return (
        peer.raw_id
        or peer.dns_name
        or peer.host_name
        or (peer.tailscale_ips[0] if peer.tailscale_ips else None)
        or fallback_ip
        or "unknown"
    )


def _normalize_name(value: str | None) -> str:
    return re.sub(r"[^a-z0-9]+", "-", (value or "").strip().lower()).strip("-")


async def run_probe(
    device: KnownDeviceConfig,
    probe: DeviceProbeConfig,
) -> DeviceProbeStatus:
    host = device.lan_ip or device.tailscale_ip
    if host is None:
        return DeviceProbeStatus(
            type=probe.type,
            label=probe.label,
            port=probe.port,
            reachable=False,
            latency_ms=None,
            summary=f"{probe.label}: no target IP configured",
        )

    if probe.type == "tcp":
        if probe.port is None:
            return DeviceProbeStatus(
                type="tcp",
                label=probe.label,
                port=None,
                reachable=False,
                latency_ms=None,
                summary=f"{probe.label}: port not configured",
            )
        reachable, latency_ms = await asyncio.to_thread(
            probe_tcp,
            host,
            probe.port,
        )
        return DeviceProbeStatus(
            type="tcp",
            label=probe.label,
            port=probe.port,
            reachable=reachable,
            latency_ms=latency_ms,
            summary=f"{probe.label}: {'reachable' if reachable else 'unreachable'}",
        )

    reachable, latency_ms, unavailable = await asyncio.to_thread(probe_ping, host)
    if unavailable:
        summary = f"{probe.label}: ping unavailable"
    else:
        summary = f"{probe.label}: {'reachable' if reachable else 'unreachable'}"
    return DeviceProbeStatus(
        type="ping",
        label=probe.label,
        port=None,
        reachable=reachable,
        latency_ms=latency_ms,
        summary=summary,
    )


def probe_tcp(host: str, port: int, timeout_seconds: float = 0.75) -> tuple[bool, float | None]:
    started = time.perf_counter()
    try:
        with socket.create_connection((host, port), timeout=timeout_seconds):
            latency_ms = (time.perf_counter() - started) * 1000
            return True, round(latency_ms, 1)
    except OSError:
        return False, None


def probe_ping(
    host: str,
    subprocess_runner=subprocess.run,
) -> tuple[bool, float | None, bool]:
    if hasattr(subprocess, "_mswindows") and subprocess._mswindows:
        args = ["ping", "-n", "1", "-w", "1000", host]
    else:
        args = ["ping", "-c", "1", "-W", "1", host]

    try:
        result = subprocess_runner(
            args,
            capture_output=True,
            check=False,
            text=True,
            timeout=2,
        )
    except FileNotFoundError:
        return False, None, True
    except subprocess.TimeoutExpired:
        return False, None, False

    if result.returncode != 0:
        return False, None, False

    latency_ms = _parse_ping_latency(result.stdout)
    return True, latency_ms, False


def _parse_ping_latency(stdout: str) -> float | None:
    match = re.search(r"time[=<]\s*([0-9.]+)\s*ms", stdout)
    if match is None:
        return None
    return float(match.group(1))
