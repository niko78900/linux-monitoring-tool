from __future__ import annotations

import subprocess
from pathlib import Path
from urllib import error

import pytest

from app.services.service_registry import (
    ServiceActionStateStore,
    execute_service_action,
    get_service_status,
    load_service_registry,
)


class _HttpOkResponse:
    status = 200


def test_service_registry_parses(tmp_path: Path) -> None:
    services = load_service_registry(_write_services_config(tmp_path))

    assert len(services) == 2
    assert services[0].adapter == "docker"
    assert services[0].category == "media"
    assert services[0].url == "http://127.0.0.1:8096"
    assert services[0].ports == ["8096/tcp"]
    assert services[1].adapter == "systemd"


def test_service_registry_duplicate_ids_rejected(tmp_path: Path) -> None:
    config_path = tmp_path / "services.yaml"
    config_path.write_text(
        """
services:
  - id: jellyfin
    display_name: A
    host_id: homelab-server
    adapter: docker
    target: jellyfin
  - id: jellyfin
    display_name: B
    host_id: homelab-server
    adapter: docker
    target: jellyfin
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="must be unique"):
        load_service_registry(config_path)


def test_unknown_service_rejected(client, auth_headers) -> None:
    response = client.get("/api/services/missing", headers=auth_headers)

    assert response.status_code == 404


def test_unknown_action_rejected(client, auth_headers) -> None:
    response = client.post("/api/services/jellyfin/actions/invalid", headers=auth_headers)

    assert response.status_code == 422


def test_disabled_action_rejected(tmp_path: Path) -> None:
    config_path = tmp_path / "services.yaml"
    config_path.write_text(
        """
services:
  - id: jellyfin
    display_name: Jellyfin
    host_id: homelab-server
    adapter: docker
    target: jellyfin
    allowed_actions: [restart]
""".strip(),
        encoding="utf-8",
    )
    services = load_service_registry(config_path)

    with pytest.raises(PermissionError, match="not allowed"):
        execute_service_action(
            services,
            service_id="jellyfin",
            action="start",
            helper_path=Path("/tmp/helper"),
            timeout_seconds=5,
            subprocess_runner=lambda *_args, **_kwargs: subprocess.CompletedProcess(
                [], 0, "", ""
            ),
        )


def test_action_result_persists_to_json(tmp_path: Path) -> None:
    services = load_service_registry(_write_services_config(tmp_path))
    state_store = ServiceActionStateStore(tmp_path / "service_actions.json")

    record = execute_service_action(
        services,
        service_id="jellyfin",
        action="restart",
        helper_path=Path("/tmp/helper"),
        timeout_seconds=5,
        subprocess_runner=lambda args, **_kwargs: subprocess.CompletedProcess(
            args,
            0,
            "accepted",
            "",
        ),
        action_store=state_store,
    )

    assert record.status == "accepted"
    reloaded_store = ServiceActionStateStore(tmp_path / "service_actions.json")
    status = get_service_status(
        services[0],
        subprocess_runner=lambda args, **_kwargs: subprocess.CompletedProcess(
            args,
            0,
            "running",
            "",
        ),
        url_opener=lambda *_args, **_kwargs: _HttpOkResponse(),
        action_store=reloaded_store,
    )
    assert status.last_action is not None
    assert status.last_action.action == "restart"


def test_invalid_action_state_json_is_ignored(tmp_path: Path) -> None:
    state_path = tmp_path / "service_actions.json"
    state_path.write_text("{", encoding="utf-8")

    store = ServiceActionStateStore(state_path)

    assert store.get("jellyfin") is None


def test_action_state_write_failure_does_not_block_success(tmp_path: Path) -> None:
    services = load_service_registry(_write_services_config(tmp_path))
    state_store = ServiceActionStateStore(tmp_path)

    record = execute_service_action(
        services,
        service_id="jellyfin",
        action="restart",
        helper_path=Path("/tmp/helper"),
        timeout_seconds=5,
        subprocess_runner=lambda args, **_kwargs: subprocess.CompletedProcess(
            args,
            0,
            "accepted",
            "",
        ),
        action_store=state_store,
    )

    assert record.status == "accepted"


def test_auth_required_for_services(client) -> None:
    response = client.get("/api/services")

    assert response.status_code == 401


def test_docker_adapter_status_reads_runtime(tmp_path: Path) -> None:
    service = load_service_registry(_write_services_config(tmp_path))[0]

    status = get_service_status(
        service,
        subprocess_runner=lambda *_args, **_kwargs: subprocess.CompletedProcess(
            [], 0, "running", ""
        ),
        url_opener=lambda *_args, **_kwargs: _HttpOkResponse(),
    )

    assert status.runtime_type == "docker"
    assert status.runtime_target == "jellyfin"
    assert status.category == "media"
    assert status.url == "http://127.0.0.1:8096"
    assert status.runtime_state == "running"
    assert status.health_probe_state == "healthy"


def test_systemd_adapter_status_reads_runtime(tmp_path: Path) -> None:
    service = load_service_registry(_write_services_config(tmp_path))[1]

    status = get_service_status(
        service,
        subprocess_runner=lambda *_args, **_kwargs: subprocess.CompletedProcess(
            [], 0, "active", ""
        ),
        url_opener=lambda *_args, **_kwargs: _HttpOkResponse(),
    )

    assert status.runtime_type == "systemd"
    assert status.runtime_state == "active"


def test_helper_invocation_exact_arguments(
    client, auth_headers, monkeypatch, tmp_path: Path
) -> None:
    import app.core.config as config_module

    invoked: list[list[str]] = []
    helper_path = tmp_path / "helper"
    monkeypatch.setenv("SERVICE_CONTROL_HELPER_PATH", str(helper_path))
    config_module.get_settings.cache_clear()

    def _runner(args, **_kwargs):
        invoked.append(args)
        return subprocess.CompletedProcess(args, 0, "accepted", "")

    monkeypatch.setattr("app.services.service_registry.subprocess.run", _runner)

    response = client.post("/api/services/jellyfin/actions/restart", headers=auth_headers)

    assert response.status_code == 202
    assert invoked == [[str(helper_path), "jellyfin", "restart"]]


def test_helper_failure_handling(client, auth_headers, monkeypatch, tmp_path: Path) -> None:
    import app.core.config as config_module

    helper_path = tmp_path / "helper"
    monkeypatch.setenv("SERVICE_CONTROL_HELPER_PATH", str(helper_path))
    config_module.get_settings.cache_clear()
    monkeypatch.setattr(
        "app.services.service_registry.subprocess.run",
        lambda *_args, **_kwargs: subprocess.CompletedProcess(
            [], 1, "", "helper failed"
        ),
    )

    response = client.post("/api/services/jellyfin/actions/restart", headers=auth_headers)

    assert response.status_code == 500
    assert response.json()["detail"] == "helper failed"


def test_health_probe_timeout(tmp_path: Path) -> None:
    service = load_service_registry(_write_services_config(tmp_path))[0]

    status = get_service_status(
        service,
        subprocess_runner=lambda *_args, **_kwargs: subprocess.CompletedProcess(
            [], 0, "running", ""
        ),
        url_opener=lambda *_args, **_kwargs: (_ for _ in ()).throw(TimeoutError()),
    )

    assert status.health_probe_state == "timeout"


def test_health_probe_and_runtime_status_disagreement(tmp_path: Path) -> None:
    service = load_service_registry(_write_services_config(tmp_path))[0]

    status = get_service_status(
        service,
        subprocess_runner=lambda *_args, **_kwargs: subprocess.CompletedProcess(
            [], 0, "running", ""
        ),
        url_opener=lambda *_args, **_kwargs: (_ for _ in ()).throw(error.URLError("down")),
    )

    assert status.runtime_state == "running"
    assert status.health_probe_state == "unreachable"


def test_services_endpoint_returns_status(client, auth_headers, monkeypatch) -> None:
    monkeypatch.setattr(
        "app.services.service_registry.subprocess.run",
        lambda args, **_kwargs: subprocess.CompletedProcess(
            args,
            0,
            "running" if args[0] == "docker" else "active",
            "",
        ),
    )
    monkeypatch.setattr(
        "app.services.service_registry.request.urlopen",
        lambda *_args, **_kwargs: _HttpOkResponse(),
    )

    response = client.get("/api/services", headers=auth_headers)

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["services"]) == 2
    assert payload["services"][0]["service_id"] == "jellyfin"


def _write_services_config(tmp_path: Path) -> Path:
    config_path = tmp_path / "services.yaml"
    config_path.write_text(
        """
services:
  - id: jellyfin
    display_name: Jellyfin
    host_id: homelab-server
    adapter: docker
    target: jellyfin
    category: media
    description: Media server
    url: http://127.0.0.1:8096
    ports: [8096/tcp]
    allowed_actions: [start, stop, restart]
    health_probe:
      type: http
      url: http://127.0.0.1:8096
      timeout_seconds: 3
  - id: hfs
    display_name: HFS
    host_id: homelab-server
    adapter: systemd
    target: hfs.service
    allowed_actions: [start, stop, restart]
    health_probe:
      type: http
      url: http://127.0.0.1:8081
      timeout_seconds: 3
""".strip(),
        encoding="utf-8",
    )
    return config_path
