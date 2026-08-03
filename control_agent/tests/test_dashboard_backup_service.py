from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass
from ipaddress import ip_network
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.backup_main import create_app
from app.core.backup_config import BackupServiceSettings
from app.services.backup_executor import (
    BackupAssessment,
    BackupExecutionResult,
    BackupProgress,
)
from app.services.backup_registry import BackupRegistry

TEST_TOKEN = "dashboard-backup-test-token-0123456789abcdef"
ALLOWED_CLIENT = ("192.0.2.10", 51000)


class FakeBackupHelper:
    def __init__(self) -> None:
        self.assessment = BackupAssessment(
            allowed=True,
            blocking_code=None,
            blocking_reason=None,
            source_size_estimate=1024,
            destination_free_bytes=100_000_000_000,
            required_bytes=2_000_000_000,
            cold_storage_mounted=True,
            cold_storage_writable=True,
            raid_healthy=True,
        )
        self.result = BackupExecutionResult(
            status="succeeded",
            summary="Backup completed and verification passed.",
            error_code=None,
            verification_state="passed",
            destination_snapshot="/mnt/storage/backups/database/2026-01-01T000000Z",
            manifest_path="/mnt/storage/backups/database/2026-01-01T000000Z/manifest.json",
            files_examined=1,
            files_copied=1,
            bytes_examined=1024,
            bytes_copied=1024,
        )
        self.delay_seconds = 0.0
        self.cancelled: set[str] = set()
        self.failure: Exception | None = None
        self.validation_calls = 0

    async def validate_registry(self, *, plan_id: str, fingerprint: str) -> None:
        self.validation_calls += 1

    async def assess(self, *, plan, job_id: str, fingerprint: str, operation: str = "assess"):
        return self.assessment

    async def execute(self, *, plan, job_id: str, fingerprint: str, on_progress):
        await on_progress(BackupProgress(phase="running", progress_percent=10.0))
        if self.delay_seconds:
            await asyncio.sleep(self.delay_seconds)
        if self.failure is not None:
            raise self.failure
        if job_id in self.cancelled:
            return BackupExecutionResult(
                status="cancelled",
                summary="Backup cancelled by the operator.",
                error_code="cancelled_by_operator",
                verification_state="failed",
                destination_snapshot=None,
                manifest_path=None,
                files_examined=0,
                files_copied=0,
                bytes_examined=0,
                bytes_copied=0,
            )
        await on_progress(BackupProgress(phase="verifying", progress_percent=90.0))
        return self.result

    async def cancel(self, *, plan_id: str, job_id: str, fingerprint: str) -> bool:
        self.cancelled.add(job_id)
        return True


def _registry() -> BackupRegistry:
    return BackupRegistry.model_validate(
        {
            "version": 1,
            "cold_mount": "/mnt/storage",
            "destination_root": "/mnt/storage/backups",
            "raid_device": "/dev/md0",
            "minimum_free_bytes": 1_073_741_824,
            "capacity_overhead_percent": 10,
            "plans": [
                {
                    "id": "database",
                    "display_name": "Database backup",
                    "description": "Consistent logical database dump.",
                    "enabled": True,
                    "destination": "/mnt/storage/backups/database",
                    "timeout_seconds": 600,
                    "estimated_size_bytes": 1024,
                    "confirmation_level": "high",
                    "retention": {"mode": "manual", "retain_at_least": 2},
                    "steps": [
                        {
                            "type": "postgres_dump",
                            "container": "example-postgres",
                            "expected_compose_project": "example",
                            "expected_compose_service": "database",
                            "database": "example",
                            "role": "postgres",
                            "component": "database",
                            "filename": "database.dump",
                            "timeout_seconds": 300,
                        },
                        {"type": "verification", "mode": "sha256"},
                        {"type": "manifest"},
                    ],
                },
                {
                    "id": "disabled",
                    "display_name": "Disabled backup",
                    "description": "Intentionally disabled plan.",
                    "enabled": False,
                    "disabled_reason": "Intentionally disabled for validation.",
                    "destination": "/mnt/storage/backups/disabled",
                    "timeout_seconds": 600,
                    "estimated_size_bytes": 1024,
                    "confirmation_level": "high",
                    "retention": {"mode": "manual", "retain_at_least": 1},
                    "steps": [
                        {
                            "type": "copy_files",
                            "sources": ["/etc/systemd/system/example.service"],
                            "component": "configuration",
                        },
                        {"type": "verification", "mode": "sha256"},
                        {"type": "manifest"},
                    ],
                },
            ],
        }
    )


