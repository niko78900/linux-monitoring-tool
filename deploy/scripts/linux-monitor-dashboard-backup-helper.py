#!/var/lib/homelab-venvs/linux-monitor-control-agent/bin/python
from __future__ import annotations

import fcntl
import hashlib
import json
import math
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import UUID

import yaml

REGISTRY_PATH = Path("/etc/linux-monitor/dashboard-backups.yml")
COLD_MOUNT = Path("/mnt/storage")
DESTINATION_ROOT = Path("/mnt/storage/backups")
RUNTIME_ROOT = Path("/run/linux-monitor-dashboard-backup-helper")
APPROVED_SOURCE_ROOTS = (
    Path("/mnt/warm"),
    Path("/etc/linux-monitor"),
    Path("/etc/systemd/system"),
    Path("/etc/ufw"),
    Path("/opt/homelab"),
)
FORBIDDEN_POSTGRES_ROOTS: tuple[Path, ...] = ()

DOCKER_BINARY = "/usr/bin/docker"
RSYNC_BINARY = "/usr/bin/rsync"
DU_BINARY = "/usr/bin/du"
HELPER_PATH = "/usr/local/libexec/linux-monitor-dashboard-backup-helper"
MAX_INPUT_BYTES = 4096
MAX_REGISTRY_BYTES = 262_144
SAFE_ENV = {"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL": "C"}

ID_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")
TARGET_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.@-]{0,127}$")
FILENAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
SAFE_GLOB_PATTERN = re.compile(r"^[A-Za-z0-9_./*?\[\]-]{1,160}$")
SHELL_METACHARACTERS = frozenset("$`;&|><\\\n\r\x00")
OPERATIONS = {"validate", "assess", "preflight", "run", "cancel"}
STEP_TYPES = {"rsync_snapshot", "postgres_dump", "copy_files", "verification", "manifest"}

_cancel_requested = False


class HelperFailure(RuntimeError):
    def __init__(self, code: str, summary: str, *, status_value: str = "failed"):
        super().__init__(summary)
        self.code = code
        self.summary = summary
        self.status_value = status_value


class BackupCancelled(HelperFailure):
    def __init__(self):
        super().__init__("cancelled_by_operator", "Backup cancelled by the operator.", status_value="cancelled")


class BackupTimedOut(HelperFailure):
    def __init__(self):
        super().__init__("backup_timeout", "Backup exceeded its execution deadline.", status_value="timed_out")


def load_registry(path: Path = REGISTRY_PATH, *, enforce_metadata: bool = True) -> dict[str, Any]:
    if not path.is_absolute():
        raise HelperFailure("registry_invalid", "Backup registry validation failed.", status_value="rejected")
    try:
        metadata = path.lstat()
        parent = path.parent.stat()
    except OSError as error:
        raise HelperFailure("registry_unavailable", "Backup registry is unavailable.", status_value="rejected") from error
    if metadata.st_size > MAX_REGISTRY_BYTES:
        raise HelperFailure("registry_invalid", "Backup registry validation failed.", status_value="rejected")
    if enforce_metadata and (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_gid != 0
        or stat.S_IMODE(metadata.st_mode) != 0o600
        or not stat.S_ISDIR(parent.st_mode)
        or parent.st_uid != 0
        or parent.st_gid != 0
        or stat.S_IMODE(parent.st_mode) & 0o022
    ):
        raise HelperFailure("registry_permissions", "Backup registry permissions are invalid.", status_value="rejected")
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, yaml.YAMLError) as error:
        raise HelperFailure("registry_invalid", "Backup registry validation failed.", status_value="rejected") from error
    return validate_registry(payload)


def validate_registry(
    payload: object,
    *,
    check_paths: bool = True,
    expected_cold_mount: Path = COLD_MOUNT,
    expected_destination_root: Path = DESTINATION_ROOT,
    approved_source_roots: tuple[Path, ...] = APPROVED_SOURCE_ROOTS,
    forbidden_postgres_roots: tuple[Path, ...] = FORBIDDEN_POSTGRES_ROOTS,
) -> dict[str, Any]:
    try:
        document = _strict_dict(
            payload,
            {
                "version",
                "cold_mount",
                "destination_root",
                "raid_device",
                "minimum_free_bytes",
                "capacity_overhead_percent",
                "plans",
            },
        )
        if document["version"] != 1:
            raise ValueError("version")
        cold_mount = _absolute_path(document["cold_mount"])
        destination_root = _absolute_path(document["destination_root"])
        raid_device = _absolute_path(document["raid_device"])
        if cold_mount.resolve(strict=check_paths) != expected_cold_mount.resolve(strict=check_paths):
            raise ValueError("cold mount")
        if destination_root.resolve(strict=False) != expected_destination_root.resolve(strict=False):
            raise ValueError("destination root")
        if destination_root.resolve(strict=False).parent != cold_mount.resolve(strict=check_paths):
            raise ValueError("destination layout")
        if not re.fullmatch(r"/dev/md[0-9]+", str(raid_device)):
            raise ValueError("raid")
        minimum_free = _strict_int(document["minimum_free_bytes"], 1_073_741_824, 2_199_023_255_552)
        overhead = _strict_int(document["capacity_overhead_percent"], 0, 100)
        plans_raw = document["plans"]
        if not isinstance(plans_raw, list) or not 1 <= len(plans_raw) <= 32:
            raise ValueError("plans")
        plans = [
            _validate_plan(
                item,
                destination_root=destination_root,
                approved_source_roots=approved_source_roots,
                forbidden_postgres_roots=forbidden_postgres_roots,
                check_paths=check_paths,
            )
            for item in plans_raw
        ]
        identifiers = [plan["id"] for plan in plans]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError("duplicates")
        return {
            "version": 1,
            "cold_mount": str(cold_mount),
            "destination_root": str(destination_root),
            "raid_device": str(raid_device),
            "minimum_free_bytes": minimum_free,
            "capacity_overhead_percent": overhead,
            "plans": plans,
        }
    except (KeyError, OSError, TypeError, ValueError) as error:
        raise HelperFailure("registry_invalid", "Backup registry validation failed.", status_value="rejected") from error


