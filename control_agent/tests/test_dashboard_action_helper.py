from __future__ import annotations

import ast
import importlib.util
import json
import subprocess
from pathlib import Path
from types import ModuleType
from uuid import uuid4

import pytest
import yaml

from app.services.wake_on_lan import build_magic_packet


@pytest.fixture(scope="module")
def helper_module() -> ModuleType:
    helper_path = (
        Path(__file__).parents[2]
        / "deploy/scripts/linux-monitor-dashboard-action-helper.py"
    )
    specification = importlib.util.spec_from_file_location(
        "dashboard_action_helper",
        helper_path,
    )
    assert specification is not None and specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def _registry_document() -> dict:
    return {
        "services": [
            {
                "id": "example-worker",
                "name": "Example Worker",
                "kind": "docker_container",
                "container_name": "example-worker",
                "expected_compose_project": "example-stack",
                "expected_compose_service": "worker",
                "allowed_actions": ["start", "stop", "restart"],
                "timeout_seconds": 30,
                "health_url": "http://127.0.0.1:8080/health",
                "confirmation_level": "normal",
            }
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
    }


class DockerRunner:
    def __init__(self, *, fail_action: bool = False, time_out: bool = False):
        self.state = "running"
        self.calls: list[tuple[list[str], dict]] = []
        self.fail_action = fail_action
        self.time_out = time_out

    def __call__(self, arguments, **kwargs):
        self.calls.append((list(arguments), dict(kwargs)))
        if self.time_out and arguments[1] in {"start", "stop", "restart"}:
            raise subprocess.TimeoutExpired(arguments, kwargs["timeout"])
        if arguments[1:3] == ["inspect", "--format"]:
            template = arguments[3]
            if "compose.project\"" in template:
                output = "example-stack\n"
            elif "compose.service\"" in template:
                output = "worker\n"
            else:
                output = f"{self.state}\n"
            return subprocess.CompletedProcess(arguments, 0, output, "")
        if arguments[1] in {"start", "stop", "restart"}:
            if self.fail_action:
                return subprocess.CompletedProcess(arguments, 1, "secret stdout", "secret stderr")
            self.state = "exited" if arguments[1] == "stop" else "running"
            return subprocess.CompletedProcess(arguments, 0, "example-worker\n", "")
        raise AssertionError(f"unexpected command: {arguments}")


class HealthyResponse:
    status = 200

    def close(self) -> None:
        pass


def _request(action: str = "restart", *, service_id: str = "example-worker") -> dict:
    return {
        "service_id": service_id,
        "action": action,
        "action_id": str(uuid4()),
    }


@pytest.mark.parametrize("action", ["start", "stop", "restart"])
def test_helper_runs_only_exact_container_actions(
    helper_module: ModuleType,
    action: str,
) -> None:
    registry = helper_module.validate_registry(_registry_document())
    runner = DockerRunner()

    result = helper_module.execute_request(
        _request(action),
        registry,
        runner=runner,
        health_opener=lambda *_args, **_kwargs: HealthyResponse(),
    )

    assert result["status"] == "succeeded"
    action_calls = [call for call, _kwargs in runner.calls if call[1] == action]
    assert len(action_calls) == 1
    assert action_calls[0][-1] == "example-worker"
    assert all("shell" not in kwargs for _call, kwargs in runner.calls)


def test_helper_rejects_failed_command_without_returning_output(
    helper_module: ModuleType,
) -> None:
    registry = helper_module.validate_registry(_registry_document())

    with pytest.raises(helper_module.HelperFailure) as caught:
        helper_module.execute_request(
            _request("restart"),
            registry,
            runner=DockerRunner(fail_action=True),
            health_opener=lambda *_args, **_kwargs: HealthyResponse(),
        )

    assert caught.value.code == "operation_failed"
    assert "secret" not in caught.value.summary


def test_helper_reports_command_timeout(helper_module: ModuleType) -> None:
    registry = helper_module.validate_registry(_registry_document())

    with pytest.raises(helper_module.HelperFailure) as caught:
        helper_module.execute_request(
            _request("restart"),
            registry,
            runner=DockerRunner(time_out=True),
            health_opener=lambda *_args, **_kwargs: HealthyResponse(),
        )

    assert caught.value.status_value == "timed_out"
    assert caught.value.code == "operation_timeout"


@pytest.mark.parametrize(
    "extra",
    [
        {"container_name": "other"},
        {"command": "/bin/sh"},
        {"path": "/tmp/unsafe"},
        {"environment": {"PATH": "/tmp"}},
    ],
)
def test_helper_rejects_extra_request_fields(
    helper_module: ModuleType,
    extra: dict,
) -> None:
    registry = helper_module.validate_registry(_registry_document())
    payload = _request()
    payload.update(extra)

    with pytest.raises(helper_module.HelperFailure) as caught:
        helper_module.execute_request(payload, registry)

    assert caught.value.status_value == "rejected"
    assert caught.value.code == "request_invalid"


@pytest.mark.parametrize("action", ["shell", "remove", "exec", "compose"])
def test_helper_rejects_arbitrary_actions(
    helper_module: ModuleType,
    action: str,
) -> None:
    registry = helper_module.validate_registry(_registry_document())

    with pytest.raises(helper_module.HelperFailure) as caught:
        helper_module.execute_request(_request(action), registry)

    assert caught.value.code == "request_invalid"


def test_helper_rejects_mismatched_container_identity(
    helper_module: ModuleType,
) -> None:
    registry = helper_module.validate_registry(_registry_document())
    runner = DockerRunner()
    registry["services"][0]["expected_compose_project"] = "different-stack"

    with pytest.raises(helper_module.HelperFailure) as caught:
        helper_module.execute_request(_request(), registry, runner=runner)

    assert caught.value.status_value == "rejected"
    assert caught.value.code == "target_identity_mismatch"


def test_helper_validates_registry_metadata(helper_module: ModuleType, tmp_path: Path) -> None:
    registry_path = tmp_path / "registry.yml"
    registry_path.write_text(
        yaml.safe_dump(_registry_document(), sort_keys=False),
        encoding="utf-8",
    )

    loaded = helper_module.load_registry(registry_path.resolve(), enforce_metadata=False)

    assert loaded["services"][0]["id"] == "example-worker"


def test_helper_rejects_shell_metacharacters_in_registry(
    helper_module: ModuleType,
) -> None:
    document = _registry_document()
    document["services"][0]["container_name"] = "worker;id"

    with pytest.raises(helper_module.HelperFailure) as caught:
        helper_module.validate_registry(document)

    assert caught.value.code == "registry_invalid"


class FakeWakeSocket:
    def __init__(self) -> None:
        self.options: list[tuple[int, int, object]] = []
        self.packet: bytes | None = None
        self.destination: tuple[str, int] | None = None

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def setsockopt(self, level, option, value):
        self.options.append((level, option, value))

    def sendto(self, packet: bytes, destination: tuple[str, int]):
        self.packet = packet
        self.destination = destination
        return len(packet)


def test_wake_packet_reuses_existing_magic_packet_contract(
    helper_module: ModuleType,
    monkeypatch,
) -> None:
    registry = helper_module.validate_registry(_registry_document())
    wake_socket = FakeWakeSocket()

    def runner(arguments, **_kwargs):
        assert arguments == [
            helper_module.IP_BINARY,
            "-j",
            "address",
            "show",
            "dev",
            "example0",
        ]
        payload = [
            {
                "addr_info": [
                    {
                        "family": "inet",
                        "broadcast": "192.0.2.255",
                    }
                ]
            }
        ]
        return subprocess.CompletedProcess(arguments, 0, json.dumps(payload), "")

    monkeypatch.setattr(helper_module.socket, "if_nametoindex", lambda _name: 2)
    result = helper_module.execute_request(
        _request("wake", service_id="main-pc"),
        registry,
        runner=runner,
        socket_factory=lambda *_args: wake_socket,
    )

    assert result["status"] == "succeeded"
    assert wake_socket.packet == build_magic_packet("AA:BB:CC:DD:EE:FF")
    assert len(wake_socket.packet or b"") == 102
    assert wake_socket.destination == ("192.0.2.255", 9)


def test_helper_source_never_enables_shell_execution() -> None:
    helper_path = (
        Path(__file__).parents[2]
        / "deploy/scripts/linux-monitor-dashboard-action-helper.py"
    )
    source = helper_path.read_text(encoding="utf-8")
    syntax_tree = ast.parse(source)

    assert "shell=True" not in source
    for call in (node for node in ast.walk(syntax_tree) if isinstance(node, ast.Call)):
        assert not any(
            keyword.arg == "shell"
            and isinstance(keyword.value, ast.Constant)
            and keyword.value.value is True
            for keyword in call.keywords
        )


def test_sudoers_allows_only_no_argument_helper() -> None:
    sudoers = (
        Path(__file__).parents[2]
        / "deploy/sudoers/linux-monitor-dashboard-action"
    ).read_text(encoding="utf-8")

    assert '/usr/local/libexec/linux-monitor-dashboard-action-helper ""' in sudoers
    assert "Defaults:linux-monitor-action !pam_acct_mgmt" in sudoers
    assert "systemctl" not in sudoers
    assert "/usr/bin/docker" not in sudoers
    assert "ALL=(ALL)" not in sudoers
    assert "NOPASSWD: ALL" not in sudoers