@dataclass
class BackupHarness:
    app: object
    client: TestClient
    helper: FakeBackupHelper
    headers: dict[str, str]
    database_path: Path


@pytest.fixture
def backup_harness(tmp_path: Path):
    registry_path = tmp_path / "registry.yml"
    registry_path.write_text("version: 1\n", encoding="utf-8")
    helper_path = tmp_path / "helper"
    helper_path.write_text("helper", encoding="utf-8")
    helper_path.chmod(0o700)
    database_path = tmp_path / "state" / "backups.db"
    settings = BackupServiceSettings(
        token=TEST_TOKEN,
        allowed_networks=(ip_network("192.0.2.0/24"),),
        registry_path=registry_path,
        registry_is_credential=True,
        database_path=database_path,
        helper_path=helper_path,
        worker_count=1,
        queue_size=8,
        retention_records=100,
        retention_days=30,
    )
    helper = FakeBackupHelper()
    application = create_app(
        backup_settings=settings,
        helper=helper,
        registry_override=_registry(),
    )
    with TestClient(
        application,
        client=ALLOWED_CLIENT,
        raise_server_exceptions=False,
    ) as client:
        yield BackupHarness(
            app=application,
            client=client,
            helper=helper,
            headers={"Authorization": f"Bearer {TEST_TOKEN}"},
            database_path=database_path,
        )


def _body(request_id=None, **extra) -> dict:
    body = {
        "confirmed": True,
        "request_id": str(request_id or uuid4()),
        "reason": " Controlled   validation ",
    }
    body.update(extra)
    return body


def _wait_for_terminal(harness: BackupHarness, job_id: str, timeout: float = 3.0) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        response = harness.client.get(f"/jobs/{job_id}", headers=harness.headers)
        assert response.status_code == 200
        record = response.json()
        if record["status"] in {"succeeded", "failed", "cancelled", "timed_out", "rejected"}:
            return record
        time.sleep(0.01)
    raise AssertionError("backup job did not become terminal")


def test_authentication_is_required_on_every_route(backup_harness: BackupHarness) -> None:
    routes = ["/health", "/plans", "/plans/database", "/jobs", f"/jobs/{uuid4()}"]
    for route in routes:
        response = backup_harness.client.get(route)
        assert response.status_code == 401
        assert response.json() == {"detail": "Unauthorized"}


def test_invalid_token_and_disallowed_source_are_rejected(backup_harness: BackupHarness) -> None:
    invalid = backup_harness.client.get(
        "/health",
        headers={"Authorization": "Bearer invalid"},
    )
    assert invalid.status_code == 401
    with TestClient(
        backup_harness.app,
        client=("198.51.100.10", 51000),
        raise_server_exceptions=False,
    ) as client:
        hidden = client.get("/health", headers=backup_harness.headers)
    assert hidden.status_code == 404


def test_health_and_plan_contracts_are_safe(backup_harness: BackupHarness) -> None:
    health = backup_harness.client.get("/health", headers=backup_harness.headers)
    plans = backup_harness.client.get("/plans", headers=backup_harness.headers)

    assert health.status_code == 200
    assert health.json()["status"] == "ok"
    assert health.json()["plan_count"] == 2
    assert plans.status_code == 200
    database = next(item for item in plans.json()["plans"] if item["id"] == "database")
    assert database["allowed_to_start_now"] is True
    assert "container" not in str(database)
    assert "role" not in str(database)


