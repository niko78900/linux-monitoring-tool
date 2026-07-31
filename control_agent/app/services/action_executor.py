from __future__ import annotations

import asyncio
import json
import re
from dataclasses import dataclass
from pathlib import Path

from ..models.dashboard_actions import ActionRecordResponse

SAFE_STATE_PATTERN = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")
TERMINAL_HELPER_STATES = {"succeeded", "failed", "rejected", "timed_out"}


@dataclass(frozen=True)
class HelperExecutionResult:
    status: str
    summary: str
    error_code: str | None = None
    previous_state: str | None = None
    resulting_state: str | None = None


class HelperProtocolError(RuntimeError):
    pass


class SudoActionHelper:
    def __init__(self, helper_path: Path):
        self.helper_path = helper_path

    async def execute(
        self,
        record: ActionRecordResponse,
        *,
        timeout_seconds: int,
    ) -> HelperExecutionResult:
        request_payload = json.dumps(
            {
                "service_id": record.target_id,
                "action": record.action,
                "action_id": str(record.action_id),
            },
            separators=(",", ":"),
        ).encode("utf-8")

        process = await asyncio.create_subprocess_exec(
            "/usr/bin/sudo",
            "-n",
            str(self.helper_path),
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            limit=8192,
        )
        try:
            stdout, _stderr = await asyncio.wait_for(
                process.communicate(request_payload),
                timeout=timeout_seconds + 5,
            )
        except asyncio.TimeoutError:
            process.kill()
            await process.wait()
            return HelperExecutionResult(
                status="timed_out",
                summary="Action helper exceeded its execution deadline.",
                error_code="helper_timeout",
            )
        except asyncio.CancelledError:
            process.terminate()
            try:
                await asyncio.wait_for(process.wait(), timeout=2)
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
            raise

        if len(stdout) > 8192:
            raise HelperProtocolError("action helper response is too large")
        try:
            payload = json.loads(stdout.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise HelperProtocolError("action helper returned an invalid response") from error
        result = _validate_helper_response(payload)
        if process.returncode == 0 and result.status != "succeeded":
            raise HelperProtocolError("action helper status contradicts its exit code")
        if process.returncode != 0 and result.status == "succeeded":
            raise HelperProtocolError("action helper status contradicts its exit code")
        return result


def _validate_helper_response(payload: object) -> HelperExecutionResult:
    if not isinstance(payload, dict):
        raise HelperProtocolError("action helper response must be an object")
    allowed_keys = {
        "status",
        "summary",
        "error_code",
        "previous_state",
        "resulting_state",
    }
    if set(payload) - allowed_keys:
        raise HelperProtocolError("action helper response contains unknown fields")

    status_value = payload.get("status")
    summary_value = payload.get("summary")
    if status_value not in TERMINAL_HELPER_STATES:
        raise HelperProtocolError("action helper returned an invalid status")
    if not isinstance(summary_value, str):
        raise HelperProtocolError("action helper summary is invalid")
    summary = _sanitize_text(summary_value, maximum=240)
    error_code = _optional_safe_value(payload.get("error_code"), maximum=64)
    previous_state = _optional_safe_state(payload.get("previous_state"))
    resulting_state = _optional_safe_state(payload.get("resulting_state"))
    return HelperExecutionResult(
        status=status_value,
        summary=summary,
        error_code=error_code,
        previous_state=previous_state,
        resulting_state=resulting_state,
    )


def _sanitize_text(value: str, *, maximum: int) -> str:
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise HelperProtocolError("action helper text contains control characters")
    normalized = " ".join(value.split())
    if not normalized or len(normalized) > maximum:
        raise HelperProtocolError("action helper text length is invalid")
    return normalized


def _optional_safe_value(value: object, *, maximum: int) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise HelperProtocolError("action helper error code is invalid")
    normalized = _sanitize_text(value, maximum=maximum)
    if not re.fullmatch(r"[a-z0-9_]+", normalized):
        raise HelperProtocolError("action helper error code is invalid")
    return normalized


def _optional_safe_state(value: object) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or not SAFE_STATE_PATTERN.fullmatch(value):
        raise HelperProtocolError("action helper state is invalid")
    return value
