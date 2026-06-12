from __future__ import annotations

import importlib

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def app(monkeypatch, tmp_path):
    monkeypatch.setenv("CONTROL_API_TOKEN", "test-token")
    monkeypatch.setenv("MAIN_PC_MAC", "AA:BB:CC:DD:EE:FF")
    monkeypatch.setenv("WAKE_RATE_LIMIT_SECONDS", "30")
    known_devices_path = tmp_path / "known_devices.yaml"
    known_devices_path.write_text(
        """
devices:
  - id: homelab-server
    name: Debian Server
    category: server
    lan_ip: 192.168.1.10
    tailscale_ip: 100.64.10.22
    wol_enabled: false
    probes:
      - type: tcp
        port: 22
        label: SSH
  - id: main-pc
    name: Main PC
    category: desktop
    lan_ip: 192.168.1.50
    wol_enabled: true
    wake_action: wake-main-pc
    probes:
      - type: tcp
        port: 3389
        label: RDP
""".strip(),
        encoding="utf-8",
    )
    monkeypatch.setenv("KNOWN_DEVICES_CONFIG_PATH", str(known_devices_path))
    managed_hosts_path = tmp_path / "managed_hosts.yaml"
    managed_hosts_path.write_text(
        """
hosts:
  - id: homelab-server
    display_name: Homelab Server
    category: server
    description: Debian primary homelab server
    lan_ip: 192.168.1.10
    tailscale_ip: 100.64.10.22
    monitoring_api_url: http://100.64.10.22:8000/api
    control_api_url: http://100.64.10.22:4042/api
    capabilities:
      - hardware_monitoring
      - history
      - service_control
      - ssh
      - sftp
    services:
      - jellyfin
      - hfs
    tags:
      - debian
      - primary
    probes:
      - type: tcp
        port: 22
        label: SSH
""".strip(),
        encoding="utf-8",
    )
    monkeypatch.setenv("MANAGED_HOSTS_CONFIG_PATH", str(managed_hosts_path))
    monkeypatch.setenv(
        "MOBILE_PUSH_TOKEN_REGISTRY_FILE",
        str(tmp_path / "mobile_push_tokens.json"),
    )
    monkeypatch.setenv(
        "FIREBASE_SERVICE_ACCOUNT_FILE",
        str(tmp_path / "firebase-service-account.json"),
    )
    services_path = tmp_path / "services.yaml"
    services_path.write_text(
        """
services:
  - id: jellyfin
    display_name: Jellyfin
    host_id: homelab-server
    adapter: docker
    target: jellyfin
    allowed_actions:
      - start
      - stop
      - restart
    health_probe:
      type: http
      url: http://127.0.0.1:8096
      timeout_seconds: 3
  - id: hfs
    display_name: HFS
    host_id: homelab-server
    adapter: systemd
    target: hfs.service
    allowed_actions:
      - start
      - stop
      - restart
    health_probe:
      type: http
      url: http://127.0.0.1:8081
      timeout_seconds: 3
""".strip(),
        encoding="utf-8",
    )
    monkeypatch.setenv("SERVICES_CONFIG_PATH", str(services_path))
    monkeypatch.setenv(
        "SERVICE_CONTROL_HELPER_PATH",
        str(tmp_path / "homelab-service-control"),
    )

    import app.core.config as config_module

    config_module.get_settings.cache_clear()

    import app.main as main_module

    importlib.reload(main_module)
    import app.core.rate_limit as rate_limit_module

    rate_limit_module.rate_limiter.reset()
    yield main_module.app
    config_module.get_settings.cache_clear()
    rate_limit_module.rate_limiter.reset()


@pytest.fixture
def client(app):
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def auth_headers() -> dict[str, str]:
    return {"Authorization": "Bearer test-token"}