def _validate_plan(
    payload: object,
    *,
    destination_root: Path,
    approved_source_roots: tuple[Path, ...],
    forbidden_postgres_roots: tuple[Path, ...],
    check_paths: bool,
) -> dict[str, Any]:
    document = _strict_dict(
        payload,
        {
            "id",
            "display_name",
            "description",
            "enabled",
            "disabled_reason",
            "destination",
            "timeout_seconds",
            "estimated_size_bytes",
            "confirmation_level",
            "retention",
            "steps",
        },
        optional={"disabled_reason"},
    )
    plan_id = _identifier(document["id"])
    display_name = _human_text(document["display_name"], maximum=80)
    description = _human_text(document["description"], maximum=300)
    if not isinstance(document["enabled"], bool):
        raise ValueError("enabled")
    disabled_reason_raw = document.get("disabled_reason")
    disabled_reason = (
        _human_text(disabled_reason_raw, maximum=240)
        if disabled_reason_raw is not None
        else None
    )
    if document["enabled"] and disabled_reason is not None:
        raise ValueError("disabled reason")
    if not document["enabled"] and disabled_reason is None:
        raise ValueError("disabled reason")
    destination = _absolute_path(document["destination"])
    if destination.resolve(strict=False).parent != destination_root.resolve(strict=False) or destination.name != plan_id:
        raise ValueError("destination")
    if _has_symlink(destination, require_leaf=False):
        raise ValueError("destination symlink")
    timeout = _strict_int(document["timeout_seconds"], 60, 604_800)
    estimated_size = _strict_int(document["estimated_size_bytes"], 1, 10_000_000_000_000)
    if document["confirmation_level"] != "high":
        raise ValueError("confirmation")
    retention_raw = _strict_dict(document["retention"], {"mode", "retain_at_least"})
    if retention_raw["mode"] != "manual":
        raise ValueError("retention")
    retention = {
        "mode": "manual",
        "retain_at_least": _strict_int(retention_raw["retain_at_least"], 1, 1000),
    }
    steps_raw = document["steps"]
    if not isinstance(steps_raw, list) or not 3 <= len(steps_raw) <= 32:
        raise ValueError("steps")
    steps = [
        _validate_step(
            step,
            destination_root=destination_root,
            approved_source_roots=approved_source_roots,
            forbidden_postgres_roots=forbidden_postgres_roots,
            check_paths=check_paths,
        )
        for step in steps_raw
    ]
    types = [step["type"] for step in steps]
    if types.count("verification") != 1 or types.count("manifest") != 1:
        raise ValueError("required steps")
    if types[-2:] != ["verification", "manifest"] or any(
        value in {"verification", "manifest"} for value in types[:-2]
    ):
        raise ValueError("step order")
    components = [step["component"] for step in steps if "component" in step]
    if len(components) != len(set(components)):
        raise ValueError("components")
    return {
        "id": plan_id,
        "display_name": display_name,
        "description": description,
        "enabled": document["enabled"],
        "disabled_reason": disabled_reason,
        "destination": str(destination),
        "timeout_seconds": timeout,
        "estimated_size_bytes": estimated_size,
        "confirmation_level": "high",
        "retention": retention,
        "steps": steps,
    }


def _validate_step(
    payload: object,
    *,
    destination_root: Path,
    approved_source_roots: tuple[Path, ...],
    forbidden_postgres_roots: tuple[Path, ...],
    check_paths: bool,
) -> dict[str, Any]:
    if not isinstance(payload, dict) or payload.get("type") not in STEP_TYPES:
        raise ValueError("step type")
    step_type = payload["type"]
    if step_type == "rsync_snapshot":
        document = _strict_dict(
            payload,
            {"type", "source", "component", "excludes", "allow_source_root", "consistency"},
            optional={"excludes", "allow_source_root", "consistency"},
        )
        source = _absolute_path(document["source"])
        component = _identifier(document["component"])
        excludes_raw = document.get("excludes", [])
        if not isinstance(excludes_raw, list) or len(excludes_raw) > 128:
            raise ValueError("excludes")
        excludes: list[str] = []
        for value in excludes_raw:
            if (
                not isinstance(value, str)
                or not SAFE_GLOB_PATTERN.fullmatch(value)
                or value.startswith("/")
                or ".." in Path(value).parts
                or any(character in SHELL_METACHARACTERS for character in value)
            ):
                raise ValueError("exclude")
            excludes.append(value)
        if len(excludes) != len(set(excludes)):
            raise ValueError("exclude duplicates")
        allow_source_root = document.get("allow_source_root", False)
        if not isinstance(allow_source_root, bool):
            raise ValueError("source root approval")
        consistency = document.get("consistency", "point_in_time")
        if consistency not in {"point_in_time", "best_effort_live"}:
            raise ValueError("consistency")
        _validate_source(
            source,
            destination_root=destination_root,
            approved_source_roots=approved_source_roots,
            forbidden_postgres_roots=forbidden_postgres_roots,
            check_paths=check_paths,
            require_directory=True,
            allow_source_root=allow_source_root,
        )
        return {
            "type": "rsync_snapshot",
            "source": str(source),
            "component": component,
            "excludes": excludes,
            "allow_source_root": allow_source_root,
            "consistency": consistency,
        }
    if step_type == "postgres_dump":
        document = _strict_dict(
            payload,
            {
                "type",
                "container",
                "expected_compose_project",
                "expected_compose_service",
                "database",
                "role",
                "component",
                "filename",
                "timeout_seconds",
            },
            optional={"component", "filename", "timeout_seconds"},
        )
        filename = document.get("filename", "database.dump")
        if not isinstance(filename, str) or not FILENAME_PATTERN.fullmatch(filename):
            raise ValueError("filename")
        return {
            "type": "postgres_dump",
            "container": _target(document["container"]),
            "expected_compose_project": _target(document["expected_compose_project"]),
            "expected_compose_service": _target(document["expected_compose_service"]),
            "database": _target(document["database"]),
            "role": _target(document["role"]),
            "component": _identifier(document.get("component", "database")),
            "filename": filename,
            "timeout_seconds": _strict_int(document.get("timeout_seconds", 1800), 30, 86_400),
        }
    if step_type == "copy_files":
        document = _strict_dict(payload, {"type", "sources", "component"})
        sources_raw = document["sources"]
        if not isinstance(sources_raw, list) or not 1 <= len(sources_raw) <= 256:
            raise ValueError("copy sources")
        sources = [_absolute_path(value) for value in sources_raw]
        if len(sources) != len(set(sources)):
            raise ValueError("copy source duplicates")
        for source in sources:
            _validate_source(
                source,
                destination_root=destination_root,
                approved_source_roots=approved_source_roots,
                forbidden_postgres_roots=forbidden_postgres_roots,
                check_paths=check_paths,
                require_directory=False,
                allow_source_root=False,
            )
        return {
            "type": "copy_files",
            "sources": [str(source) for source in sources],
            "component": _identifier(document["component"]),
        }
    if step_type == "verification":
        document = _strict_dict(payload, {"type", "mode"}, optional={"mode"})
        mode = document.get("mode", "sha256")
        if mode not in {"sha256", "inventory"}:
            raise ValueError("verification")
        return {"type": "verification", "mode": mode}
    _strict_dict(payload, {"type"})
    return {"type": "manifest"}


def _validate_source(
    source: Path,
    *,
    destination_root: Path,
    approved_source_roots: tuple[Path, ...],
    forbidden_postgres_roots: tuple[Path, ...],
    check_paths: bool,
    require_directory: bool,
    allow_source_root: bool,
) -> None:
    if _has_symlink(source, require_leaf=check_paths):
        raise ValueError("source symlink")
    resolved = source.resolve(strict=check_paths)
    approved = [root.resolve(strict=check_paths) for root in approved_source_roots]
    matches = [root for root in approved if _within(resolved, root)]
    if not matches or (resolved in matches and not allow_source_root):
        raise ValueError("source root")
    if _overlaps(resolved, destination_root.resolve(strict=False)):
        raise ValueError("overlap")
    if any(_overlaps(resolved, root.resolve(strict=False)) for root in forbidden_postgres_roots):
        raise ValueError("postgres data")
    if _is_postgres_data_path(resolved):
        raise ValueError("postgres data")
    if check_paths:
        if require_directory and not resolved.is_dir():
            raise ValueError("directory source")
        if not require_directory and not resolved.is_file():
            raise ValueError("file source")