@pytest.mark.parametrize(
    "body",
    [
        {"request_id": str(uuid4())},
        {"confirmed": False, "request_id": str(uuid4())},
        {"confirmed": True, "request_id": "not-a-uuid"},
        {"confirmed": True, "request_id": str(uuid4()), "reason": "bad\nreason"},
    ],
)
def test_confirmation_uuid_and_reason_are_validated(
    backup_harness: BackupHarness,
    body: dict,
) -> None:
    response = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=body,
    )
    assert response.status_code == 422
    assert response.json() == {"detail": "Request validation failed"}


@pytest.mark.parametrize("field", ["source", "destination", "path", "command", "args", "plan"])
def test_caller_cannot_supply_paths_commands_or_plans(
    backup_harness: BackupHarness,
    field: str,
) -> None:
    response = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=_body(**{field: "/caller/controlled"}),
    )
    assert response.status_code == 422


def test_unknown_and_disabled_plans_are_safe(backup_harness: BackupHarness) -> None:
    unknown = backup_harness.client.post(
        "/plans/unknown/jobs",
        headers=backup_harness.headers,
        json=_body(),
    )
    disabled = backup_harness.client.post(
        "/plans/disabled/jobs",
        headers=backup_harness.headers,
        json=_body(),
    )

    assert unknown.status_code == 404
    assert disabled.status_code == 409
    assert disabled.json()["error_code"] == "plan_disabled"


def test_successful_job_progress_manifest_and_history(backup_harness: BackupHarness) -> None:
    response = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=_body(),
    )
    assert response.status_code == 202
    accepted = response.json()
    assert response.headers["location"] == accepted["polling_location"]
    record = _wait_for_terminal(backup_harness, accepted["job"]["job_id"])
    history = backup_harness.client.get("/jobs", headers=backup_harness.headers).json()["jobs"]

    assert record["status"] == "succeeded"
    assert record["verification_state"] == "passed"
    assert record["manifest_path"].endswith("/manifest.json")
    assert record["reason"] == "Controlled validation"
    assert any(item["job_id"] == record["job_id"] for item in history)


def test_duplicate_request_id_returns_original_job(backup_harness: BackupHarness) -> None:
    request_id = uuid4()
    first = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=_body(request_id),
    )
    second = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=_body(request_id),
    )

    assert first.status_code == 202
    assert second.status_code == 200
    assert second.json()["duplicate"] is True
    assert second.json()["job"]["job_id"] == first.json()["job"]["job_id"]


def test_concurrent_same_plan_rejected(backup_harness: BackupHarness) -> None:
    backup_harness.helper.delay_seconds = 0.3
    first = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=_body(),
    )
    second = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=_body(),
    )

    assert first.status_code == 202
    assert second.status_code == 409
    assert second.json()["error_code"] == "plan_busy"


def test_capacity_rejection_is_specific_and_durable(backup_harness: BackupHarness) -> None:
    backup_harness.helper.assessment = BackupAssessment(
        allowed=False,
        blocking_code="insufficient_capacity",
        blocking_reason="Cold storage does not have enough free capacity for this backup.",
        source_size_estimate=100,
        destination_free_bytes=10,
        required_bytes=200,
        cold_storage_mounted=True,
        cold_storage_writable=True,
        raid_healthy=True,
    )
    response = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=_body(),
    )

    assert response.status_code == 507
    assert response.json()["error_code"] == "insufficient_capacity"
    record = backup_harness.client.get(
        f"/jobs/{response.json()['job_id']}", headers=backup_harness.headers
    ).json()
    assert record["status"] == "rejected"


