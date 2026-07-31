from __future__ import annotations

import importlib
import json
import subprocess
from datetime import datetime
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

TEST_TOKEN = "dashboard-read-test-token-0123456789abcdef"
ALLOWED_CLIENT = ("192.0.2.10", 50000)


@pytest.fixture
def bridge_app(monkeypatch, tmp_path: Path):
    monkeypatch.setenv("DASHBOARD_CONTROL_READ_TOKEN", TEST_TOKEN)
    monkeypatch.setenv("DASHBOARD_CONTROL_ALLOWED_NETWORKS", "192.0.2.0/24")

    known_devices_path = tmp_path / "known_devices.yaml"
    known_devices_path.write_text(
        """
devices:
  - id: example-workstation
    name: Example Workstation
    category: desktop
    wol_enabled: true
    wake_action: wake-example-workstation
    probes: []
""".strip(),
        encoding="utf-8",
    )
    monkeypatch.setenv("KNOWN_DEVICES_CONFIG_PATH", str(known_devices_path))

    managed_hosts_path = tmp_path / "managed_hosts.yaml"
    managed_hosts_path.write_text(
        """
hosts:
  - id: example-server
    display_name: Example Server
    category: server
    capabilities: [hardware_monitoring]
    probes: []
""".strip(),
        encoding="utf-8",
    )
    monkeypatch.setenv("MANAGED_HOSTS_CONFIG_PATH", str(managed_hosts_path))

    services_path = tmp_path / "services.yaml"
    services_path.write_text(
        """
services:
  - id: example-service
    display_name: Example Service
    host_id: example-server
    adapter: docker
    target: example-container
    allowed_actions: [start, stop, restart]
""".strip(),
        encoding="utf-8",
    )
    monkeypatch.setenv("SERVICES_CONFIG_PATH", str(services_path))

    import app.core.config as config_module
    import app.core.read_only_config as bridge_config_module

    config_module.get_settings.cache_clear()
    bridge_config_module.get_read_only_bridge_settings.cache_clear()

    import app.read_only_main as main_module

    importlib.reload(main_module)
    monkeypatch.setattr(
        "app.api.read_only_router.read_tailscale_peers",
        lambda: {},
    )
    monkeypatch.setattr(
        "app.api.read_only_router._docker_runtime_available",
        lambda: False,
    )
    monkeypatch.setattr(
        "app.services.service_registry.subprocess.run",
        lambda args, **_kwargs: subprocess.CompletedProcess(
            args,
            1,
            "",
            "permission denied: /var/run/docker.sock",
        ),
    )

    yield main_module.app

    config_module.get_settings.cache_clear()
    bridge_config_module.get_read_only_bridge_settings.cache_clear()


@pytest.fixture
def bridge_client(bridge_app):
    with TestClient(
        bridge_app,
        client=ALLOWED_CLIENT,
        raise_server_exceptions=False,
    ) as test_client:
        yield test_client


@pytest.fixture
def bridge_auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {TEST_TOKEN}"}


def test_missing_bearer_token_is_rejected(bridge_client) -> None:
    response = bridge_client.get("/health")

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}
    assert response.headers["www-authenticate"] == "Bearer"


