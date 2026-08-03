from __future__ import annotations

import importlib.util
import json
import subprocess
import time
from pathlib import Path
from uuid import uuid4

import pytest


@pytest.fixture
def helper_module():
    helper_path = Path(__file__).parents[2] / "deploy/scripts/linux-monitor-dashboard-backup-helper.py"
    spec = importlib.util.spec_from_file_location("dashboard_backup_helper_test", helper_path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_helper_request_accepts_only_internal_operation_plan_and_job(helper_module) -> None:
    request = {
        "operation": "run",
        "plan_id": "database",
        "job_id": str(uuid4()),
    }
    assert helper_module.validate_request(request) == request

    with pytest.raises(Exception):
        helper_module.validate_request({**request, "path": "/caller/controlled"})
    with pytest.raises(Exception):
        helper_module.validate_request({**request, "operation": "restore"})


def test_successful_database_dump_is_nonempty_inspected_and_checksummed(
    helper_module,
    monkeypatch,
    tmp_path: Path,
) -> None:
    step = {
        "type": "postgres_dump",
        "container": "example-postgres",
        "expected_compose_project": "example",
        "expected_compose_service": "database",
        "database": "example",
        "role": "postgres",
        "component": "database",
        "filename": "database.dump",
        "timeout_seconds": 60,
    }
    snapshot = tmp_path / "snapshot"
    snapshot.mkdir()
    calls: list[list[str]] = []

    monkeypatch.setattr(helper_module, "_verify_postgres_target", lambda _step: None)
    monkeypatch.setattr(helper_module, "_version_command", lambda arguments, deadline: "PostgreSQL 14.19")

    def fake_run(arguments, **kwargs):
        calls.append(arguments)
        if "/usr/bin/pg_dump" in arguments:
            kwargs["stdout"].write(b"PGDMP-test-payload")
        return subprocess.CompletedProcess(arguments, 0, stdout=b"", stderr=b"")

    monkeypatch.setattr(helper_module.subprocess, "run", fake_run)
    result = helper_module._execute_postgres_dump(
        step,
        snapshot,
        time.monotonic() + 30,
    )

    dump = snapshot / "database/database.dump"
    assert dump.read_bytes() == b"PGDMP-test-payload"
    assert len(result["artifacts"][0]["sha256"]) == 64
    assert any("/usr/bin/pg_restore" in call for call in calls)
    assert not any("password" in " ".join(call).lower() for call in calls)


def test_database_dump_verification_failure_is_terminal(
    helper_module,
    monkeypatch,
    tmp_path: Path,
) -> None:
    step = {
        "type": "postgres_dump",
        "container": "example-postgres",
        "expected_compose_project": "example",
        "expected_compose_service": "database",
        "database": "example",
        "role": "postgres",
        "component": "database",
        "filename": "database.dump",
        "timeout_seconds": 60,
    }
    snapshot = tmp_path / "snapshot"
    snapshot.mkdir()
    monkeypatch.setattr(helper_module, "_verify_postgres_target", lambda _step: None)
    monkeypatch.setattr(helper_module, "_version_command", lambda arguments, deadline: "PostgreSQL 14.19")

    def fake_run(arguments, **kwargs):
        if "/usr/bin/pg_dump" in arguments:
            kwargs["stdout"].write(b"PGDMP-test-payload")
            return subprocess.CompletedProcess(arguments, 0, stdout=b"", stderr=b"")
        return subprocess.CompletedProcess(arguments, 1, stdout=b"", stderr=b"private error")

    monkeypatch.setattr(helper_module.subprocess, "run", fake_run)

    with pytest.raises(helper_module.HelperFailure) as error:
        helper_module._execute_postgres_dump(step, snapshot, time.monotonic() + 30)
    assert error.value.code == "dump_verification_failed"
    assert "private" not in error.value.summary


def test_rsync_failure_is_sanitized_and_never_uses_destructive_flags(
    helper_module,
    monkeypatch,
    tmp_path: Path,
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    snapshot = tmp_path / "snapshot"
    snapshot.mkdir()
    observed: list[str] = []

    def fake_run(arguments, **kwargs):
        observed.extend(arguments)
        return subprocess.CompletedProcess(arguments, 23, stdout=b"", stderr=b"secret path")

    monkeypatch.setattr(helper_module.subprocess, "run", fake_run)
    step = {
        "type": "rsync_snapshot",
        "source": str(source),
        "component": "library",
        "excludes": [],
        "allow_source_root": False,
        "consistency": "best_effort_live",
    }

    with pytest.raises(helper_module.HelperFailure) as error:
        helper_module._execute_rsync(step, snapshot, time.monotonic() + 30)

    assert error.value.code == "rsync_failed"
    assert "--delete" not in observed
    assert all(isinstance(argument, str) for argument in observed)


def test_mount_validation_accepts_only_the_exact_writable_backup_bind(
    helper_module,
) -> None:
    cold_mount = Path("/mnt/storage")
    destination_root = cold_mount / "backups"
    cold_record = {
        "mount_point": cold_mount,
        "source": "/dev/md0",
        "filesystem": "ext4",
        # ProtectSystem may make the parent read-only in the service namespace.
        "options": {"ro", "noexec"},
        "super_options": {"rw"},
    }
    destination_record = {
        "mount_point": destination_root,
        "source": "/dev/md0",
        "filesystem": "ext4",
        "options": {"rw"},
        "super_options": {"rw"},
    }

    assert helper_module._mount_records_approved(
        cold_record,
        destination_record,
        cold_mount=cold_mount,
        destination_root=destination_root,
        raid_device="/dev/md0",
    )

    destination_record["options"] = {"ro"}
    assert not helper_module._mount_records_approved(
        cold_record,
        destination_record,
        cold_mount=cold_mount,
        destination_root=destination_root,
        raid_device="/dev/md0",
    )


def test_mount_validation_rejects_an_unexpected_device(helper_module) -> None:
    cold_mount = Path("/mnt/storage")
    record = {
        "mount_point": cold_mount,
        "source": "/dev/other",
        "filesystem": "ext4",
        "options": {"rw"},
        "super_options": {"rw"},
    }

    assert not helper_module._mount_records_approved(
        record,
        record,
        cold_mount=cold_mount,
        destination_root=cold_mount / "backups",
        raid_device="/dev/md0",
    )


def _copy_registry(helper_module, tmp_path: Path) -> tuple[dict, dict, Path, Path]:
    destination_root = tmp_path / "cold" / "backups"
    destination_root.mkdir(parents=True)
    source = tmp_path / "warm" / "config.yml"
    source.parent.mkdir()
    source.write_text("services: {}\n", encoding="utf-8")
    plan = {
        "id": "config",
        "display_name": "Configuration",
        "description": "Reviewed configuration backup.",
        "enabled": True,
        "destination": str(destination_root / "config"),
        "timeout_seconds": 600,
        "estimated_size_bytes": source.stat().st_size,
        "confirmation_level": "high",
        "retention": {"mode": "manual", "retain_at_least": 2},
        "steps": [
            {
                "type": "copy_files",
                "sources": [str(source)],
                "component": "configuration",
            },
            {"type": "verification", "mode": "sha256"},
            {"type": "manifest"},
        ],
    }
    registry = {
        "version": 1,
        "cold_mount": str(destination_root.parent),
        "destination_root": str(destination_root),
        "raid_device": "/dev/md0",
        "minimum_free_bytes": 1_073_741_824,
        "capacity_overhead_percent": 10,
        "plans": [plan],
    }
    return registry, plan, destination_root, source


def test_manifest_checksum_incomplete_marker_and_atomic_finalization(
    helper_module,
    monkeypatch,
    tmp_path: Path,
) -> None:
    registry, plan, destination_root, source = _copy_registry(helper_module, tmp_path)
    runtime = tmp_path / "runtime"
    monkeypatch.setattr(helper_module, "DESTINATION_ROOT", destination_root)
    monkeypatch.setattr(helper_module, "RUNTIME_ROOT", runtime)
    monkeypatch.setattr(
        helper_module,
        "_ensure_runtime_root",
        lambda: runtime.mkdir(mode=0o700, parents=True, exist_ok=True),
    )
    monkeypatch.setattr(helper_module, "_valid_root_directory", lambda metadata: True)
    monkeypatch.setattr(
        helper_module,
        "assess_plan",
        lambda registry, plan, write_probe, check_lock=False: {
            "allowed": True,
            "source_size_estimate": source.stat().st_size,
            "blocking_code": None,
            "blocking_reason": None,
        },
    )
    job_id = str(uuid4())
    result, exit_code = helper_module.run_backup(registry, plan, job_id)

    assert exit_code == 0
    assert result["status"] == "succeeded"
    snapshot = Path(result["destination_snapshot"])
    assert snapshot.is_dir()
    assert not (snapshot / "BACKUP_INCOMPLETE").exists()
    assert (snapshot / "BACKUP_COMPLETE").is_file()
    manifest_path = snapshot / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    completion = json.loads((snapshot / "BACKUP_COMPLETE").read_text(encoding="utf-8"))
    assert manifest["verification"]["state"] == "passed"
    assert manifest["checksums"]
    assert completion["manifest_sha256"] == helper_module._sha256(
        manifest_path, deadline=time.monotonic() + 10
    )
    assert snapshot.name.startswith("20")
    assert snapshot.stat().st_mode & 0o777 == 0o500


def test_failed_job_leaves_only_a_marked_incomplete_snapshot(
    helper_module,
    monkeypatch,
    tmp_path: Path,
) -> None:
    registry, plan, destination_root, source = _copy_registry(helper_module, tmp_path)
    monkeypatch.setattr(helper_module, "DESTINATION_ROOT", destination_root)
    runtime = tmp_path / "runtime"
    monkeypatch.setattr(helper_module, "RUNTIME_ROOT", runtime)
    monkeypatch.setattr(
        helper_module,
        "_ensure_runtime_root",
        lambda: runtime.mkdir(mode=0o700, parents=True, exist_ok=True),
    )
    monkeypatch.setattr(helper_module, "_valid_root_directory", lambda metadata: True)
    monkeypatch.setattr(
        helper_module,
        "assess_plan",
        lambda registry, plan, write_probe, check_lock=False: {
            "allowed": True,
            "source_size_estimate": source.stat().st_size,
            "blocking_code": None,
            "blocking_reason": None,
        },
    )
    monkeypatch.setattr(
        helper_module,
        "_execute_copy_files",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            helper_module.HelperFailure("copy_failed", "Configuration copy failed.")
        ),
    )
    job_id = str(uuid4())
    result, exit_code = helper_module.run_backup(registry, plan, job_id)

    incomplete = Path(plan["destination"]) / f".incomplete-{job_id}"
    assert exit_code == 1
    assert result["status"] == "failed"
    assert incomplete.is_dir()
    marker = json.loads((incomplete / "BACKUP_INCOMPLETE").read_text(encoding="utf-8"))
    assert marker["error_code"] == "copy_failed"
    assert not list(Path(plan["destination"]).glob("20*T*Z"))


def test_timeout_and_cancel_flags_are_bounded(helper_module) -> None:
    with pytest.raises(helper_module.BackupTimedOut):
        helper_module._check_cancel_or_timeout(time.monotonic() - 1)

    helper_module._cancel_requested = True
    try:
        with pytest.raises(helper_module.BackupCancelled):
            helper_module._check_cancel_or_timeout(time.monotonic() + 10)
    finally:
        helper_module._cancel_requested = False


def test_interrupted_helper_state_marks_incomplete_without_deleting_it(
    helper_module,
    monkeypatch,
    tmp_path: Path,
) -> None:
    registry, plan, _destination_root, _source = _copy_registry(helper_module, tmp_path)
    runtime = tmp_path / "runtime"
    runtime.mkdir(mode=0o700)
    monkeypatch.setattr(helper_module, "RUNTIME_ROOT", runtime)
    monkeypatch.setattr(helper_module, "_ensure_runtime_root", lambda: None)
    monkeypatch.setattr(helper_module, "_valid_state_metadata", lambda metadata: True)
    monkeypatch.setattr(
        helper_module,
        "_safe_unlink_state",
        lambda path: path.unlink(missing_ok=True),
    )
    job_id = str(uuid4())
    incomplete = Path(plan["destination"]) / f".incomplete-{job_id}"
    incomplete.mkdir(parents=True)
    (incomplete / "BACKUP_INCOMPLETE").write_text("{}\n", encoding="utf-8")
    final = Path(plan["destination"]) / "2026-01-01T000000Z"
    state_path = runtime / f"{job_id}.json"
    state_path.write_text(
        json.dumps(
            {
                "job_id": job_id,
                "plan_id": plan["id"],
                "pid": 999999,
                "pgid": 999999,
                "start_ticks": 1,
                "incomplete": str(incomplete),
                "final": str(final),
                "registry_fingerprint": helper_module.registry_fingerprint(registry),
            }
        ),
        encoding="utf-8",
    )
    state_path.chmod(0o600)

    assert helper_module.recover_interrupted_states(registry) == 1
    assert incomplete.is_dir()
    marker = json.loads((incomplete / "BACKUP_INCOMPLETE").read_text(encoding="utf-8"))
    assert marker["error_code"] == "service_interrupted"
    assert not state_path.exists()


def test_successful_snapshot_cannot_be_cancelled(
    helper_module,
    monkeypatch,
    tmp_path: Path,
) -> None:
    registry, plan, destination_root, _source = _copy_registry(helper_module, tmp_path)
    runtime = tmp_path / "runtime"
    runtime.mkdir(mode=0o700)
    monkeypatch.setattr(helper_module, "RUNTIME_ROOT", runtime)
    monkeypatch.setattr(helper_module, "_ensure_runtime_root", lambda: None)
    monkeypatch.setattr(helper_module, "_valid_state_metadata", lambda metadata: True)
    job_id = str(uuid4())
    incomplete = Path(plan["destination"]) / f".incomplete-{job_id}"
    incomplete.mkdir(parents=True)
    final = Path(plan["destination"]) / "2026-01-01T000000Z"
    final.mkdir()
    state = {
        "job_id": job_id,
        "plan_id": plan["id"],
        "pid": 999999,
        "pgid": 999999,
        "start_ticks": 1,
        "incomplete": str(incomplete),
        "final": str(final),
        "registry_fingerprint": helper_module.registry_fingerprint(registry),
    }
    state_path = runtime / f"{job_id}.json"
    state_path.write_text(json.dumps(state), encoding="utf-8")
    state_path.chmod(0o600)

    with pytest.raises(helper_module.HelperFailure) as error:
        helper_module.cancel_backup(registry, plan, job_id)
    assert error.value.code == "cancellation_not_safe"


def test_helper_and_unit_enforce_no_shell_or_source_writes() -> None:
    root = Path(__file__).parents[2]
    helper_source = (
        root / "deploy/scripts/linux-monitor-dashboard-backup-helper.py"
    ).read_text(encoding="utf-8")
    unit = (root / "deploy/systemd/linux-monitor-dashboard-backup.service").read_text(
        encoding="utf-8"
    )
    sudoers = (root / "deploy/sudoers/linux-monitor-dashboard-backup").read_text(
        encoding="utf-8"
    )

    assert "shell=True" not in helper_source
    assert "--delete" not in helper_source
    assert "ReadOnlyPaths=/mnt/warm" in unit
    assert " /usr/bin/rsync" not in sudoers
    assert " /usr/bin/docker" not in sudoers
    assert " ALL=(root) NOPASSWD: ALL" not in sudoers