@pytest.mark.parametrize(
    ("code", "mounted", "raid"),
    [
        ("cold_storage_unavailable", False, True),
        ("raid_unhealthy", True, False),
    ],
)
def test_mount_or_raid_rejection(
    backup_harness: BackupHarness,
    code: str,
    mounted: bool,
    raid: bool,
) -> None:
    backup_harness.helper.assessment = BackupAssessment(
        allowed=False,
        blocking_code=code,
        blocking_reason="Backup storage safety check failed.",
        source_size_estimate=100,
        destination_free_bytes=1000,
        required_bytes=200,
        cold_storage_mounted=mounted,
        cold_storage_writable=mounted,
        raid_healthy=raid,
    )
    response = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=_body(),
    )
    assert response.status_code == 409
    assert response.json()["error_code"] == code


def test_running_job_can_be_cancelled_safely(backup_harness: BackupHarness) -> None:
    backup_harness.helper.delay_seconds = 0.3
    response = backup_harness.client.post(
        "/plans/database/jobs",
        headers=backup_harness.headers,
        json=_body(),
    )
    job_id = response.json()["job"]["job_id"]
    time.sleep(0.05)
    cancellation = backup_harness.client.post(
        f"/jobs/{job_id}/cancel",
        headers=backup_harness.headers,
    )
    record = _wait_for_terminal(backup_harness, job_id)

    assert cancellation.status_code == 202
    assert cancellation.json()["cancellation_requested"] is True
    assert record["status"] == "cancelled"


def test_timeout_and_rsync_failure_are_sanitized(backup_harness: BackupHarness) -> None:
    backup_harness.helper.result = BackupExecutionResult(
        status="timed_out",
        summary="Backup exceeded its execution deadline.",
        error_code="backup_timeout",
        verification_state="failed",
        destination_snapshot=None,
        manifest_path=None,
        files_examined=0,
        files_copied=0,
        bytes_examined=0,
        bytes_copied=0,
    )
    timed_out = backup_harness.client.post(
        "/plans/database/jobs", headers=backup_harness.headers, json=_body()
    )
    record = _wait_for_terminal(backup_harness, timed_out.json()["job"]["job_id"])
    assert record["status"] == "timed_out"

    backup_harness.helper.result = BackupExecutionResult(
        status="failed",
        summary="Rsync snapshot failed.",
        error_code="rsync_failed",
        verification_state="failed",
        destination_snapshot=None,
        manifest_path=None,
        files_examined=0,
        files_copied=0,
        bytes_examined=0,
        bytes_copied=0,
    )
    failed = backup_harness.client.post(
        "/plans/database/jobs", headers=backup_harness.headers, json=_body()
    )
    failure_record = _wait_for_terminal(backup_harness, failed.json()["job"]["job_id"])
    assert failure_record["error_code"] == "rsync_failed"


def test_unexpected_errors_do_not_leak_output(backup_harness: BackupHarness) -> None:
    backup_harness.helper.failure = RuntimeError("password=secret raw stderr")
    response = backup_harness.client.post(
        "/plans/database/jobs", headers=backup_harness.headers, json=_body()
    )
    record = _wait_for_terminal(backup_harness, response.json()["job"]["job_id"])

    assert record["status"] == "failed"
    assert record["error_code"] == "helper_unavailable"
    assert "secret" not in str(record)


def test_openapi_declares_bearer_and_no_restore_or_delete_routes(
    backup_harness: BackupHarness,
) -> None:
    schema = backup_harness.app.openapi()
    assert "DashboardBackupBearer" in schema["components"]["securitySchemes"]
    paths = set(schema["paths"])
    assert all("restore" not in path and "delete" not in path for path in paths)
    assert not any(
        method == "delete"
        for operations in schema["paths"].values()
        for method in operations
    )


def test_network_bind_configuration_is_exact() -> None:
    root = Path(__file__).parents[2]
    unit = (root / "deploy/systemd/linux-monitor-dashboard-backup.service").read_text(
        encoding="utf-8"
    )
    assert "--host ${DASHBOARD_BACKUP_HOST}" in unit
    assert "--port ${DASHBOARD_BACKUP_PORT}" in unit
    assert "0.0.0.0" not in unit
    assert "4045" in (
        root / "control_agent/dashboard-backup.env.example"
    ).read_text(encoding="utf-8")