def test_invalid_bearer_token_is_rejected(bridge_client) -> None:
    response = bridge_client.get(
        "/health",
        headers={"Authorization": "Bearer invalid-token"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}


def test_valid_bearer_token_returns_read_only_health(
    bridge_client,
    bridge_auth_headers,
) -> None:
    response = bridge_client.get("/health", headers=bridge_auth_headers)

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "degraded"
    assert payload["read_only"] is True
    assert payload["version"] == "0.1.0"
    assert payload["discovery"] == {
        "devices": "available",
        "hosts": "available",
        "services": "available",
        "docker_runtime": "partial",
    }
    datetime.fromisoformat(payload["timestamp"].replace("Z", "+00:00"))
    assert TEST_TOKEN not in response.text


def test_device_listing_removes_wake_action_metadata(
    bridge_client,
    bridge_auth_headers,
) -> None:
    response = bridge_client.get("/devices", headers=bridge_auth_headers)

    assert response.status_code == 200
    device = response.json()["devices"][0]
    assert device["id"] == "example-workstation"
    assert device["wol_enabled"] is False
    assert device["wake_action"] is None


def test_host_listing(bridge_client, bridge_auth_headers) -> None:
    response = bridge_client.get("/hosts", headers=bridge_auth_headers)

    assert response.status_code == 200
    assert response.json()["hosts"][0]["id"] == "example-server"


def test_host_detail(bridge_client, bridge_auth_headers) -> None:
    response = bridge_client.get(
        "/hosts/example-server",
        headers=bridge_auth_headers,
    )

    assert response.status_code == 200
    assert response.json()["display_name"] == "Example Server"


def test_service_listing_is_partial_and_has_no_actions(
    bridge_client,
    bridge_auth_headers,
) -> None:
    response = bridge_client.get("/services", headers=bridge_auth_headers)

    assert response.status_code == 200
    service = response.json()["services"][0]
    assert service["service_id"] == "example-service"
    assert service["runtime_state"] == "unavailable"
    assert service["allowed_actions"] == []
    assert service["last_action"] is None
    assert "permission denied" not in response.text.lower()
    assert "docker.sock" not in response.text


def test_service_detail_is_read_only(bridge_client, bridge_auth_headers) -> None:
    response = bridge_client.get(
        "/services/example-service",
        headers=bridge_auth_headers,
    )

    assert response.status_code == 200
    assert response.json()["allowed_actions"] == []


@pytest.mark.parametrize(
    "action_path",
    [
        "/services/example-service/actions/restart",
        "/actions/wake-main-pc",
        "/benchmarks/start",
        "/benchmarks/stop",
    ],
)
def test_post_action_routes_are_absent_and_cannot_execute(
    bridge_client,
    bridge_auth_headers,
    monkeypatch,
    action_path: str,
) -> None:
    executed = False

    def _unexpected_action(*_args, **_kwargs):
        nonlocal executed
        executed = True
        raise AssertionError("action execution must not be reachable")

    monkeypatch.setattr(
        "app.services.service_registry.execute_service_action",
        _unexpected_action,
    )

    response = bridge_client.post(
        action_path,
        headers=bridge_auth_headers,
    )

    assert response.status_code == 404
    assert executed is False


@pytest.mark.parametrize("method", ["put", "patch", "delete"])
def test_mutating_methods_are_rejected(
    bridge_client,
    bridge_auth_headers,
    method: str,
) -> None:
    response = getattr(bridge_client, method)(
        "/services/example-service",
        headers=bridge_auth_headers,
    )

    assert response.status_code == 405


def test_arbitrary_path_is_rejected(bridge_client, bridge_auth_headers) -> None:
    response = bridge_client.get("/arbitrary-command", headers=bridge_auth_headers)

    assert response.status_code == 404


def test_discovery_configuration_error_is_sanitized(
    bridge_client,
    bridge_auth_headers,
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        "app.api.read_only_router.load_known_devices",
        lambda _path: (_ for _ in ()).throw(
            ValueError("secret topology and protected path")
        ),
    )

    response = bridge_client.get("/devices", headers=bridge_auth_headers)

    assert response.status_code == 503
    assert response.json() == {"detail": "Device discovery is unavailable"}
    assert "secret" not in response.text
    assert "protected path" not in response.text


def test_unexpected_discovery_error_is_sanitized(
    bridge_client,
    bridge_auth_headers,
    monkeypatch,
) -> None:
    async def _fail(*_args, **_kwargs):
        raise RuntimeError("sensitive internal failure")

    monkeypatch.setattr("app.api.read_only_router.probe_managed_hosts", _fail)

    response = bridge_client.get("/hosts", headers=bridge_auth_headers)

    assert response.status_code == 500
    assert response.json() == {"detail": "Internal server error"}
    assert "sensitive" not in response.text


def test_openapi_declares_bearer_and_contains_only_read_routes(bridge_app) -> None:
    schema = bridge_app.openapi()
    expected_paths = {
        "/health",
        "/devices",
        "/hosts",
        "/hosts/{host_id}",
        "/services",
        "/services/{service_id}",
    }

    assert set(schema["paths"]) == expected_paths
    assert schema["components"]["securitySchemes"] == {
        "DashboardControlReadBearer": {
            "type": "http",
            "description": "Dedicated bearer credential for the read-only Dashboard bridge.",
            "scheme": "bearer",
        }
    }
    for path_definition in schema["paths"].values():
        assert set(path_definition) == {"get"}
        assert path_definition["get"]["security"] == [
            {"DashboardControlReadBearer": []}
        ]
    assert TEST_TOKEN not in json.dumps(schema)


def test_openapi_http_endpoint_is_not_exposed(
    bridge_client,
    bridge_auth_headers,
) -> None:
    response = bridge_client.get("/openapi.json", headers=bridge_auth_headers)

    assert response.status_code == 404


def test_request_outside_allowed_network_is_hidden(
    bridge_app,
    bridge_auth_headers,
) -> None:
    with TestClient(
        bridge_app,
        client=("198.51.100.10", 50000),
        raise_server_exceptions=False,
    ) as client:
        response = client.get("/health", headers=bridge_auth_headers)

    assert response.status_code == 404
