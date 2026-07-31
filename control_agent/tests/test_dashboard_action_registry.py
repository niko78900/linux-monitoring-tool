from __future__ import annotations

from copy import deepcopy
from pathlib import Path

import pytest
import yaml

from app.services.action_registry import load_action_registry


def _document() -> dict:
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


def _load(tmp_path: Path, document: object):
    path = tmp_path / "registry.yml"
    path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
    return load_action_registry(path.resolve())


def test_registry_accepts_explicit_targets(tmp_path: Path) -> None:
    registry = _load(tmp_path, _document())

    assert [service.id for service in registry.services] == ["example-worker"]
    assert registry.get_wake_target().id == "main-pc"


def test_registry_rejects_duplicate_ids(tmp_path: Path) -> None:
    document = _document()
    document["services"].append(deepcopy(document["services"][0]))

    with pytest.raises(ValueError, match="validation failed"):
        _load(tmp_path, document)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("id", "../../unsafe"),
        ("name", "worker; shutdown"),
        ("container_name", "worker$(id)"),
        ("expected_compose_project", "*"),
        ("expected_compose_service", "worker|shell"),
    ],
)
def test_registry_rejects_unsafe_identifiers(
    tmp_path: Path,
    field: str,
    value: str,
) -> None:
    document = _document()
    document["services"][0][field] = value

    with pytest.raises(ValueError, match="validation failed"):
        _load(tmp_path, document)


def test_registry_rejects_unsafe_path_fields(tmp_path: Path) -> None:
    document = _document()
    document["services"][0]["project_directory"] = "../unsafe"

    with pytest.raises(ValueError, match="validation failed"):
        _load(tmp_path, document)


def test_registry_rejects_unsupported_kind(tmp_path: Path) -> None:
    document = _document()
    document["services"][0]["kind"] = "docker_compose"

    with pytest.raises(ValueError, match="validation failed"):
        _load(tmp_path, document)


@pytest.mark.parametrize("timeout", [0, 301, "90"])
def test_registry_rejects_invalid_timeout(tmp_path: Path, timeout: object) -> None:
    document = _document()
    document["services"][0]["timeout_seconds"] = timeout

    with pytest.raises(ValueError, match="validation failed"):
        _load(tmp_path, document)


@pytest.mark.parametrize(
    "mac_address",
    ["", "AA:BB:CC:DD:EE", "AA:BB:CC:DD:EE:GG", "AA-BB-CC-DD-EE-FF"],
)
def test_registry_rejects_invalid_mac(tmp_path: Path, mac_address: str) -> None:
    document = _document()
    document["wake_targets"][0]["mac_address"] = mac_address

    with pytest.raises(ValueError, match="validation failed"):
        _load(tmp_path, document)


def test_registry_rejects_arbitrary_wake_target(tmp_path: Path) -> None:
    document = _document()
    document["wake_targets"][0]["id"] = "another-pc"

    with pytest.raises(ValueError, match="validation failed"):
        _load(tmp_path, document)


@pytest.mark.parametrize(
    "unit",
    [
        "docker.service",
        "linux-monitor-dashboard-action.service",
        "linux-monitor-dashboard-read-bridge.service",
    ],
)
def test_registry_rejects_protected_systemd_units(tmp_path: Path, unit: str) -> None:
    document = _document()
    document["services"] = [
        {
            "id": "protected-service",
            "name": "Protected Service",
            "kind": "systemd",
            "systemd_unit": unit,
            "allowed_actions": ["restart"],
        }
    ]

    with pytest.raises(ValueError, match="validation failed"):
        _load(tmp_path, document)


def test_registry_rejects_individual_immich_dependency(tmp_path: Path) -> None:
    document = _document()
    document["services"][0]["container_name"] = "immich_postgres"

    with pytest.raises(ValueError, match="validation failed"):
        _load(tmp_path, document)


def test_registry_rejects_relative_registry_path(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.chdir(tmp_path)
    Path("registry.yml").write_text("services: []\n", encoding="utf-8")

    with pytest.raises(ValueError, match="absolute"):
        load_action_registry(Path("registry.yml"))


def test_registry_fails_closed_on_malformed_yaml(tmp_path: Path) -> None:
    path = tmp_path / "registry.yml"
    path.write_text("services: [\n", encoding="utf-8")

    with pytest.raises(ValueError, match="invalid YAML"):
        load_action_registry(path.resolve())
