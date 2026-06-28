from __future__ import annotations

import logging
import os
import re
import shutil
import signal
import subprocess
import threading
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import IO, Any

from ..core.config import Settings
from ..models.benchmarks import BenchmarkStartRequest, BenchmarkStatusResponse

logger = logging.getLogger(__name__)

_BENCHMARK_LABELS = {
    "cpu_single": "CPU Single-Core Benchmark",
    "cpu_multi": "CPU Multi-Core Benchmark",
    "cpu_stress": "CPU Stress Test",
    "gpu_vkmark": "GPU Vulkan Benchmark",
}


class BenchmarkAlreadyRunningError(RuntimeError):
    pass


class BenchmarkUnavailableError(RuntimeError):
    pass


@dataclass
class _BenchmarkJob:
    kind: str
    label: str
    command: list[str]
    started_at: datetime
    duration_seconds: int | None
    threads: int | None
    workers: int | None
    process: subprocess.Popen[str]
    stdout_tail: deque[str]
    stderr_tail: deque[str]
    state: str = "running"
    finished_at: datetime | None = None
    return_code: int | None = None
    result: dict[str, Any] = field(default_factory=dict)
    detail: str | None = None
    stop_requested: bool = False
    stdout_thread: threading.Thread | None = None
    stderr_thread: threading.Thread | None = None


class BenchmarkRunner:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._job: _BenchmarkJob | None = None

    def status(self, settings: Settings) -> BenchmarkStatusResponse:
        with self._lock:
            job = self._job
            if job is None:
                return self._idle_status(settings)
            return self._status_from_job(job, settings)

    def start(
        self, request: BenchmarkStartRequest, settings: Settings
    ) -> BenchmarkStatusResponse:
        with self._lock:
            if self._job is not None and self._job.state == "running":
                raise BenchmarkAlreadyRunningError("A benchmark is already running")

            command, metadata = build_benchmark_command(request, settings)
            tail_size = max(10, settings.benchmark_stdout_tail_lines)
            try:
                process = _open_process(command)
            except FileNotFoundError as error:
                raise BenchmarkUnavailableError(
                    f"Benchmark command is unavailable: {command[0]}"
                ) from error
            except PermissionError as error:
                raise BenchmarkUnavailableError(
                    f"Benchmark command is not executable: {command[0]}"
                ) from error

            job = _BenchmarkJob(
                kind=request.kind,
                label=_BENCHMARK_LABELS[request.kind],
                command=command,
                started_at=datetime.now(timezone.utc),
                duration_seconds=metadata.get("duration_seconds"),
                threads=metadata.get("threads"),
                workers=metadata.get("workers"),
                process=process,
                stdout_tail=deque(maxlen=tail_size),
                stderr_tail=deque(maxlen=tail_size),
            )
            self._job = job

            job.stdout_thread = _start_reader(process.stdout, job.stdout_tail, self._lock)
            job.stderr_thread = _start_reader(process.stderr, job.stderr_tail, self._lock)
            threading.Thread(target=self._watch_process, args=(job,), daemon=True).start()
            logger.info("Started benchmark %s", job.kind)
            return self._status_from_job(job, settings)

    def stop(self, settings: Settings) -> BenchmarkStatusResponse:
        with self._lock:
            job = self._job
            if job is None or job.state != "running":
                return self.status(settings)
            job.stop_requested = True
            job.detail = "Stop requested by operator"
            process = job.process

        _terminate_process_tree(process)

        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _kill_process_tree(process)
            process.wait(timeout=5)

        with self._lock:
            if job.state == "running":
                self._finalize_job(job, process.returncode)
            return self._status_from_job(job, settings)

    def reset_for_tests(self) -> None:
        with self._lock:
            self._job = None

    def _watch_process(self, job: _BenchmarkJob) -> None:
        return_code = job.process.wait()
        _join_reader(job.stdout_thread)
        _join_reader(job.stderr_thread)
        with self._lock:
            if self._job is job and job.state == "running":
                self._finalize_job(job, return_code)

    def _finalize_job(self, job: _BenchmarkJob, return_code: int | None) -> None:
        job.finished_at = datetime.now(timezone.utc)
        job.return_code = return_code
        if job.stop_requested:
            job.state = "stopped"
            job.detail = job.detail or "Stopped"
        elif return_code == 0:
            job.state = "finished"
            job.detail = "Completed"
        else:
            job.state = "failed"
            job.detail = f"Command exited with status {return_code}"
        job.result = parse_benchmark_result(
            job.kind,
            "\n".join(job.stdout_tail),
            "\n".join(job.stderr_tail),
        )

    def _idle_status(self, settings: Settings) -> BenchmarkStatusResponse:
        return BenchmarkStatusResponse(
            state="idle",
            nproc=_nproc(),
            gpu_helper_path=str(settings.benchmark_gpu_helper_path),
            gpu_helper_available=settings.benchmark_gpu_helper_path.exists(),
        )

    def _status_from_job(
        self, job: _BenchmarkJob, settings: Settings
    ) -> BenchmarkStatusResponse:
        return BenchmarkStatusResponse(
            state=job.state,  # type: ignore[arg-type]
            kind=job.kind,  # type: ignore[arg-type]
            label=job.label,
            started_at=job.started_at,
            finished_at=job.finished_at,
            duration_seconds=job.duration_seconds,
            threads=job.threads,
            workers=job.workers,
            command=list(job.command),
            return_code=job.return_code,
            result=dict(job.result),
            stdout_tail=list(job.stdout_tail),
            stderr_tail=list(job.stderr_tail),
            detail=job.detail,
            nproc=_nproc(),
            gpu_helper_path=str(settings.benchmark_gpu_helper_path),
            gpu_helper_available=settings.benchmark_gpu_helper_path.exists(),
        )


