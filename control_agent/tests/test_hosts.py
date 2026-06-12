from __future__ import annotations

from pathlib import Path
import asyncio

import pytest

from app.models.devices import DeviceProbeConfig, DeviceProbeStatus
from app.models.hosts import ManagedHostConfig
from app.services.managed_hosts import probe_managed_host
from app.services.managed_hosts import load_managed_hosts


def test_managed_hosts_yaml_parses(tmp_path: Path) -> None:
    config_path = tmp_path / "managed_hosts.yaml"
    config_path.write_text(
        """
hosts:
  - id: homelab-server
    display_name: Homelab Server
    category: server
    capabilities:
      - hardware_monitoring
      - history
""".strip(),
        encoding="utf-8",
    )

    hosts = load_managed_hosts(config_path)

    assert len(hosts) == 1
    assert hosts[0].display_name == "Homelab Server"
    assert hosts[0].capabilities == ["hardware_monitoring", "history"]


def test_managed_hosts_missing_optional_values(tmp_path: Path) -> None:
    config_path = tmp_path / "managed_hosts.yaml"
    config_path.write_text(
        """
hosts:
  - id: homelab-server
    display_name: Homelab Server
    category: server
""".strip(),
        encoding="utf-8",
    )

    hosts = load_managed_hosts(config_path)

    assert hosts[0].description is None
    assert hosts[0].capabilities == []
    assert hosts[0].services == []


def test_managed_hosts_duplicate_ids_rejected(tmp_path: Path) -> None:
    config_path = tmp_path / "managed_hosts.yaml"
    config_path.write_text(
        """
hosts:
  - id: homelab-server
    display_name: Host A
    category: server
  - id: homelab-server
    display_name: Host B
    category: server
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="must be unique"):
        load_managed_hosts(config_path)


def test_managed_hosts_disabled_entries_hidden(tmp_path: Path) -> None:
    config_path = tmp_path / "managed_hosts.yaml"
    config_path.write_text(
        """
hosts:
  - id: homelab-server
    display_name: Homelab Server
    category: server
  - id: disabled-host
    display_name: Disabled
    category: other
    enabled: false
""".strip(),
        encoding="utf-8",
    )

    hosts = load_managed_hosts(config_path)

    assert [host.id for host in hosts] == ["homelab-server"]


def test_managed_hosts_unknown_capability_preserved(tmp_path: Path) -> None:
    config_path = tmp_path / "managed_hosts.yaml"
    config_path.write_text(
        """
hosts:
  - id: homelab-server
    display_name: Homelab Server
    category: server
    capabilities:
      - hardware_monitoring
      - future_capability
""".strip(),
        encoding="utf-8",
    )

    hosts = load_managed_hosts(config_path)

    assert hosts[0].capabilities == ["hardware_monitoring", "future_capability"]


def test_hosts_endpoint_returns_enabled_managed_hosts(
    client, auth_headers, monkeypatch
) -> None:
    monkeypatch.setattr(
        "app.api.routes.hosts.read_tailscale_peers",
        lambda: {},
    )
    monkeypatch.setattr(
        "app.services.device_probe.probe_tcp",
        lambda *_args, **_kwargs: (True, 1.5),
    )

    response = client.get("/api/hosts", headers=auth_headers)

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["hosts"]) == 1
    assert payload["hosts"][0]["id"] == "homelab-server"
    assert payload["hosts"][0]["display_name"] == "Homelab Server"


def test_host_details_endpoint_returns_single_host(
    client, auth_headers, monkeypatch
) -> None:
    monkeypatch.setattr(
        "app.api.routes.hosts.read_tailscale_peers",
        lambda: {},
    )
    monkeypatch.setattr(
        "app.services.device_probe.probe_tcp",
        lambda *_args, **_kwargs: (True, 1.5),
    )

    response = client.get("/api/hosts/homelab-server", headers=auth_headers)

    assert response.status_code == 200
    payload = response.json()
    assert payload["id"] == "homelab-server"
    assert payload["services"] == ["jellyfin", "hfs"]


def test_managed_host_successful_tcp_probe_is_online(monkeypatch: pytest.MonkeyPatch) -> None:
    async def fake_run_probe(_target, probe):
        return DeviceProbeStatus(
            type=probe.type,
            label=probe.label,
            port=probe.port,
            reachable=True,
            latency_ms=2.5,
            summary="SSH: reachable",
        )

    monkeypatch.setattr("app.services.managed_hosts.run_probe", fake_run_probe)

    status = asyncio.run(probe_managed_host(_host_with_probe(), tailscale_peers={}))

    assert status.online is True
    assert status.status == "online"
    assert status.probe_summary == "SSH: reachable; Tailscale peer status unavailable"


def test_managed_host_failed_configured_probe_is_unreachable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fake_run_probe(_target, probe):
        return DeviceProbeStatus(
            type=probe.type,
            label=probe.label,
            port=probe.port,
            reachable=False,
            latency_ms=None,
            summary="SSH: unreachable",
        )

    monkeypatch.setattr("app.services.managed_hosts.run_probe", fake_run_probe)

    status = asyncio.run(probe_managed_host(_host_with_probe(), tailscale_peers={}))

    assert status.online is False
    assert status.status == "unreachable"
    assert "SSH: unreachable" in status.probe_summary


def test_managed_host_without_probe_or_peer_information_is_unknown() -> None:
    status = asyncio.run(
        probe_managed_host(
            _host_with_probe(probes=[]),
            tailscale_peers={},
        )
    )

    assert status.online is False
    assert status.status == "unknown"
    assert status.last_seen is None
    assert status.probe_summary == "No probes configured; Tailscale peer status unavailable"


def test_local_managed_host_does_not_require_tailscale_peer(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fake_run_probe(_target, probe):
        return DeviceProbeStatus(
            type=probe.type,
            label=probe.label,
            port=probe.port,
            reachable=True,
            latency_ms=1.0,
            summary="SSH: reachable",
        )

    monkeypatch.setattr("app.services.managed_hosts.run_probe", fake_run_probe)

    status = asyncio.run(probe_managed_host(_host_with_probe(), tailscale_peers={}))

    assert status.status == "online"
    assert status.last_seen is not None


def _host_with_probe(
    probes: list[DeviceProbeConfig] | None = None,
) -> ManagedHostConfig:
    return ManagedHostConfig(
        id="homelab-server",
        display_name="Homelab Server",
        category="server",
        lan_ip="192.168.100.34",
        tailscale_ip="100.64.10.22",
        probes=probes
        if probes is not None
        else [DeviceProbeConfig(type="tcp", port=22, label="SSH")],
    )
