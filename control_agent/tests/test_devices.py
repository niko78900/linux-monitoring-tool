from __future__ import annotations

from pathlib import Path

import pytest

from app.services.device_probe import load_known_devices, probe_ping, probe_tcp
from app.services.tailscale_peers import read_tailscale_peers


def test_known_devices_yaml_parses(tmp_path: Path) -> None:
    config_path = tmp_path / "devices.yaml"
    config_path.write_text(
        """
devices:
  - id: main-pc
    name: Main PC
    category: desktop
    lan_ip: 192.168.1.50
    wol_enabled: true
    wake_action: wake-main-pc
    probes:
      - type: tcp
        label: RDP
        port: 3389
""".strip(),
        encoding="utf-8",
    )

    devices = load_known_devices(config_path)

    assert len(devices) == 1
    assert devices[0].id == "main-pc"
    assert devices[0].probes[0].port == 3389


def test_known_devices_yaml_malformed(tmp_path: Path) -> None:
    config_path = tmp_path / "devices.yaml"
    config_path.write_text("devices: [", encoding="utf-8")

    with pytest.raises(ValueError, match="valid YAML"):
        load_known_devices(config_path)


def test_tcp_probe_success(monkeypatch: pytest.MonkeyPatch) -> None:
    class _FakeSocket:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return None

    monkeypatch.setattr("app.services.device_probe.socket.create_connection", lambda *_args, **_kwargs: _FakeSocket())

    reachable, latency_ms = probe_tcp("192.168.1.10", 22)

    assert reachable is True
    assert latency_ms is not None


def test_tcp_probe_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    def _raise_timeout(*_args, **_kwargs):
        raise OSError("timeout")

    monkeypatch.setattr("app.services.device_probe.socket.create_connection", _raise_timeout)

    reachable, latency_ms = probe_tcp("192.168.1.10", 22)

    assert reachable is False
    assert latency_ms is None


def test_ping_probe_unavailable_fallback() -> None:
    def _missing(*_args, **_kwargs):
        raise FileNotFoundError

    reachable, latency_ms, unavailable = probe_ping("192.168.1.10", subprocess_runner=_missing)

    assert reachable is False
    assert latency_ms is None
    assert unavailable is True


def test_tailscale_cli_unavailable_fallback() -> None:
    def _missing(*_args, **_kwargs):
        raise FileNotFoundError

    assert read_tailscale_peers(subprocess_runner=_missing) == {}


def test_devices_endpoint_returns_known_devices(client, auth_headers, monkeypatch) -> None:
    monkeypatch.setattr(
        "app.api.routes.devices.read_tailscale_peers",
        lambda: {},
    )
    monkeypatch.setattr(
        "app.services.device_probe.probe_tcp",
        lambda *_args, **_kwargs: (True, 2.4),
    )

    response = client.get("/api/devices", headers=auth_headers)

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["devices"]) == 2
    assert payload["devices"][0]["name"] == "Debian Server"
    assert payload["devices"][1]["wol_enabled"] is True
