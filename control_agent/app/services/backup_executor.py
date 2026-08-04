from __future__ import annotations

import asyncio
import json
import os
import re
import signal
from contextlib import suppress
from dataclasses import dataclass
from pathlib import Path
from typing import Awaitable, Callable, Protocol
from uuid import UUID

from .backup_registry import BackupPlan

MAX_HELPER_OUTPUT_BYTES = 262_144
FINGERPRINT_PATTERN = re.compile(r"^[a-f0-9]{64}$")
ERROR_CODE_PATTERN = re.compile(r"^[a-z0-9_]{1,64}$")
TERMINAL_STATUSES = {"succeeded", "failed", "cancelled", "timed_out", "rejected"}


class HelperProtocolError(RuntimeError):
    pass


class HelperUnavailableError(RuntimeError):
    pass


@dataclass(frozen=True)
class BackupAssessment:
    allowed: bool
    blocking_code: str | None
    blocking_reason: str | None
    source_size_estimate: int
    destination_free_bytes: int
    required_bytes: int
    cold_storage_mounted: bool
    cold_storage_writable: bool
    raid_healthy: bool


@dataclass(frozen=True)
class BackupProgress:
    phase: str
    progress_percent: float | None = None
    files_examined: int | None = None
    files_copied: int | None = None
    bytes_examined: int | None = None
    bytes_copied: int | None = None


@dataclass(frozen=True)
class BackupExecutionResult:
    status: str
    summary: str
    error_code: str | None
    verification_state: str
    destination_snapshot: str | None
    manifest_path: str | None
    files_examined: int | None
    files_copied: int | None
    bytes_examined: int | None
    bytes_copied: int | None


class BackupHelper(Protocol):
    async def validate_registry(self, *, plan_id: str, fingerprint: str) -> None: ...

    async def assess(
        self,
        *,
        plan: BackupPlan,
        job_id: str,
        fingerprint: str,
        operation: str = "assess",
    ) -> BackupAssessment: ...

    async def execute(
        self,
        *,
        plan: BackupPlan,
        job_id: str,
        fingerprint: str,
        on_progress: Callable[[BackupProgress], Awaitable[None]],
    ) -> BackupExecutionResult: ...

    async def cancel(
        self,
        *,
        plan_id: str,
        job_id: str,
        fingerprint: str,
    ) -> bool: ...