def build_benchmark_command(
    request: BenchmarkStartRequest, settings: Settings
) -> tuple[list[str], dict[str, int]]:
    nproc = _nproc()
    max_duration = min(300, max(10, settings.benchmark_max_duration_seconds))
    metadata: dict[str, int] = {}

    if request.kind == "cpu_single":
        binary = _required_binary("sysbench")
        duration = _clamp(request.duration_seconds, 30, 5, max_duration)
        metadata["duration_seconds"] = duration
        return (
            [
                binary,
                "cpu",
                "--cpu-max-prime=20000",
                "--threads=1",
                f"--time={duration}",
                "run",
            ],
            metadata,
        )

    if request.kind == "cpu_multi":
        binary = _required_binary("sysbench")
        duration = _clamp(request.duration_seconds, 30, 5, max_duration)
        threads = _clamp(request.threads, nproc, 1, nproc)
        metadata["duration_seconds"] = duration
        metadata["threads"] = threads
        return (
            [
                binary,
                "cpu",
                "--cpu-max-prime=20000",
                f"--threads={threads}",
                f"--time={duration}",
                "run",
            ],
            metadata,
        )

    if request.kind == "cpu_stress":
        binary = _required_binary("stress-ng")
        duration = _clamp(request.duration_seconds, 60, 10, max_duration)
        workers = _clamp(request.workers, nproc, 1, nproc)
        metadata["duration_seconds"] = duration
        metadata["workers"] = workers
        return (
            [
                binary,
                "--cpu",
                str(workers),
                "--cpu-method",
                "matrixprod",
                "--verify",
                "--metrics-brief",
                "--timeout",
                f"{duration}s",
            ],
            metadata,
        )

    if request.kind == "gpu_vkmark":
        helper_path = settings.benchmark_gpu_helper_path
        if not helper_path.exists():
            raise BenchmarkUnavailableError(
                f"GPU benchmark helper is unavailable: {helper_path}"
            )
        return ([str(helper_path), "800x600"], metadata)

    raise ValueError("Unknown benchmark kind")