def registry_fingerprint(registry: dict[str, Any]) -> str:
    encoded = json.dumps(registry, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def validate_request(payload: object) -> dict[str, str]:
    document = _strict_dict(payload, {"operation", "plan_id", "job_id"})
    operation = document["operation"]
    plan_id = document["plan_id"]
    job_id = document["job_id"]
    if operation not in OPERATIONS or not isinstance(plan_id, str) or not ID_PATTERN.fullmatch(plan_id):
        raise HelperFailure("request_invalid", "Backup helper request is invalid.", status_value="rejected")
    if not isinstance(job_id, str):
        raise HelperFailure("request_invalid", "Backup helper request is invalid.", status_value="rejected")
    try:
        parsed = UUID(job_id)
    except ValueError as error:
        raise HelperFailure("request_invalid", "Backup helper request is invalid.", status_value="rejected") from error
    if str(parsed) != job_id:
        raise HelperFailure("request_invalid", "Backup helper request is invalid.", status_value="rejected")
    return {"operation": operation, "plan_id": plan_id, "job_id": job_id}


def assess_plan(
    registry: dict[str, Any],
    plan: dict[str, Any],
    *,
    write_probe: bool,
    check_lock: bool = True,
) -> dict[str, Any]:
    mounted, writable, raid_healthy, free_bytes = _storage_state(registry, write_probe=write_probe)
    blocking_code: str | None = None
    blocking_reason: str | None = None
    if not plan["enabled"]:
        blocking_code = "plan_disabled"
        blocking_reason = plan["disabled_reason"]
    elif not mounted:
        blocking_code = "cold_storage_unavailable"
        blocking_reason = "Cold backup storage is not mounted at the approved location."
    elif not raid_healthy:
        blocking_code = "raid_unhealthy"
        blocking_reason = "Cold-storage RAID is not healthy."
    elif not writable:
        blocking_code = "cold_storage_read_only"
        blocking_reason = "Cold backup storage is not writable."

    source_size = plan["estimated_size_bytes"]
    if blocking_code is None or blocking_code == "plan_disabled":
        try:
            _verify_required_tools(plan)
            _verify_postgres_targets(plan)
            source_size = _estimate_plan(plan)
            if check_lock and _plan_locked(plan["id"]):
                if blocking_code is None:
                    blocking_code = "plan_busy"
                    blocking_reason = "This backup plan already has an active job."
        except HelperFailure as error:
            if blocking_code is None:
                blocking_code = error.code
                blocking_reason = error.summary

    required_bytes = math.ceil(
        source_size * (100 + registry["capacity_overhead_percent"]) / 100
    ) + registry["minimum_free_bytes"]
    if blocking_code is None and free_bytes < required_bytes:
        blocking_code = "insufficient_capacity"
        blocking_reason = "Cold storage does not have enough free capacity for this backup."
    return {
        "kind": "assessment",
        "status": "succeeded",
        "registry_fingerprint": registry_fingerprint(registry),
        "allowed": blocking_code is None,
        "blocking_code": blocking_code,
        "blocking_reason": blocking_reason,
        "source_size_estimate": source_size,
        "destination_free_bytes": free_bytes,
        "required_bytes": required_bytes,
        "cold_storage_mounted": mounted,
        "cold_storage_writable": writable,
        "raid_healthy": raid_healthy,
    }


def run_backup(registry: dict[str, Any], plan: dict[str, Any], job_id: str) -> tuple[dict[str, Any], int]:
    global _cancel_requested
    _cancel_requested = False
    if not plan["enabled"]:
        return _result(
            registry,
            status_value="rejected",
            summary=plan["disabled_reason"],
            error_code="plan_disabled",
            verification_state="not_applicable",
        ), 4
    _ensure_runtime_root()
    lock_path = RUNTIME_ROOT / f"plan-{plan['id']}.lock"
    lock_handle = lock_path.open("a+", encoding="utf-8")
    os.chmod(lock_path, 0o600)
    try:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_handle.close()
        return _result(
            registry,
            status_value="rejected",
            summary="This backup plan already has an active job.",
            error_code="plan_busy",
            verification_state="not_applicable",
        ), 4

    plan_directory = Path(plan["destination"])
    incomplete = plan_directory / f".incomplete-{job_id}"
    final_directory: Path | None = None
    state_path = RUNTIME_ROOT / f"{job_id}.json"
    started_at = _utc_timestamp()
    deadline = time.monotonic() + plan["timeout_seconds"]
    counters = {
        "files_examined": 0,
        "files_copied": 0,
        "bytes_examined": 0,
        "bytes_copied": 0,
    }
    artifacts: list[dict[str, Any]] = []
    components: list[dict[str, Any]] = []
    postgres_metadata: list[dict[str, Any]] = []
    consistency_notes: list[str] = []
    verification_state = "failed"
    try:
        assessment = assess_plan(registry, plan, write_probe=True, check_lock=False)
        if not assessment["allowed"]:
            raise HelperFailure(
                assessment["blocking_code"] or "unsafe_to_start",
                assessment["blocking_reason"] or "Backup safety preflight rejected the job.",
                status_value="rejected",
            )
        plan_directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(plan_directory, 0o700)
        plan_metadata = plan_directory.lstat()
        if (
            plan_directory.is_symlink()
            or plan_directory.resolve().parent != DESTINATION_ROOT.resolve()
            or not _valid_root_directory(plan_metadata)
        ):
            raise HelperFailure("destination_invalid", "Backup destination validation failed.", status_value="rejected")
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
        final_directory = plan_directory / timestamp
        if incomplete.exists() or final_directory.exists():
            raise HelperFailure("snapshot_exists", "Backup snapshot destination already exists.", status_value="rejected")
        incomplete.mkdir(mode=0o700)
        _write_json_file(
            incomplete / "BACKUP_INCOMPLETE",
            {"job_id": job_id, "plan_id": plan["id"], "status": "running", "started_at": started_at},
            exclusive=True,
        )
        _write_state_file(
            state_path,
            registry=registry,
            plan=plan,
            job_id=job_id,
            incomplete=incomplete,
            final_directory=final_directory,
        )
        _install_signal_handlers()
        _emit_progress(registry, phase="running", progress_percent=0.0, **counters)

        data_steps = plan["steps"][:-2]
        for index, step in enumerate(data_steps, start=1):
            _check_cancel_or_timeout(deadline)
            if step["type"] == "postgres_dump":
                result = _execute_postgres_dump(step, incomplete, deadline)
                artifacts.extend(result["artifacts"])
                components.append(result["component"])
                postgres_metadata.append(result["postgres"])
                _merge_counters(counters, result["counters"])
            elif step["type"] == "rsync_snapshot":
                result = _execute_rsync(step, incomplete, deadline)
                components.append(result["component"])
                _merge_counters(counters, result["counters"])
                if step["consistency"] == "best_effort_live":
                    consistency_notes.append(
                        f"{step['component']} is a best-effort live snapshot; application writes were not quiesced."
                    )
            elif step["type"] == "copy_files":
                result = _execute_copy_files(step, incomplete, deadline)
                artifacts.extend(result["artifacts"])
                components.append(result["component"])
                _merge_counters(counters, result["counters"])
            else:
                raise HelperFailure("registry_invalid", "Backup registry validation failed.", status_value="rejected")
            progress = min(80.0, index / len(data_steps) * 80.0)
            _emit_progress(registry, phase="running", progress_percent=progress, **counters)

        _check_cancel_or_timeout(deadline)
        _emit_progress(registry, phase="verifying", progress_percent=85.0, **counters)
        verification_mode = plan["steps"][-2]["mode"]
        verification = _verify_snapshot(
            incomplete,
            artifacts=artifacts,
            mode=verification_mode,
            deadline=deadline,
        )
        verification_state = "passed"
        _emit_progress(registry, phase="verifying", progress_percent=95.0, **counters)
        completed_at = _utc_timestamp()
        manifest = {
            "schema_version": 1,
            "job_id": job_id,
            "plan_id": plan["id"],
            "display_name": plan["display_name"],
            "started_at": started_at,
            "completed_at": completed_at,
            "snapshot_name": final_directory.name,
            "source_size_estimate": assessment["source_size_estimate"],
            "components": components,
            "postgresql": postgres_metadata,
            "checksums": verification["checksums"],
            "verification": {
                "state": "passed",
                "mode": verification_mode,
                "regular_files": verification["regular_files"],
                "symlinks": verification["symlinks"],
                "bytes": verification["bytes"],
            },
            "counters": counters,
            "consistency_notes": consistency_notes,
            "metadata_policy": {
                "source_filesystem_note": (
                    "NTFS/FUSE sources do not provide reliable Unix ownership or ACL preservation."
                ),
                "preserved": ["file content", "relative path", "modification time"],
                "not_preserved": ["source ownership", "source group", "source ACLs", "source Unix mode"],
                "destination_permissions": "root-only directories and files",
            },
            "retention": {
                "mode": plan["retention"]["mode"],
                "retain_at_least": plan["retention"]["retain_at_least"],
                "automatic_snapshot_deletion": False,
            },
        }
        manifest_path = incomplete / "manifest.json"
        _write_json_file(manifest_path, manifest, exclusive=True)
        manifest_checksum = _sha256(manifest_path, deadline=deadline)
        _check_cancel_or_timeout(deadline)
        (incomplete / "BACKUP_INCOMPLETE").unlink()
        _write_json_file(
            incomplete / "BACKUP_COMPLETE",
            {
                "job_id": job_id,
                "plan_id": plan["id"],
                "completed_at": completed_at,
                "manifest_sha256": manifest_checksum,
            },
            exclusive=True,
        )
        _make_snapshot_read_only(incomplete)
        _fsync_directory(incomplete)
        if final_directory.exists():
            raise HelperFailure("snapshot_exists", "Backup snapshot destination already exists.")
        os.rename(incomplete, final_directory)
        _fsync_directory(plan_directory)
        _safe_unlink_state(state_path)
        result = _result(
            registry,
            status_value="succeeded",
            summary="Backup completed and verification passed.",
            error_code=None,
            verification_state="passed",
            destination_snapshot=str(final_directory),
            manifest_path=str(final_directory / "manifest.json"),
            **counters,
        )
        return result, 0
    except HelperFailure as error:
        if incomplete.exists() and incomplete.is_dir():
            _mark_incomplete(incomplete, job_id=job_id, plan_id=plan["id"], error=error)
        _safe_unlink_state(state_path)
        exit_code = 2 if error.status_value == "cancelled" else 3 if error.status_value == "timed_out" else 4 if error.status_value == "rejected" else 1
        return _result(
            registry,
            status_value=error.status_value,
            summary=error.summary,
            error_code=error.code,
            verification_state="not_applicable" if error.status_value == "rejected" else verification_state,
            destination_snapshot=str(incomplete) if incomplete.is_dir() else None,
            **counters,
        ), exit_code
    except Exception:
        failure = HelperFailure("backup_failed", "Backup failed inside the privileged helper.")
        if incomplete.exists() and incomplete.is_dir():
            _mark_incomplete(incomplete, job_id=job_id, plan_id=plan["id"], error=failure)
        _safe_unlink_state(state_path)
        return _result(
            registry,
            status_value="failed",
            summary=failure.summary,
            error_code=failure.code,
            verification_state="failed",
            destination_snapshot=str(incomplete) if incomplete.is_dir() else None,
            **counters,
        ), 1
    finally:
        try:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        finally:
            lock_handle.close()


def cancel_backup(registry: dict[str, Any], plan: dict[str, Any], job_id: str) -> dict[str, Any]:
    _ensure_runtime_root()
    state_path = RUNTIME_ROOT / f"{job_id}.json"
    if not state_path.exists():
        return {
            "kind": "cancellation",
            "status": "succeeded",
            "registry_fingerprint": registry_fingerprint(registry),
            "signal_sent": False,
        }
    metadata = state_path.lstat()
    if not _valid_state_metadata(metadata):
        raise HelperFailure("cancellation_state_invalid", "Backup cancellation state is invalid.")
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise HelperFailure("cancellation_state_invalid", "Backup cancellation state is invalid.") from error
    expected_keys = {
        "job_id",
        "plan_id",
        "pid",
        "pgid",
        "start_ticks",
        "incomplete",
        "final",
        "registry_fingerprint",
    }
    if not isinstance(state, dict) or set(state) != expected_keys:
        raise HelperFailure("cancellation_state_invalid", "Backup cancellation state is invalid.")
    if (
        state["job_id"] != job_id
        or state["plan_id"] != plan["id"]
        or state["registry_fingerprint"] != registry_fingerprint(registry)
    ):
        raise HelperFailure("cancellation_state_invalid", "Backup cancellation state is invalid.")
    incomplete = Path(state["incomplete"])
    final = Path(state["final"])
    expected_incomplete = Path(plan["destination"]) / f".incomplete-{job_id}"
    if (
        incomplete != expected_incomplete
        or incomplete.resolve(strict=False).parent != Path(plan["destination"]).resolve(strict=False)
        or final.parent != Path(plan["destination"])
        or final.exists()
        or not incomplete.is_dir()
    ):
        raise HelperFailure("cancellation_not_safe", "Backup is no longer safe to cancel.")
    pid = _strict_int(state["pid"], 2, 2_147_483_647)
    pgid = _strict_int(state["pgid"], 2, 2_147_483_647)
    start_ticks = _strict_int(state["start_ticks"], 1, 9_223_372_036_854_775_807)
    if pgid == os.getpgrp():
        raise HelperFailure("cancellation_not_safe", "Backup cancellation target is invalid.")
    try:
        process_stat = _read_process_stat(pid)
        command_line = (Path("/proc") / str(pid) / "cmdline").read_bytes().split(b"\x00")
    except OSError as error:
        raise HelperFailure("cancellation_not_running", "Backup process is no longer running.") from error
    if (
        process_stat["pgid"] != pgid
        or process_stat["start_ticks"] != start_ticks
        or not any(HELPER_PATH.encode("utf-8") == value for value in command_line)
    ):
        raise HelperFailure("cancellation_not_safe", "Backup cancellation target is invalid.")
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        return {
            "kind": "cancellation",
            "status": "succeeded",
            "registry_fingerprint": registry_fingerprint(registry),
            "signal_sent": False,
        }
    return {
        "kind": "cancellation",
        "status": "succeeded",
        "registry_fingerprint": registry_fingerprint(registry),
        "signal_sent": True,
    }


def recover_interrupted_states(registry: dict[str, Any]) -> int:
    """Mark only stale helper-owned incomplete jobs; never remove their data."""
    _ensure_runtime_root()
    recovered = 0
    plans = {plan["id"]: plan for plan in registry["plans"]}
    for state_path in sorted(RUNTIME_ROOT.glob("*.json")):
        try:
            job_id = state_path.stem
            if str(UUID(job_id)) != job_id:
                continue
            metadata = state_path.lstat()
            if not _valid_state_metadata(metadata):
                continue
            state = json.loads(state_path.read_text(encoding="utf-8"))
            if not isinstance(state, dict):
                continue
            plan = plans.get(state.get("plan_id"))
            if plan is None or state.get("job_id") != job_id:
                continue
            pid = state.get("pid")
            start_ticks = state.get("start_ticks")
            process_is_current = False
            if isinstance(pid, int) and isinstance(start_ticks, int):
                try:
                    process_is_current = _read_process_stat(pid)["start_ticks"] == start_ticks
                except OSError:
                    process_is_current = False
            if process_is_current:
                continue
            incomplete = Path(str(state.get("incomplete", "")))
            final = Path(str(state.get("final", "")))
            expected = Path(plan["destination"]) / f".incomplete-{job_id}"
            if (
                incomplete == expected
                and incomplete.is_dir()
                and incomplete.resolve(strict=False).parent
                == Path(plan["destination"]).resolve(strict=False)
                and final.parent == Path(plan["destination"])
                and not final.exists()
            ):
                _mark_incomplete(
                    incomplete,
                    job_id=job_id,
                    plan_id=plan["id"],
                    error=HelperFailure(
                        "service_interrupted",
                        "Backup service restarted before completion.",
                    ),
                )
                _safe_unlink_state(state_path)
                recovered += 1
        except (OSError, TypeError, ValueError, json.JSONDecodeError):
            continue
    return recovered


def _execute_postgres_dump(step: dict[str, Any], snapshot: Path, deadline: float) -> dict[str, Any]:
    _verify_postgres_target(step)
    component_dir = snapshot / step["component"]
    component_dir.mkdir(mode=0o700)
    destination = component_dir / step["filename"]
    postgres_version = _version_command(
        [DOCKER_BINARY, "exec", step["container"], "/usr/lib/postgresql/14/bin/postgres", "--version"],
        deadline=deadline,
    )
    dump_version = _version_command(
        [DOCKER_BINARY, "exec", step["container"], "/usr/bin/pg_dump", "--version"],
        deadline=deadline,
    )
    timeout = min(step["timeout_seconds"], _remaining_seconds(deadline))
    arguments = [
        DOCKER_BINARY,
        "exec",
        step["container"],
        "/usr/bin/pg_dump",
        "-U",
        step["role"],
        "-d",
        step["database"],
        "--format=custom",
        "--no-owner",
        "--no-privileges",
    ]
    try:
        with destination.open("xb") as output:
            result = subprocess.run(
                arguments,
                stdin=subprocess.DEVNULL,
                stdout=output,
                stderr=subprocess.PIPE,
                timeout=timeout,
                check=False,
                env=SAFE_ENV,
            )
    except subprocess.TimeoutExpired as error:
        raise BackupTimedOut() from error
    _check_cancel_or_timeout(deadline)
    if result.returncode != 0:
        raise HelperFailure("postgres_dump_failed", "PostgreSQL logical dump failed.")
    os.chmod(destination, 0o600)
    size = destination.stat().st_size
    if size <= 0:
        raise HelperFailure("postgres_dump_empty", "PostgreSQL logical dump was empty.")
    try:
        with destination.open("rb") as dump_input:
            verification = subprocess.run(
                [DOCKER_BINARY, "exec", "-i", step["container"], "/usr/bin/pg_restore", "--list"],
                stdin=dump_input,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=min(step["timeout_seconds"], _remaining_seconds(deadline)),
                check=False,
                env=SAFE_ENV,
            )
    except subprocess.TimeoutExpired as error:
        raise BackupTimedOut() from error
    _check_cancel_or_timeout(deadline)
    if verification.returncode != 0:
        raise HelperFailure("dump_verification_failed", "PostgreSQL dump inspection failed.")
    checksum = _sha256(destination, deadline=deadline)
    relative_path = destination.relative_to(snapshot).as_posix()
    return {
        "artifacts": [
            {
                "relative_path": relative_path,
                "source": "postgresql-logical-dump",
                "size": size,
                "sha256": checksum,
            }
        ],
        "component": {"name": step["component"], "type": "postgres_dump", "files": 1, "bytes": size},
        "postgres": {
            "component": step["component"],
            "database": step["database"],
            "role": step["role"],
            "server_version": postgres_version,
            "dump_tool_version": dump_version,
            "format": "custom",
            "inspection": "pg_restore --list",
            "sha256": checksum,
        },
        "counters": {
            "files_examined": 1,
            "files_copied": 1,
            "bytes_examined": size,
            "bytes_copied": size,
        },
    }


def _execute_rsync(step: dict[str, Any], snapshot: Path, deadline: float) -> dict[str, Any]:
    source = Path(step["source"])
    component_dir = snapshot / step["component"]
    component_dir.mkdir(mode=0o700)
    arguments = [
        RSYNC_BINARY,
        "--archive",
        "--no-owner",
        "--no-group",
        "--no-perms",
        "--no-devices",
        "--no-specials",
        "--safe-links",
        "--chmod=Du=rwx,Dgo=,Fu=rw,Fgo=",
        "--stats",
    ]
    for exclusion in step["excludes"]:
        arguments.extend(["--exclude", exclusion])
    arguments.extend([f"{source}/", f"{component_dir}/"])
    try:
        result = subprocess.run(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=_remaining_seconds(deadline),
            check=False,
            env=SAFE_ENV,
        )
    except subprocess.TimeoutExpired as error:
        raise BackupTimedOut() from error
    _check_cancel_or_timeout(deadline)
    if result.returncode != 0:
        raise HelperFailure("rsync_failed", "Rsync snapshot failed.")
    try:
        output = result.stdout.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise HelperFailure("rsync_output_invalid", "Rsync returned invalid statistics.") from error
    files = _parse_rsync_stat(output, "Number of regular files transferred")
    examined = _parse_rsync_stat(output, "Number of files")
    total_bytes = _parse_rsync_stat(output, "Total file size")
    copied_bytes = _parse_rsync_stat(output, "Total transferred file size")
    return {
        "component": {
            "name": step["component"],
            "type": "rsync_snapshot",
            "files": files,
            "bytes": copied_bytes,
            "source_bytes_examined": total_bytes,
            "consistency": step["consistency"],
        },
        "counters": {
            "files_examined": examined,
            "files_copied": files,
            "bytes_examined": total_bytes,
            "bytes_copied": copied_bytes,
        },
    }


def _execute_copy_files(step: dict[str, Any], snapshot: Path, deadline: float) -> dict[str, Any]:
    component_dir = snapshot / step["component"]
    component_dir.mkdir(mode=0o700)
    artifacts: list[dict[str, Any]] = []
    total_bytes = 0
    for source_value in step["sources"]:
        _check_cancel_or_timeout(deadline)
        source = Path(source_value)
        if source.is_symlink() or not source.is_file():
            raise HelperFailure("source_invalid", "A configured backup source is unavailable.", status_value="rejected")
        relative_source = Path(*source.parts[1:])
        destination = component_dir / "rootfs" / relative_source
        destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with source.open("rb") as input_file, destination.open("xb") as output_file:
            shutil.copyfileobj(input_file, output_file, length=1024 * 1024)
            output_file.flush()
            os.fsync(output_file.fileno())
        source_stat = source.stat()
        os.utime(destination, ns=(source_stat.st_atime_ns, source_stat.st_mtime_ns))
        os.chmod(destination, 0o600)
        size = destination.stat().st_size
        checksum = _sha256(destination, deadline=deadline)
        total_bytes += size
        artifacts.append(
            {
                "relative_path": destination.relative_to(snapshot).as_posix(),
                "source": str(source),
                "size": size,
                "sha256": checksum,
            }
        )
    return {
        "artifacts": artifacts,
        "component": {
            "name": step["component"],
            "type": "copy_files",
            "files": len(artifacts),
            "bytes": total_bytes,
        },
        "counters": {
            "files_examined": len(artifacts),
            "files_copied": len(artifacts),
            "bytes_examined": total_bytes,
            "bytes_copied": total_bytes,
        },
    }


def _verify_snapshot(
    snapshot: Path,
    *,
    artifacts: list[dict[str, Any]],
    mode: str,
    deadline: float,
) -> dict[str, Any]:
    artifact_checksums = {item["relative_path"]: item["sha256"] for item in artifacts}
    checksums: list[dict[str, str]] = []
    regular_files = 0
    symlinks = 0
    total_bytes = 0
    for root, directories, filenames in os.walk(snapshot, topdown=True, followlinks=False):
        _check_cancel_or_timeout(deadline)
        directories.sort()
        filenames.sort()
        root_path = Path(root)
        for directory_name in list(directories):
            directory = root_path / directory_name
            if directory.is_symlink():
                _verify_safe_link(directory, snapshot)
                directories.remove(directory_name)
                symlinks += 1
        for filename in filenames:
            path = root_path / filename
            relative = path.relative_to(snapshot).as_posix()
            if relative in {"BACKUP_INCOMPLETE", "BACKUP_COMPLETE", "manifest.json"}:
                continue
            if path.is_symlink():
                _verify_safe_link(path, snapshot)
                symlinks += 1
                continue
            if not path.is_file():
                raise HelperFailure("verification_failed", "Snapshot contains an unsupported filesystem object.")
            regular_files += 1
            size = path.stat().st_size
            total_bytes += size
            expected = artifact_checksums.get(relative)
            if mode == "sha256" or expected is not None:
                actual = _sha256(path, deadline=deadline)
                if expected is not None and actual != expected:
                    raise HelperFailure("checksum_mismatch", "Snapshot checksum verification failed.")
                checksums.append({"path": relative, "sha256": actual})
    if regular_files == 0:
        raise HelperFailure("verification_failed", "Snapshot contains no regular backup files.")
    checksums.sort(key=lambda item: item["path"])
    return {
        "regular_files": regular_files,
        "symlinks": symlinks,
        "bytes": total_bytes,
        "checksums": checksums,
    }


def _verify_safe_link(path: Path, snapshot: Path) -> None:
    target = os.readlink(path)
    if os.path.isabs(target):
        raise HelperFailure("unsafe_symlink", "Snapshot contains an unsafe symbolic link.")
    resolved = (path.parent / target).resolve(strict=False)
    if not _within(resolved, snapshot.resolve()):
        raise HelperFailure("unsafe_symlink", "Snapshot contains an unsafe symbolic link.")


def _verify_required_tools(plan: dict[str, Any]) -> None:
    required: set[str] = set()
    for step in plan["steps"]:
        if step["type"] == "rsync_snapshot":
            required.add(RSYNC_BINARY)
        elif step["type"] == "postgres_dump":
            required.add(DOCKER_BINARY)
    for path in required:
        if not Path(path).is_file() or not os.access(path, os.X_OK):
            raise HelperFailure("required_tool_missing", "A required backup tool is unavailable.", status_value="rejected")


def _verify_postgres_targets(plan: dict[str, Any]) -> None:
    _verify_postgres_data_sources(plan)
    for step in plan["steps"]:
        if step["type"] == "postgres_dump":
            _verify_postgres_target(step)


def _verify_postgres_data_sources(plan: dict[str, Any]) -> None:
    copy_sources: list[Path] = []
    for step in plan["steps"]:
        if step["type"] == "rsync_snapshot":
            copy_sources.append(Path(step["source"]).resolve())
        elif step["type"] == "copy_files":
            copy_sources.extend(Path(value).resolve() for value in step["sources"])
    for step in plan["steps"]:
        if step["type"] != "postgres_dump":
            continue
        mount_source = _postgres_data_mount(step["container"])
        if mount_source and any(_overlaps(source, mount_source) for source in copy_sources):
            raise HelperFailure(
                "postgres_data_copy_forbidden",
                "Direct copying of live PostgreSQL storage is forbidden.",
                status_value="rejected",
            )


def _verify_postgres_target(step: dict[str, Any]) -> None:
    format_string = (
        "{{.Name}}\n{{.State.Status}}\n"
        "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}\n"
        "{{index .Config.Labels \"com.docker.compose.project\"}}\n"
        "{{index .Config.Labels \"com.docker.compose.service\"}}"
    )
    result = _run_capture([DOCKER_BINARY, "inspect", "--format", format_string, step["container"]], timeout=20)
    lines = result.splitlines()
    if len(lines) != 5:
        raise HelperFailure("container_identity_invalid", "Required PostgreSQL container identity is invalid.", status_value="rejected")
    if (
        lines[0] != f"/{step['container']}"
        or lines[1] != "running"
        or lines[2] != "healthy"
        or lines[3] != step["expected_compose_project"]
        or lines[4] != step["expected_compose_service"]
    ):
        raise HelperFailure("required_container_unhealthy", "Required PostgreSQL container is not healthy.", status_value="rejected")


def _postgres_data_mount(container: str) -> Path | None:
    format_string = '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Source}}{{end}}{{end}}'
    output = _run_capture([DOCKER_BINARY, "inspect", "--format", format_string, container], timeout=20).strip()
    if not output:
        return None
    path = Path(output)
    if not path.is_absolute():
        raise HelperFailure("container_identity_invalid", "Required PostgreSQL container identity is invalid.", status_value="rejected")
    return path.resolve(strict=False)


def _estimate_plan(plan: dict[str, Any]) -> int:
    total = 0
    for step in plan["steps"]:
        if step["type"] == "rsync_snapshot":
            total += _estimate_rsync(step, timeout=min(plan["timeout_seconds"], 600))
        elif step["type"] == "copy_files":
            total += sum(Path(value).stat().st_size for value in step["sources"])
        elif step["type"] == "postgres_dump":
            query = "SELECT pg_database_size(current_database());"
            output = _run_capture(
                [
                    DOCKER_BINARY,
                    "exec",
                    step["container"],
                    "/usr/bin/psql",
                    "-X",
                    "-A",
                    "-t",
                    "-U",
                    step["role"],
                    "-d",
                    step["database"],
                    "-c",
                    query,
                ],
                timeout=30,
            ).strip()
            if not output.isdigit():
                raise HelperFailure("database_estimate_failed", "PostgreSQL size estimation failed.", status_value="rejected")
            total += int(output)
    if total <= 0:
        raise HelperFailure("source_empty", "Backup source estimate is empty.", status_value="rejected")
    return total


def _estimate_rsync(step: dict[str, Any], *, timeout: int) -> int:
    arguments = [
        RSYNC_BINARY,
        "--archive",
        "--no-owner",
        "--no-group",
        "--no-perms",
        "--no-devices",
        "--no-specials",
        "--safe-links",
        "--dry-run",
        "--stats",
    ]
    for exclusion in step["excludes"]:
        arguments.extend(["--exclude", exclusion])
    arguments.extend([f"{step['source']}/", f"{DESTINATION_ROOT}/.assessment-placeholder/"])
    output = _run_capture(arguments, timeout=timeout)
    return _parse_rsync_stat(output, "Total file size")


def _storage_state(registry: dict[str, Any], *, write_probe: bool) -> tuple[bool, bool, bool, int]:
    cold_mount = Path(registry["cold_mount"])
    destination_root = Path(registry["destination_root"])
    mounted = False
    writable = False
    free_bytes = 0
    try:
        mount = _mount_for(cold_mount)
        mounted = (
            mount is not None
            and mount["mount_point"] == cold_mount
            and mount["source"] == registry["raid_device"]
            and mount["filesystem"] == "ext4"
            and "rw" in mount["options"]
            and cold_mount.is_mount()
            and not cold_mount.is_symlink()
            and destination_root.exists()
            and destination_root.is_dir()
            and not destination_root.is_symlink()
            and destination_root.resolve().parent == cold_mount.resolve()
            and destination_root.stat().st_dev == cold_mount.stat().st_dev
            and _valid_root_directory(destination_root.stat())
        )
        if mounted:
            stats = os.statvfs(destination_root)
            free_bytes = stats.f_bavail * stats.f_frsize
            writable = os.access(destination_root, os.W_OK)
            if writable and write_probe:
                probe = destination_root / f".write-probe-{os.getpid()}"
                descriptor = os.open(
                    probe,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                    0o600,
                )
                os.write(descriptor, b"ok\n")
                os.fsync(descriptor)
                os.close(descriptor)
                probe.unlink()
    except OSError:
        mounted = False
        writable = False
        free_bytes = 0
    raid_name = Path(registry["raid_device"]).name
    try:
        degraded = (Path("/sys/block") / raid_name / "md" / "degraded").read_text(encoding="ascii").strip()
        array_state = (Path("/sys/block") / raid_name / "md" / "array_state").read_text(encoding="ascii").strip()
        raid_healthy = degraded == "0" and array_state in {"clean", "active"}
    except OSError:
        raid_healthy = False
    return mounted, writable, raid_healthy, free_bytes


def _mount_for(path: Path) -> dict[str, Any] | None:
    best: dict[str, Any] | None = None
    for line in Path("/proc/self/mountinfo").read_text(encoding="utf-8").splitlines():
        fields = line.split()
        try:
            separator = fields.index("-")
        except ValueError:
            continue
        mount_point = Path(_unescape_mount_field(fields[4]))
        if path == mount_point or path.is_relative_to(mount_point):
            candidate = {
                "mount_point": mount_point,
                "options": set(fields[5].split(",")),
                "filesystem": fields[separator + 1],
                "source": _unescape_mount_field(fields[separator + 2]),
            }
            if best is None or len(mount_point.parts) > len(best["mount_point"].parts):
                best = candidate
    return best


def _unescape_mount_field(value: str) -> str:
    return value.replace("\\040", " ").replace("\\011", "\t").replace("\\012", "\n").replace("\\134", "\\")


def _plan_locked(plan_id: str) -> bool:
    _ensure_runtime_root()
    lock_path = RUNTIME_ROOT / f"plan-{plan_id}.lock"
    handle = lock_path.open("a+", encoding="utf-8")
    os.chmod(lock_path, 0o600)
    try:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        return False
    finally:
        handle.close()


def _write_state_file(
    path: Path,
    *,
    registry: dict[str, Any],
    plan: dict[str, Any],
    job_id: str,
    incomplete: Path,
    final_directory: Path,
) -> None:
    process_stat = _read_process_stat(os.getpid())
    state = {
        "job_id": job_id,
        "plan_id": plan["id"],
        "pid": os.getpid(),
        "pgid": os.getpgrp(),
        "start_ticks": process_stat["start_ticks"],
        "incomplete": str(incomplete),
        "final": str(final_directory),
        "registry_fingerprint": registry_fingerprint(registry),
    }
    _write_json_file(path, state, exclusive=True)


def _read_process_stat(pid: int) -> dict[str, int]:
    content = (Path("/proc") / str(pid) / "stat").read_text(encoding="ascii")
    closing = content.rfind(")")
    fields = content[closing + 2 :].split()
    return {"pgid": int(fields[2]), "start_ticks": int(fields[19])}


def _install_signal_handlers() -> None:
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)