class SudoBackupHelper:
    def __init__(self, helper_path: Path):
        self.helper_path = helper_path

    async def validate_registry(self, *, plan_id: str, fingerprint: str) -> None:
        payload = await self._single_response(
            operation="validate",
            plan_id=plan_id,
            job_id=str(UUID(int=0)),
            timeout_seconds=30,
        )
        _require_fingerprint(payload, fingerprint)
        if payload.get("kind") != "validation" or payload.get("status") != "succeeded":
            raise HelperProtocolError("backup helper registry validation failed")

    async def assess(
        self,
        *,
        plan: BackupPlan,
        job_id: str,
        fingerprint: str,
        operation: str = "assess",
    ) -> BackupAssessment:
        if operation not in {"assess", "preflight"}:
            raise ValueError("backup helper assessment operation is invalid")
        payload = await self._single_response(
            operation=operation,
            plan_id=plan.id,
            job_id=job_id,
            timeout_seconds=min(max(plan.timeout_seconds // 10, 30), 300),
        )
        _require_fingerprint(payload, fingerprint)
        if payload.get("kind") != "assessment" or payload.get("status") != "succeeded":
            raise HelperProtocolError("backup helper assessment response is invalid")
        allowed = payload.get("allowed")
        if not isinstance(allowed, bool):
            raise HelperProtocolError("backup helper assessment is invalid")
        return BackupAssessment(
            allowed=allowed,
            blocking_code=_optional_error_code(payload.get("blocking_code")),
            blocking_reason=_optional_text(payload.get("blocking_reason"), maximum=240),
            source_size_estimate=_nonnegative_int(payload.get("source_size_estimate")),
            destination_free_bytes=_nonnegative_int(payload.get("destination_free_bytes")),
            required_bytes=_nonnegative_int(payload.get("required_bytes")),
            cold_storage_mounted=_boolean(payload.get("cold_storage_mounted")),
            cold_storage_writable=_boolean(payload.get("cold_storage_writable")),
            raid_healthy=_boolean(payload.get("raid_healthy")),
        )

    async def execute(
        self,
        *,
        plan: BackupPlan,
        job_id: str,
        fingerprint: str,
        on_progress: Callable[[BackupProgress], Awaitable[None]],
    ) -> BackupExecutionResult:
        process = await self._spawn(
            _request_payload(operation="run", plan_id=plan.id, job_id=job_id)
        )
        stderr_task = asyncio.create_task(_discard_stream(process.stderr))

        async def consume() -> BackupExecutionResult:
            total_bytes = 0
            final_result: BackupExecutionResult | None = None
            assert process.stdout is not None
            while True:
                line = await process.stdout.readline()
                if not line:
                    break
                total_bytes += len(line)
                if total_bytes > MAX_HELPER_OUTPUT_BYTES or len(line) > 65_536:
                    raise HelperProtocolError("backup helper output exceeded its limit")
                try:
                    payload = json.loads(line.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError) as error:
                    raise HelperProtocolError("backup helper emitted invalid JSON") from error
                _require_fingerprint(payload, fingerprint)
                kind = payload.get("kind")
                if kind == "progress":
                    if final_result is not None:
                        raise HelperProtocolError("backup helper emitted progress after completion")
                    await on_progress(_parse_progress(payload))
                elif kind == "result":
                    if final_result is not None:
                        raise HelperProtocolError("backup helper emitted multiple results")
                    final_result = _parse_result(payload)
                else:
                    raise HelperProtocolError("backup helper emitted an unknown event")
            await process.wait()
            await stderr_task
            if final_result is None:
                raise HelperProtocolError("backup helper did not emit a result")
            if process.returncode == 0 and final_result.status != "succeeded":
                raise HelperProtocolError("backup helper exit status is inconsistent")
            if process.returncode != 0 and final_result.status == "succeeded":
                raise HelperProtocolError("backup helper exit status is inconsistent")
            return final_result

        try:
            return await asyncio.wait_for(consume(), timeout=plan.timeout_seconds + 30)
        except asyncio.TimeoutError:
            await self.cancel(
                plan_id=plan.id,
                job_id=job_id,
                fingerprint=fingerprint,
            )
            await _wait_after_cancel(process)
            return BackupExecutionResult(
                status="timed_out",
                summary="Backup exceeded its execution deadline.",
                error_code="backup_timeout",
                verification_state="failed",
                destination_snapshot=None,
                manifest_path=None,
                files_examined=None,
                files_copied=None,
                bytes_examined=None,
                bytes_copied=None,
            )
        except HelperProtocolError:
            try:
                await self.cancel(
                    plan_id=plan.id,
                    job_id=job_id,
                    fingerprint=fingerprint,
                )
            except (HelperProtocolError, HelperUnavailableError):
                pass
            await _wait_after_cancel(process)
            raise
        except asyncio.CancelledError:
            try:
                await self.cancel(
                    plan_id=plan.id,
                    job_id=job_id,
                    fingerprint=fingerprint,
                )
            finally:
                await _wait_after_cancel(process)
            raise
        finally:
            if not stderr_task.done():
                stderr_task.cancel()
            with suppress(asyncio.CancelledError):
                await stderr_task

    async def cancel(
        self,
        *,
        plan_id: str,
        job_id: str,
        fingerprint: str,
    ) -> bool:
        payload = await self._single_response(
            operation="cancel",
            plan_id=plan_id,
            job_id=job_id,
            timeout_seconds=15,
        )
        _require_fingerprint(payload, fingerprint)
        if payload.get("kind") != "cancellation" or payload.get("status") != "succeeded":
            raise HelperProtocolError("backup helper cancellation response is invalid")
        return _boolean(payload.get("signal_sent"))

    async def _single_response(
        self,
        *,
        operation: str,
        plan_id: str,
        job_id: str,
        timeout_seconds: int,
    ) -> dict[str, object]:
        process = await self._spawn(
            _request_payload(operation=operation, plan_id=plan_id, job_id=job_id)
        )
        try:
            stdout, _stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=timeout_seconds,
            )
        except asyncio.TimeoutError as error:
            await _terminate_process_group(process)
            raise HelperUnavailableError("backup helper timed out") from error
        except asyncio.CancelledError:
            await _terminate_process_group(process)
            raise
        if len(stdout) > 65_536:
            raise HelperProtocolError("backup helper response exceeded its limit")
        try:
            payload = json.loads(stdout.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise HelperProtocolError("backup helper returned invalid JSON") from error
        if not isinstance(payload, dict):
            raise HelperProtocolError("backup helper response is not an object")
        if process.returncode != 0:
            error_code = _optional_error_code(payload.get("error_code"))
            summary = _optional_text(payload.get("summary"), maximum=240)
            raise HelperUnavailableError(summary or error_code or "backup helper failed")
        return payload

    async def _spawn(self, request_payload: bytes) -> asyncio.subprocess.Process:
        try:
            process = await asyncio.create_subprocess_exec(
                "/usr/bin/sudo",
                "-n",
                str(self.helper_path),
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                limit=65_536,
                start_new_session=True,
            )
        except OSError as error:
            raise HelperUnavailableError("backup helper is unavailable") from error
        assert process.stdin is not None
        process.stdin.write(request_payload)
        await process.stdin.drain()
        process.stdin.close()
        return process


def _request_payload(*, operation: str, plan_id: str, job_id: str) -> bytes:
    parsed_job_id = UUID(job_id)
    canonical_job_id = str(parsed_job_id)
    payload = {
        "operation": operation,
        "plan_id": plan_id,
        "job_id": canonical_job_id,
    }
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")


def _require_fingerprint(payload: object, expected: str) -> None:
    if not isinstance(payload, dict):
        raise HelperProtocolError("backup helper event is not an object")
    fingerprint = payload.get("registry_fingerprint")
    if (
        not isinstance(fingerprint, str)
        or not FINGERPRINT_PATTERN.fullmatch(fingerprint)
        or fingerprint != expected
    ):
        raise HelperProtocolError("backup registry changed; service restart is required")


def _parse_progress(payload: dict[str, object]) -> BackupProgress:
    allowed = {
        "kind",
        "registry_fingerprint",
        "phase",
        "progress_percent",
        "files_examined",
        "files_copied",
        "bytes_examined",
        "bytes_copied",
    }
    if set(payload) - allowed:
        raise HelperProtocolError("backup progress contains unknown fields")
    phase = payload.get("phase")
    if phase not in {"running", "verifying"}:
        raise HelperProtocolError("backup progress phase is invalid")
    progress_value = payload.get("progress_percent")
    if progress_value is not None:
        if not isinstance(progress_value, (int, float)) or isinstance(progress_value, bool):
            raise HelperProtocolError("backup progress percentage is invalid")
        if not 0 <= float(progress_value) <= 100:
            raise HelperProtocolError("backup progress percentage is invalid")
    return BackupProgress(
        phase=phase,
        progress_percent=float(progress_value) if progress_value is not None else None,
        files_examined=_optional_nonnegative_int(payload.get("files_examined")),
        files_copied=_optional_nonnegative_int(payload.get("files_copied")),
        bytes_examined=_optional_nonnegative_int(payload.get("bytes_examined")),
        bytes_copied=_optional_nonnegative_int(payload.get("bytes_copied")),
    )


def _parse_result(payload: dict[str, object]) -> BackupExecutionResult:
    allowed = {
        "kind",
        "registry_fingerprint",
        "status",
        "summary",
        "error_code",
        "verification_state",
        "destination_snapshot",
        "manifest_path",
        "files_examined",
        "files_copied",
        "bytes_examined",
        "bytes_copied",
    }
    if set(payload) - allowed:
        raise HelperProtocolError("backup result contains unknown fields")
    status_value = payload.get("status")
    if status_value not in TERMINAL_STATUSES:
        raise HelperProtocolError("backup helper status is invalid")
    verification = payload.get("verification_state")
    if verification not in {"passed", "failed", "not_applicable"}:
        raise HelperProtocolError("backup verification state is invalid")
    return BackupExecutionResult(
        status=str(status_value),
        summary=_required_text(payload.get("summary"), maximum=300),
        error_code=_optional_error_code(payload.get("error_code")),
        verification_state=str(verification),
        destination_snapshot=_optional_private_path(payload.get("destination_snapshot")),
        manifest_path=_optional_private_path(payload.get("manifest_path")),
        files_examined=_optional_nonnegative_int(payload.get("files_examined")),
        files_copied=_optional_nonnegative_int(payload.get("files_copied")),
        bytes_examined=_optional_nonnegative_int(payload.get("bytes_examined")),
        bytes_copied=_optional_nonnegative_int(payload.get("bytes_copied")),
    )


def _required_text(value: object, *, maximum: int) -> str:
    parsed = _optional_text(value, maximum=maximum)
    if parsed is None:
        raise HelperProtocolError("backup helper text is missing")
    return parsed


def _optional_text(value: object, *, maximum: int) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise HelperProtocolError("backup helper text is invalid")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise HelperProtocolError("backup helper text contains control characters")
    normalized = " ".join(value.split())
    if not normalized or len(normalized) > maximum:
        raise HelperProtocolError("backup helper text is invalid")
    return normalized


def _optional_error_code(value: object) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or not ERROR_CODE_PATTERN.fullmatch(value):
        raise HelperProtocolError("backup helper error code is invalid")
    return value


def _nonnegative_int(value: object) -> int:
    parsed = _optional_nonnegative_int(value)
    if parsed is None:
        raise HelperProtocolError("backup helper integer is missing")
    return parsed


def _optional_nonnegative_int(value: object) -> int | None:
    if value is None:
        return None
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise HelperProtocolError("backup helper integer is invalid")
    return value


def _boolean(value: object) -> bool:
    if not isinstance(value, bool):
        raise HelperProtocolError("backup helper boolean is invalid")
    return value


def _optional_private_path(value: object) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or not value.startswith("/mnt/storage/backups/"):
        raise HelperProtocolError("backup helper path is invalid")
    if ".." in Path(value).parts or any(character in value for character in "\n\r\x00"):
        raise HelperProtocolError("backup helper path is invalid")
    return value


async def _wait_after_cancel(process: asyncio.subprocess.Process) -> None:
    try:
        await asyncio.wait_for(process.wait(), timeout=10)
    except asyncio.TimeoutError:
        await _terminate_process_group(process)


async def _terminate_process_group(process: asyncio.subprocess.Process) -> None:
    """Terminate the isolated sudo/helper group and always reap its leader."""
    if process.returncode is not None:
        await process.wait()
        return
    try:
        process_group = os.getpgid(process.pid)
    except ProcessLookupError:
        await process.wait()
        return
    if process_group == os.getpgrp():
        raise RuntimeError("refusing to terminate the service process group")

    try:
        os.killpg(process_group, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        try:
            process.terminate()
        except (ProcessLookupError, PermissionError):
            pass
    try:
        await asyncio.wait_for(process.wait(), timeout=5)
        return
    except asyncio.TimeoutError:
        pass

    try:
        os.killpg(process_group, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            process.kill()
        except (ProcessLookupError, PermissionError):
            pass
    try:
        await asyncio.wait_for(process.wait(), timeout=2)
    except asyncio.TimeoutError:
        # The process has been signalled and will be reaped by the event-loop
        # child watcher. Avoid making shutdown wait without a bound.
        pass


async def _discard_stream(stream: asyncio.StreamReader | None) -> None:
    if stream is None:
        return
    while await stream.read(8192):
        pass
