from __future__ import annotations

import io
import threading
import time
from pathlib import Path

import pytest

from app.models.benchmarks import BenchmarkStartRequest
from app.services.benchmark_runner import build_benchmark_command, parse_benchmark_result


def test_benchmark_status_requires_auth(client) -> None:
    response = client.get("/api/benchmarks/status")

    assert response.status_code == 401


def test_unknown_benchmark_kind_returns_400(client, auth_headers) -> None:
    response = client.post(
        "/api/benchmarks/start",
        headers=auth_headers,
        json={"kind": "raw_command"},
    )

    assert response.status_code == 400


def test_cpu_multi_command_clamps_threads_and_duration(monkeypatch) -> None:
    monkeypatch.setattr("app.services.benchmark_runner.shutil.which", lambda _: "/usr/bin/sysbench")

    from app.core.config import get_settings

    command, metadata = build_benchmark_command(
        BenchmarkStartRequest(
            kind="cpu_multi",
            duration_seconds=999,
            threads=999,
        ),
        get_settings(),
    )

    assert command[:3] == ["/usr/bin/sysbench", "cpu", "--cpu-max-prime=20000"]
    assert "--time=300" in command
    assert metadata["duration_seconds"] == 300
    assert metadata["threads"] >= 1
    assert command.count(f"--threads={metadata['threads']}") == 1


def test_gpu_command_uses_configured_helper(tmp_path: Path) -> None:
    helper = tmp_path / "homelab-vkmark-benchmark"
    helper.write_text("#!/bin/sh\n", encoding="utf-8")

    from app.core.config import Settings, get_settings

    settings = get_settings()
    test_settings = Settings(
        **{
            **settings.__dict__,
            "benchmark_gpu_helper_path": helper,
        }
    )

    command, metadata = build_benchmark_command(
        BenchmarkStartRequest(kind="gpu_vkmark"),
        test_settings,
    )

    assert command == [str(helper), "800x600"]
    assert metadata == {}


def test_parse_benchmark_results() -> None:
    sysbench = """
events per second: 1234.56
total time: 30.0012s
total number of events: 37042
"""
    stress = "stress-ng: metrc: bogo ops 1000 real time 10.05 bogo ops/s 99.5 passed"
    vkmark = "vkmark Score: 4581"

    assert parse_benchmark_result("cpu_single", sysbench, "") == {
        "events_per_second": 1234.56,
        "total_time_seconds": 30.0012,
        "total_events": 37042,
    }
    assert parse_benchmark_result("cpu_stress", "", stress) == {
        "bogo_ops": 1000,
        "real_time_seconds": 10.05,
        "bogo_ops_per_second": 99.5,
        "passed": True,
    }
    assert parse_benchmark_result("gpu_vkmark", vkmark, "") == {"score": 4581}


def test_starting_while_running_returns_409(client, auth_headers, monkeypatch) -> None:
    fake_processes: list[_FakeProcess] = []

    def fake_popen(command, **_kwargs):
        process = _FakeProcess(command)
        fake_processes.append(process)
        return process

    monkeypatch.setattr("app.services.benchmark_runner.shutil.which", lambda _: "/usr/bin/sysbench")
    monkeypatch.setattr("app.services.benchmark_runner.subprocess.Popen", fake_popen)

    response = client.post(
        "/api/benchmarks/start",
        headers=auth_headers,
        json={"kind": "cpu_single", "duration_seconds": 5},
    )

    assert response.status_code == 202
    assert response.json()["state"] == "running"

    second = client.post(
        "/api/benchmarks/start",
        headers=auth_headers,
        json={"kind": "cpu_single", "duration_seconds": 5},
    )

    assert second.status_code == 409

    fake_processes[0].complete(0)
    time.sleep(0.05)


class _FakeProcess:
    _next_pid = 5000

    def __init__(self, command: list[str]) -> None:
        type(self)._next_pid += 1
        self.pid = type(self)._next_pid
        self.command = command
        self.stdout = io.StringIO("events per second: 42.5\n")
        self.stderr = io.StringIO("")
        self.returncode: int | None = None
        self._done = threading.Event()

    def wait(self, timeout: float | None = None) -> int:
        if not self._done.wait(timeout):
            raise TimeoutError
        return self.returncode or 0

    def poll(self) -> int | None:
        return self.returncode

    def terminate(self) -> None:
        self.complete(-15)

    def kill(self) -> None:
        self.complete(-9)

    def complete(self, returncode: int) -> None:
        self.returncode = returncode
        self._done.set()