def parse_benchmark_result(
    kind: str, stdout: str, stderr: str
) -> dict[str, int | float | bool]:
    combined = f"{stdout}\n{stderr}"
    if kind in {"cpu_single", "cpu_multi"}:
        result: dict[str, int | float | bool] = {}
        events_per_second = _first_float(
            r"events per second:\s*([0-9]+(?:\.[0-9]+)?)", combined
        )
        total_time = _first_float(r"total time:\s*([0-9]+(?:\.[0-9]+)?)s", combined)
        total_events = _first_int(r"total number of events:\s*([0-9]+)", combined)
        if events_per_second is not None:
            result["events_per_second"] = events_per_second
        if total_time is not None:
            result["total_time_seconds"] = total_time
        if total_events is not None:
            result["total_events"] = total_events
        return result

    if kind == "cpu_stress":
        result = {}
        bogo_ops = _first_int(r"bogo ops\s*[:=]?\s*([0-9]+)", combined)
        real_time = _first_float(
            r"(?:real time|real-time)\s*[:=]?\s*([0-9]+(?:\.[0-9]+)?)", combined
        )
        bogo_ops_per_second = _first_float(
            r"(?:bogo ops/s|bogo-ops-per-second)\s*[:=]?\s*([0-9]+(?:\.[0-9]+)?)",
            combined,
        )
        if bogo_ops is not None:
            result["bogo_ops"] = bogo_ops
        if real_time is not None:
            result["real_time_seconds"] = real_time
        if bogo_ops_per_second is not None:
            result["bogo_ops_per_second"] = bogo_ops_per_second
        lowered = combined.lower()
        if "passed" in lowered:
            result["passed"] = True
        if "failed" in lowered:
            result["failed"] = True
        return result

    if kind == "gpu_vkmark":
        score = _first_int(r"vkmark Score:\s*([0-9]+)", combined)
        return {"score": score} if score is not None else {}

    return {}


def _open_process(command: list[str]) -> subprocess.Popen[str]:
    kwargs: dict[str, Any] = {
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
        "text": True,
        "bufsize": 1,
    }
    if os.name == "posix":
        kwargs["preexec_fn"] = os.setsid
    elif os.name == "nt":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    return subprocess.Popen(command, **kwargs)


def _start_reader(
    stream: IO[str] | None,
    tail: deque[str],
    lock: threading.RLock,
) -> threading.Thread | None:
    if stream is None:
        return None

    def read_stream() -> None:
        try:
            for line in stream:
                normalized = line.rstrip()
                if normalized:
                    with lock:
                        tail.append(normalized)
        finally:
            try:
                stream.close()
            except Exception:
                pass

    thread = threading.Thread(target=read_stream, daemon=True)
    thread.start()
    return thread


def _join_reader(thread: threading.Thread | None) -> None:
    if thread is not None:
        thread.join(timeout=0.5)


def _terminate_process_tree(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        if os.name == "posix":
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        else:
            process.terminate()
    except ProcessLookupError:
        return


def _kill_process_tree(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        if os.name == "posix":
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
        else:
            process.kill()
    except ProcessLookupError:
        return


def _required_binary(name: str) -> str:
    binary = shutil.which(name)
    if binary is None:
        raise BenchmarkUnavailableError(f"Required benchmark tool is unavailable: {name}")
    return binary


def _clamp(value: int | None, default: int, minimum: int, maximum: int) -> int:
    if value is None:
        parsed = default
    else:
        parsed = value
    return max(minimum, min(maximum, parsed))


def _nproc() -> int:
    return max(1, os.cpu_count() or 1)


def _first_float(pattern: str, value: str) -> float | None:
    match = re.search(pattern, value, flags=re.IGNORECASE)
    return float(match.group(1)) if match else None


def _first_int(pattern: str, value: str) -> int | None:
    match = re.search(pattern, value, flags=re.IGNORECASE)
    return int(match.group(1)) if match else None
