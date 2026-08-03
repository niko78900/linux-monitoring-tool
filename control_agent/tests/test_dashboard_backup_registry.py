from __future__ import annotations

import importlib.util
from copy import deepcopy
from pathlib import Path

import pytest
import yaml

from app.services import backup_registry as backup_registry_module
from app.services.backup_registry import RegistryValidationError, validate_backup_registry


def _document(tmp_path: Path) -> tuple[dict, dict]:
    cold = tmp_path / "cold"
    destination = cold / "backups"
    warm = tmp_path / "warm"
    source = warm / "example"
    forbidden = tmp_path / "postgres-data"
    cold.mkdir()
    destination.mkdir()
    source.mkdir(parents=True)
    forbidden.mkdir()
    config_file = source / "compose.yml"
    config_file.write_text("services: {}\n", encoding="utf-8")
    document = {
        "version": 1,
        "cold_mount": str(cold),
        "destination_root": str(destination),
        "raid_device": "/dev/md0",
        "minimum_free_bytes": 1_073_741_824,
        "capacity_overhead_percent": 10,
        "plans": [
            {
                "id": "config",
                "display_name": "Configuration",
                "description": "Reviewed configuration files.",
                "enabled": True,
                "destination": str(destination / "config"),
                "timeout_seconds": 600,
                "estimated_size_bytes": 1024,
                "confirmation_level": "high",
                "retention": {"mode": "manual", "retain_at_least": 2},
                "steps": [
                    {
                        "type": "copy_files",
                        "sources": [str(config_file)],
                        "component": "configuration",
                    },
                    {"type": "verification", "mode": "sha256"},
                    {"type": "manifest"},
                ],
            }
        ],
    }
    context = {
        "expected_cold_mount": cold,
        "expected_destination_root": destination,
        "approved_source_roots": (warm,),
        "forbidden_postgres_roots": (forbidden,),
    }
    return document, context


def _validate(tmp_path: Path, document: dict):
    _, context = _document(tmp_path / "context")
    return validate_backup_registry(document, **context)


def test_registry_accepts_strict_supported_steps(tmp_path: Path) -> None:
    document, context = _document(tmp_path)
    registry = validate_backup_registry(document, **context)

    assert registry.get_plan("config") is not None
    assert registry.fingerprint


def test_api_and_helper_registry_fingerprints_match(tmp_path: Path) -> None:
    document, context = _document(tmp_path)
    api_registry = validate_backup_registry(document, **context)
    helper_path = Path(__file__).parents[2] / "deploy/scripts/linux-monitor-dashboard-backup-helper.py"
    spec = importlib.util.spec_from_file_location("backup_helper_registry_test", helper_path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    helper_registry = module.validate_registry(document, **context)

    assert api_registry.fingerprint == module.registry_fingerprint(helper_registry)


def test_tracked_example_is_structurally_valid() -> None:
    root = Path(__file__).parents[2]
    payload = yaml.safe_load(
        (root / "control_agent/config/dashboard-backups.example.yml").read_text(encoding="utf-8")
    )

    registry = validate_backup_registry(payload, check_paths=False)

    assert {plan.id for plan in registry.plans} == {
        "immich-database",
        "immich-full",
        "homelab-config",
        "warm-storage",
    }


def test_credential_copy_validation_does_not_probe_root_only_paths(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    document, context = _document(tmp_path)

    def fail_if_probed(*_args, **_kwargs) -> None:
        raise PermissionError("root-only destination")

    monkeypatch.setattr(
        backup_registry_module,
        "_has_symlink_component",
        fail_if_probed,
    )

    registry = validate_backup_registry(document, check_paths=False, **context)

    assert registry.get_plan("config") is not None


@pytest.mark.parametrize(
    ("mutation",),
    [
        (lambda document: document["plans"][0]["steps"][0].update({"type": "shell"}),),
        (lambda document: document["plans"][0].update({"timeout_seconds": 0}),),
        (lambda document: document["plans"][0].update({"retention": {"mode": "automatic", "retain_at_least": 2}}),),
        (lambda document: document["plans"][0]["steps"][0]["sources"].append("relative/path"),),
        (lambda document: document["plans"][0]["steps"][0]["sources"].append("/tmp/unsafe;command"),),
        (lambda document: document["plans"][0].update({"unexpected": True}),),
        (lambda document: document["plans"][0].update({"display_name": "Config; command"}),),
    ],
)
def test_registry_rejects_unknown_unsafe_or_malformed_fields(
    tmp_path: Path,
    mutation,
) -> None:
    document, context = _document(tmp_path)
    mutation(document)

    with pytest.raises(RegistryValidationError):
        validate_backup_registry(document, **context)


def test_registry_rejects_duplicate_plan_ids(tmp_path: Path) -> None:
    document, context = _document(tmp_path)
    document["plans"].append(deepcopy(document["plans"][0]))

    with pytest.raises(RegistryValidationError):
        validate_backup_registry(document, **context)


def test_registry_rejects_source_destination_overlap(tmp_path: Path) -> None:
    document, context = _document(tmp_path)
    plan = document["plans"][0]
    plan["steps"][0] = {
        "type": "rsync_snapshot",
        "source": document["destination_root"],
        "component": "configuration",
        "excludes": [],
        "allow_source_root": False,
        "consistency": "point_in_time",
    }
    context["approved_source_roots"] = (Path(document["cold_mount"]),)

    with pytest.raises(RegistryValidationError):
        validate_backup_registry(document, **context)


def test_registry_rejects_source_outside_approved_roots(tmp_path: Path) -> None:
    document, context = _document(tmp_path)
    outside = tmp_path / "outside.yml"
    outside.write_text("outside\n", encoding="utf-8")
    document["plans"][0]["steps"][0]["sources"] = [str(outside)]

    with pytest.raises(RegistryValidationError):
        validate_backup_registry(document, **context)


def test_registry_rejects_symlink_escape(tmp_path: Path) -> None:
    document, context = _document(tmp_path)
    outside = tmp_path / "outside.yml"
    outside.write_text("outside\n", encoding="utf-8")
    link = Path(context["approved_source_roots"][0]) / "linked.yml"
    link.symlink_to(outside)
    document["plans"][0]["steps"][0]["sources"] = [str(link)]

    with pytest.raises(RegistryValidationError):
        validate_backup_registry(document, **context)


def test_registry_rejects_live_postgres_storage_copy(tmp_path: Path) -> None:
    document, context = _document(tmp_path)
    forbidden = context["forbidden_postgres_roots"][0]
    data_file = forbidden / "base.dat"
    data_file.write_bytes(b"live")
    context["approved_source_roots"] = (
        *context["approved_source_roots"],
        forbidden.parent,
    )
    document["plans"][0]["steps"][0]["sources"] = [str(data_file)]

    with pytest.raises(RegistryValidationError):
        validate_backup_registry(document, **context)


def test_registry_rejects_wildcard_source_root(tmp_path: Path) -> None:
    document, context = _document(tmp_path)
    document["plans"][0]["steps"][0]["sources"] = [
        str(context["approved_source_roots"][0] / "*")
    ]

    with pytest.raises(RegistryValidationError):
        validate_backup_registry(document, **context)
