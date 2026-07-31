from __future__ import annotations

import time
from dataclasses import dataclass
from ipaddress import ip_network
from pathlib import Path
from uuid import uuid4

import pytest
import yaml
from fastapi.testclient import TestClient

from app.action_main import create_app
from app.core.action_config import ActionServiceSettings
from app.services.action_executor import HelperExecutionResult

TEST_TOKEN = "dashboard-action-test-token-0123456789abcdef"
ALLOWED_CLIENT = ("192.0.2.10", 51000)


class FakeHelper:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []
        self.result = HelperExecutionResult(
            status="succeeded",
            summary="Action completed.",
            previous_state="running",
            resulting_state="running",
        )
        self.delay_seconds = 0.0
        self.failure: Exception | None = None

    async def execute(self, record, *, timeout_seconds: int):
        import asyncio

        self.calls.append((record.target_id, record.action))
        if self.delay_seconds:
            await asyncio.sleep(self.delay_seconds)
        if self.failure is not None:
            raise self.failure
        return self.result


@dataclass
class ActionHarness:
    app: object
    client: TestClient
    helper: FakeHelper
    headers: dict[str, str]
    database_path: Path


@pytest.fixture
def action_harness(tmp_path: Path):
    registry_path = tmp_path / "registry.yml"
    registry_path.write_text(
        yaml.safe_dump(
            {
                "services": [
                    {
                        "id": "example-worker",
                        "name": "Example Worker",
                        "kind": "docker_container",
                        "container_name": "example-worker",
                        "expected_compose_project": "example-stack",
                        "expected_compose_service": "worker",
                        "allowed_actions": ["start", "stop", "restart"],
                        "timeout_seconds": 10,
                        "health_url": "http://127.0.0.1:8080/health",
                        "confirmation_level": "normal",
                    },
                    {
                        "id": "restart-only",
                        "name": "Restart Only",
                        "kind": "systemd",
                        "systemd_unit": "example-restart-only.service",
                        "allowed_actions": ["restart"],
                        "timeout_seconds": 10,
                        "confirmation_level": "high",
                    },
                ],
                "wake_targets": [
                    {
                        "id": "main-pc",
                        "name": "Main PC",
                        "allowed_actions": ["wake"],
                        "mac_address": "AA:BB:CC:DD:EE:FF",
                        "broadcast_address": "192.0.2.255",
                        "interface": "example0",
                        "port": 9,
                        "timeout_seconds": 10,
                        "confirmation_level": "normal",
                    }
                ],
            },
            sort_keys=False,
        ),
        encoding="utf-8",
    )
    helper_path = tmp_path / "helper"
    helper_path.write_text("test helper", encoding="utf-8")
    helper_path.chmod(0o700)
    database_path = tmp_path / "state" / "actions.db"
    settings = ActionServiceSettings(
        token=TEST_TOKEN,
        allowed_networks=(ip_network("192.0.2.0/24"),),
        registry_path=registry_path.resolve(),
        database_path=database_path.resolve(),
        helper_path=helper_path.resolve(),
        worker_count=1,
        queue_size=8,
        retention_records=100,
        retention_days=30,
    )
    helper = FakeHelper()
    application = create_app(action_settings=settings, helper=helper)
    with TestClient(
        application,
        client=ALLOWED_CLIENT,
        raise_server_exceptions=False,
    ) as client:
        yield ActionHarness(
            app=application,
            client=client,
            helper=helper,
            headers={"Authorization": f"Bearer {TEST_TOKEN}"},
            database_path=database_path,
        )


def _body(request_id=None, **extra):
    body = {
        "confirmed": True,
        "request_id": str(request_id or uuid4()),
        "reason": " Controlled   validation ",
    }
    body.update(extra)
    return body


