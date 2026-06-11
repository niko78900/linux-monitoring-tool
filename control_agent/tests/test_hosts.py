from __future__ import annotations

from pathlib import Path

import pytest

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