def _signal_handler(_signum: int, _frame: object) -> None:
    global _cancel_requested
    _cancel_requested = True


def _check_cancel_or_timeout(deadline: float) -> None:
    if _cancel_requested:
        raise BackupCancelled()
    if time.monotonic() >= deadline:
        raise BackupTimedOut()


def _remaining_seconds(deadline: float) -> int:
    remaining = math.ceil(deadline - time.monotonic())
    if remaining <= 0:
        raise BackupTimedOut()
    return remaining


def _version_command(arguments: list[str], *, deadline: float) -> str:
    output = _run_capture(arguments, timeout=min(30, _remaining_seconds(deadline))).strip()
    if not output or len(output) > 200 or any(ord(character) < 32 for character in output):
        raise HelperFailure("version_probe_failed", "PostgreSQL version inspection failed.")
    return output


def _run_capture(arguments: list[str], *, timeout: int) -> str:
    try:
        result = subprocess.run(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
            env=SAFE_ENV,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise HelperFailure("required_operation_failed", "A required backup safety check failed.", status_value="rejected") from error
    if result.returncode != 0 or len(result.stdout) > 1_048_576:
        raise HelperFailure("required_operation_failed", "A required backup safety check failed.", status_value="rejected")
    try:
        return result.stdout.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise HelperFailure("required_operation_failed", "A required backup safety check failed.", status_value="rejected") from error


def _parse_rsync_stat(output: str, label: str) -> int:
    match = re.search(rf"^{re.escape(label)}:\s*([0-9,]+)(?:\s+bytes)?", output, re.MULTILINE)
    if not match:
        raise HelperFailure("rsync_output_invalid", "Rsync returned invalid statistics.")
    return int(match.group(1).replace(",", ""))


def _sha256(path: Path, *, deadline: float) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            _check_cancel_or_timeout(deadline)
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _write_json_file(path: Path, payload: dict[str, Any], *, exclusive: bool) -> None:
    mode = "x" if exclusive else "w"
    with path.open(mode, encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True, separators=(",", ":"), allow_nan=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(path, 0o600)


def _mark_incomplete(incomplete: Path, *, job_id: str, plan_id: str, error: HelperFailure) -> None:
    marker = incomplete / "BACKUP_INCOMPLETE"
    payload = {
        "job_id": job_id,
        "plan_id": plan_id,
        "status": error.status_value,
        "error_code": error.code,
        "finished_at": _utc_timestamp(),
    }
    try:
        _write_json_file(marker, payload, exclusive=not marker.exists())
    except OSError:
        pass


def _make_snapshot_read_only(root: Path) -> None:
    for current_root, directories, files in os.walk(root, topdown=False, followlinks=False):
        current = Path(current_root)
        for filename in files:
            path = current / filename
            if not path.is_symlink():
                os.chmod(path, 0o400)
        for directory in directories:
            path = current / directory
            if not path.is_symlink():
                os.chmod(path, 0o500)
        os.chmod(current, 0o500)


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _safe_unlink_state(path: Path) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return
    if stat.S_ISREG(metadata.st_mode) and metadata.st_uid == 0 and metadata.st_gid == 0:
        path.unlink()


def _valid_state_metadata(metadata: os.stat_result) -> bool:
    return (
        stat.S_ISREG(metadata.st_mode)
        and metadata.st_uid == 0
        and metadata.st_gid == 0
        and stat.S_IMODE(metadata.st_mode) == 0o600
        and metadata.st_size <= 8192
    )


def _valid_root_directory(metadata: os.stat_result) -> bool:
    return (
        stat.S_ISDIR(metadata.st_mode)
        and metadata.st_uid == 0
        and metadata.st_gid == 0
        and stat.S_IMODE(metadata.st_mode) == 0o700
    )


def _ensure_runtime_root() -> None:
    RUNTIME_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    metadata = RUNTIME_ROOT.lstat()
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_gid != 0
        or stat.S_IMODE(metadata.st_mode) != 0o700
    ):
        raise HelperFailure("runtime_permissions", "Backup helper runtime permissions are invalid.")


def _emit_progress(
    registry: dict[str, Any],
    *,
    phase: str,
    progress_percent: float,
    files_examined: int,
    files_copied: int,
    bytes_examined: int,
    bytes_copied: int,
) -> None:
    _emit(
        {
            "kind": "progress",
            "registry_fingerprint": registry_fingerprint(registry),
            "phase": phase,
            "progress_percent": round(progress_percent, 2),
            "files_examined": files_examined,
            "files_copied": files_copied,
            "bytes_examined": bytes_examined,
            "bytes_copied": bytes_copied,
        }
    )


def _result(
    registry: dict[str, Any],
    *,
    status_value: str,
    summary: str,
    error_code: str | None,
    verification_state: str,
    destination_snapshot: str | None = None,
    manifest_path: str | None = None,
    files_examined: int = 0,
    files_copied: int = 0,
    bytes_examined: int = 0,
    bytes_copied: int = 0,
) -> dict[str, Any]:
    return {
        "kind": "result",
        "registry_fingerprint": registry_fingerprint(registry),
        "status": status_value,
        "summary": summary,
        "error_code": error_code,
        "verification_state": verification_state,
        "destination_snapshot": destination_snapshot,
        "manifest_path": manifest_path,
        "files_examined": files_examined,
        "files_copied": files_copied,
        "bytes_examined": bytes_examined,
        "bytes_copied": bytes_copied,
    }


def _merge_counters(target: dict[str, int], incoming: dict[str, int]) -> None:
    for key in target:
        target[key] += incoming[key]


def _strict_dict(
    payload: object,
    allowed: set[str],
    *,
    optional: set[str] | None = None,
) -> dict[str, Any]:
    if not isinstance(payload, dict) or any(not isinstance(key, str) for key in payload):
        raise ValueError("object")
    optional = optional or set()
    required = allowed - optional
    if set(payload) - allowed or not required.issubset(payload):
        raise ValueError("keys")
    return payload


def _strict_int(value: object, minimum: int, maximum: int) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or not minimum <= value <= maximum:
        raise ValueError("integer")
    return value


def _identifier(value: object) -> str:
    if not isinstance(value, str) or not ID_PATTERN.fullmatch(value):
        raise ValueError("identifier")
    return value


def _target(value: object) -> str:
    if (
        not isinstance(value, str)
        or not TARGET_PATTERN.fullmatch(value)
        or any(character in SHELL_METACHARACTERS for character in value)
    ):
        raise ValueError("target")
    return value


def _human_text(value: object, *, maximum: int) -> str:
    if (
        not isinstance(value, str)
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
        or any(character in SHELL_METACHARACTERS for character in value)
    ):
        raise ValueError("text")
    normalized = " ".join(value.split())
    if not normalized or len(normalized) > maximum:
        raise ValueError("text")
    return normalized


def _absolute_path(value: object) -> Path:
    if not isinstance(value, str) or not value.startswith("/"):
        raise ValueError("path")
    if any(character in SHELL_METACHARACTERS for character in value) or any(
        character in value for character in "*?[]{}"
    ):
        raise ValueError("path")
    path = Path(value)
    if ".." in path.parts or "." in path.parts:
        raise ValueError("path")
    return path


def _has_symlink(path: Path, *, require_leaf: bool) -> bool:
    current = Path(path.anchor)
    for index, part in enumerate(path.parts[1:]):
        current /= part
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            return False
        if stat.S_ISLNK(metadata.st_mode):
            return True
        if require_leaf and index == len(path.parts[1:]) - 1 and not current.exists():
            return True
    return False


def _within(path: Path, root: Path) -> bool:
    return path == root or path.is_relative_to(root)


def _overlaps(left: Path, right: Path) -> bool:
    return _within(left, right) or _within(right, left)


def _is_postgres_data_path(path: Path) -> bool:
    candidate = path if path.is_dir() else path.parent
    for parent in (candidate, *candidate.parents):
        try:
            if (parent / "PG_VERSION").is_file():
                return True
        except OSError:
            return True
    return False


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n")
    sys.stdout.flush()


def _find_plan(registry: dict[str, Any], plan_id: str) -> dict[str, Any]:
    plan = next((item for item in registry["plans"] if item["id"] == plan_id), None)
    if plan is None:
        raise HelperFailure("plan_not_found", "Backup plan was not found.", status_value="rejected")
    return plan


def main() -> int:
    os.umask(0o077)
    if len(sys.argv) != 1:
        _emit({"status": "rejected", "summary": "Backup helper accepts no command-line arguments.", "error_code": "request_invalid"})
        return 4
    try:
        raw_input = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
        if len(raw_input) > MAX_INPUT_BYTES:
            raise HelperFailure("request_invalid", "Backup helper request is invalid.", status_value="rejected")
        try:
            request_document = json.loads(raw_input.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise HelperFailure("request_invalid", "Backup helper request is invalid.", status_value="rejected") from error
        request = validate_request(request_document)
        registry = load_registry()
        plan = _find_plan(registry, request["plan_id"])
        operation = request["operation"]
        if operation == "validate":
            for registry_plan in registry["plans"]:
                _verify_postgres_data_sources(registry_plan)
            recover_interrupted_states(registry)
            _emit(
                {
                    "kind": "validation",
                    "status": "succeeded",
                    "registry_fingerprint": registry_fingerprint(registry),
                }
            )
            return 0
        if operation in {"assess", "preflight"}:
            _emit(assess_plan(registry, plan, write_probe=operation == "preflight"))
            return 0
        if operation == "cancel":
            _emit(cancel_backup(registry, plan, request["job_id"]))
            return 0
        result, exit_code = run_backup(registry, plan, request["job_id"])
        _emit(result)
        return exit_code
    except HelperFailure as error:
        _emit({"status": error.status_value, "summary": error.summary, "error_code": error.code})
        return 4 if error.status_value == "rejected" else 1
    except Exception:
        _emit({"status": "failed", "summary": "Backup helper failed safely.", "error_code": "helper_failed"})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