def _wait_for_terminal(
    harness: ActionHarness,
    action_id: str,
    *,
    timeout: float = 2.0,
) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        response = harness.client.get(
            f"/actions/{action_id}",
            headers=harness.headers,
        )
        assert response.status_code == 200
        record = response.json()
        if record["status"] not in {"queued", "running"}:
            return record
        time.sleep(0.01)
    raise AssertionError("action did not reach a terminal state")


def test_missing_token_is_rejected(action_harness: ActionHarness) -> None:
    response = action_harness.client.get("/health")

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}
    assert response.headers["www-authenticate"] == "Bearer"


def test_invalid_token_is_rejected(action_harness: ActionHarness) -> None:
    response = action_harness.client.get(
        "/health",
        headers={"Authorization": "Bearer invalid"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}


def test_valid_token_exposes_health_and_capabilities(
    action_harness: ActionHarness,
) -> None:
    health = action_harness.client.get("/health", headers=action_harness.headers)
    capabilities = action_harness.client.get(
        "/capabilities",
        headers=action_harness.headers,
    )
    services = action_harness.client.get("/services", headers=action_harness.headers)
    detail = action_harness.client.get(
        "/services/example-worker",
        headers=action_harness.headers,
    )

    assert health.status_code == 200
    assert health.json()["status"] == "ok"
    assert health.json()["registry_service_count"] == 2
    assert health.json()["wake_available"] is True
    assert capabilities.status_code == 200
    assert capabilities.json()["wake_main_pc"]["available"] is True
    assert services.status_code == 200
    assert len(services.json()["services"]) == 2
    assert detail.json()["allowed_actions"] == ["start", "stop", "restart"]
    assert "container_name" not in detail.json()
    assert "systemd_unit" not in detail.json()


def test_disallowed_source_is_hidden(action_harness: ActionHarness) -> None:
    with TestClient(
        action_harness.app,
        client=("198.51.100.10", 51000),
        raise_server_exceptions=False,
    ) as client:
        response = client.get("/health", headers=action_harness.headers)

    assert response.status_code == 404


def test_unknown_service_is_not_found(action_harness: ActionHarness) -> None:
    response = action_harness.client.post(
        "/services/unknown/actions/restart",
        headers=action_harness.headers,
        json=_body(),
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "Service not found"}


def test_disallowed_action_is_forbidden(action_harness: ActionHarness) -> None:
    response = action_harness.client.post(
        "/services/restart-only/actions/stop",
        headers=action_harness.headers,
        json=_body(),
    )

    assert response.status_code == 403
    assert response.json() == {"detail": "Action is not allowed for this service"}


@pytest.mark.parametrize(
    "body",
    [
        {"request_id": str(uuid4())},
        {"confirmed": False, "request_id": str(uuid4())},
        {"confirmed": True, "request_id": "not-a-uuid"},
        {"confirmed": True, "request_id": str(uuid4()), "reason": "bad\nreason"},
    ],
)
def test_confirmation_and_request_validation_are_required(
    action_harness: ActionHarness,
    body: dict,
) -> None:
    response = action_harness.client.post(
        "/services/example-worker/actions/restart",
        headers=action_harness.headers,
        json=body,
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "Request validation failed"}


@pytest.mark.parametrize(
    "field",
    ["mac_address", "broadcast_address", "container_name", "systemd_unit", "path", "command"],
)
def test_caller_cannot_supply_execution_targets(
    action_harness: ActionHarness,
    field: str,
) -> None:
    response = action_harness.client.post(
        "/services/example-worker/actions/restart",
        headers=action_harness.headers,
        json=_body(**{field: "caller-controlled"}),
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "Request validation failed"}


@pytest.mark.parametrize("action", ["start", "stop", "restart"])
def test_successful_service_actions_are_durable(
    action_harness: ActionHarness,
    action: str,
) -> None:
    if action == "stop":
        action_harness.helper.result = HelperExecutionResult(
            status="succeeded",
            summary="Container stopped successfully.",
            previous_state="running",
            resulting_state="exited",
        )
    response = action_harness.client.post(
        f"/services/example-worker/actions/{action}",
        headers=action_harness.headers,
        json=_body(),
    )

    assert response.status_code == 202
    accepted = response.json()
    assert response.headers["location"] == accepted["polling_location"]
    record = _wait_for_terminal(action_harness, accepted["action_id"])
    history = action_harness.client.get("/actions", headers=action_harness.headers)

    assert record["status"] == "succeeded"
    assert record["reason"] == "Controlled validation"
    assert any(item["action_id"] == accepted["action_id"] for item in history.json()["actions"])


def test_failed_command_is_sanitized(action_harness: ActionHarness) -> None:
    action_harness.helper.result = HelperExecutionResult(
        status="failed",
        summary="Container action failed.",
        error_code="operation_failed",
        previous_state="running",
    )
    response = action_harness.client.post(
        "/services/example-worker/actions/restart",
        headers=action_harness.headers,
        json=_body(reason="token=must-not-appear"),
    )
    record = _wait_for_terminal(action_harness, response.json()["action_id"])

    assert record["status"] == "failed"
    assert record["error_code"] == "operation_failed"
    assert "token=" not in (record["result_summary"] or "")


def test_action_timeout_is_recorded(action_harness: ActionHarness) -> None:
    action_harness.helper.result = HelperExecutionResult(
        status="timed_out",
        summary="Action timed out.",
        error_code="operation_timeout",
        previous_state="running",
    )
    response = action_harness.client.post(
        "/services/example-worker/actions/restart",
        headers=action_harness.headers,
        json=_body(),
    )
    record = _wait_for_terminal(action_harness, response.json()["action_id"])

    assert record["status"] == "timed_out"
    assert record["error_code"] == "operation_timeout"


def test_unexpected_helper_error_is_sanitized(action_harness: ActionHarness) -> None:
    action_harness.helper.failure = RuntimeError("secret command output")
    response = action_harness.client.post(
        "/services/example-worker/actions/restart",
        headers=action_harness.headers,
        json=_body(),
    )
    record = _wait_for_terminal(action_harness, response.json()["action_id"])

    assert record["status"] == "failed"
    assert record["result_summary"] == "Action helper was unavailable."
    assert "secret" not in str(record)


def test_duplicate_request_id_returns_original_result(
    action_harness: ActionHarness,
) -> None:
    request_id = uuid4()
    action_harness.helper.delay_seconds = 0.05
    first = action_harness.client.post(
        "/services/example-worker/actions/restart",
        headers=action_harness.headers,
        json=_body(request_id=request_id),
    )
    second = action_harness.client.post(
        "/services/example-worker/actions/restart",
        headers=action_harness.headers,
        json=_body(request_id=request_id),
    )
    _wait_for_terminal(action_harness, first.json()["action_id"])

    assert first.status_code == second.status_code == 202
    assert first.json()["action_id"] == second.json()["action_id"]
    assert action_harness.helper.calls.count(("example-worker", "restart")) == 1


def test_busy_target_returns_conflict(action_harness: ActionHarness) -> None:
    action_harness.helper.delay_seconds = 0.2
    first = action_harness.client.post(
        "/services/example-worker/actions/restart",
        headers=action_harness.headers,
        json=_body(),
    )
    second = action_harness.client.post(
        "/services/example-worker/actions/stop",
        headers=action_harness.headers,
        json=_body(),
    )

    assert first.status_code == 202
    assert second.status_code == 409
    assert second.json() == {"detail": "Target already has an active action"}
    _wait_for_terminal(action_harness, first.json()["action_id"])


def test_wake_action_uses_only_registry_target(action_harness: ActionHarness) -> None:
    action_harness.helper.result = HelperExecutionResult(
        status="succeeded",
        summary="Wake-on-LAN magic packet sent.",
        previous_state="unknown",
        resulting_state="packet-sent",
    )
    response = action_harness.client.post(
        "/actions/wake-main-pc",
        headers=action_harness.headers,
        json=_body(),
    )
    record = _wait_for_terminal(action_harness, response.json()["action_id"])

    assert response.status_code == 202
    assert record["target_id"] == "main-pc"
    assert record["resulting_state"] == "packet-sent"
    assert action_harness.helper.calls[-1] == ("main-pc", "wake")


def test_wake_request_rejects_caller_mac(action_harness: ActionHarness) -> None:
    response = action_harness.client.post(
        "/actions/wake-main-pc",
        headers=action_harness.headers,
        json=_body(mac_address="AA:BB:CC:DD:EE:FF"),
    )

    assert response.status_code == 422
    assert action_harness.helper.calls == []


@pytest.mark.parametrize("method", ["put", "patch", "delete"])
def test_unsupported_mutating_methods_are_rejected(
    action_harness: ActionHarness,
    method: str,
) -> None:
    response = action_harness.client.request(
        method.upper(),
        "/services/example-worker/actions/restart",
        headers=action_harness.headers,
        json=_body(),
    )

    assert response.status_code == 405
    assert action_harness.helper.calls == []


def test_arbitrary_paths_and_proxy_routes_are_absent(
    action_harness: ActionHarness,
) -> None:
    for path in ("/proxy", "/commands", "/shell", "/docker/restart", "/systemd/restart"):
        response = action_harness.client.post(
            path,
            headers=action_harness.headers,
            json=_body(),
        )
        assert response.status_code == 404


def test_openapi_declares_bearer_and_only_explicit_routes(
    action_harness: ActionHarness,
) -> None:
    schema = action_harness.app.openapi()
    security_schemes = schema["components"]["securitySchemes"]
    paths = schema["paths"]

    assert security_schemes["DashboardControlActionBearer"] == {
        "type": "http",
        "description": "Dedicated bearer credential for the Dashboard action service.",
        "scheme": "bearer",
    }
    assert set(paths) == {
        "/health",
        "/capabilities",
        "/services",
        "/services/{service_id}",
        "/actions",
        "/actions/{action_id}",
        "/services/{service_id}/actions/{action}",
        "/actions/wake-main-pc",
    }
    for operations in paths.values():
        for operation in operations.values():
            assert {"DashboardControlActionBearer": []} in operation["security"]
    assert set(paths["/services/{service_id}/actions/{action}"]) == {"post"}
    assert set(paths["/actions/wake-main-pc"]) == {"post"}


def test_action_openapi_is_not_served_over_http(action_harness: ActionHarness) -> None:
    response = action_harness.client.get(
        "/openapi.json",
        headers=action_harness.headers,
    )

    assert response.status_code == 404


def test_systemd_template_has_narrow_bind_and_separate_port() -> None:
    unit = (
        Path(__file__).parents[2]
        / "deploy/systemd/linux-monitor-dashboard-action.service"
    ).read_text(encoding="utf-8")

    assert "--host ${DASHBOARD_CONTROL_ACTION_HOST}" in unit
    assert "--port ${DASHBOARD_CONTROL_ACTION_PORT}" in unit
    assert "0.0.0.0" not in unit
    assert "4043" not in unit
    assert "User=linux-monitor-action" in unit


def test_existing_read_only_bridge_router_has_no_actions() -> None:
    from app.read_only_main import create_app as create_read_only_app

    read_only_app = create_read_only_app()
    route_methods = {
        route.path: set(route.methods or set())
        for route in read_only_app.routes
        if getattr(route, "path", None)
    }

    assert "/actions/wake-main-pc" not in route_methods
    assert "/services/{service_id}/actions/{action}" not in route_methods
    assert all(
        not methods.intersection({"POST", "PUT", "PATCH", "DELETE"})
        for path, methods in route_methods.items()
        if path in {"/health", "/devices", "/hosts", "/hosts/{host_id}", "/services", "/services/{service_id}"}
    )
