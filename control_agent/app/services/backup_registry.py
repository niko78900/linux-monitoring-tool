from __future__ import annotations

import hashlib
import json
import os
import re
import stat
from pathlib import Path
from typing import Annotated, Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator

DEFAULT_COLD_MOUNT = Path("/mnt/storage")
DEFAULT_DESTINATION_ROOT = Path("/mnt/storage/backups")
APPROVED_SOURCE_ROOTS = (
    Path("/mnt/warm"),
    Path("/etc/linux-monitor"),
    Path("/etc/systemd/system"),
    Path("/etc/ufw"),
    Path("/opt/homelab"),
)
FORBIDDEN_POSTGRES_ROOTS: tuple[Path, ...] = ()
MAX_REGISTRY_BYTES = 262_144

ID_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")
TARGET_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.@-]{0,127}$")
FILENAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
SAFE_GLOB_PATTERN = re.compile(r"^[A-Za-z0-9_./*?\[\]-]{1,160}$")
SHELL_METACHARACTERS = frozenset("$`;&|><\\\n\r\x00")


class RegistryValidationError(RuntimeError):
    pass


def _safe_human_text(value: str, *, label: str, maximum: int) -> str:
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ValueError(f"{label} contains control characters")
    if any(character in SHELL_METACHARACTERS for character in value):
        raise ValueError(f"{label} contains forbidden characters")
    normalized = " ".join(value.split())
    if not normalized or len(normalized) > maximum:
        raise ValueError(f"{label} has an invalid length")
    return normalized


def _safe_target(value: str, *, label: str) -> str:
    normalized = value.strip()
    if (
        not TARGET_PATTERN.fullmatch(normalized)
        or any(character in SHELL_METACHARACTERS for character in normalized)
    ):
        raise ValueError(f"{label} is invalid")
    return normalized


def _absolute_path(value: object, *, label: str) -> Path:
    if not isinstance(value, (str, Path)):
        raise ValueError(f"{label} must be a path")
    raw_value = os.fspath(value)
    if (
        not raw_value.startswith("/")
        or any(character in SHELL_METACHARACTERS for character in raw_value)
        or any(character in raw_value for character in "*?[]{}")
    ):
        raise ValueError(f"{label} must be an exact absolute path")
    path = Path(raw_value)
    if ".." in path.parts or "." in path.parts:
        raise ValueError(f"{label} contains path traversal")
    return path


class RetentionPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: Literal["manual"] = "manual"
    retain_at_least: int = Field(default=1, ge=1, le=1000, strict=True)


class RsyncSnapshotStep(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["rsync_snapshot"]
    source: Path
    component: str
    excludes: list[str] = Field(default_factory=list, max_length=128)
    allow_source_root: bool = False
    consistency: Literal["point_in_time", "best_effort_live"] = "point_in_time"

    @field_validator("source", mode="before")
    @classmethod
    def validate_source(cls, value: object) -> Path:
        return _absolute_path(value, label="rsync source")

    @field_validator("component")
    @classmethod
    def validate_component(cls, value: str) -> str:
        if not ID_PATTERN.fullmatch(value):
            raise ValueError("component is invalid")
        return value

    @field_validator("excludes")
    @classmethod
    def validate_excludes(cls, values: list[str]) -> list[str]:
        if len(values) != len(set(values)):
            raise ValueError("rsync exclusions must be unique")
        for value in values:
            if (
                not SAFE_GLOB_PATTERN.fullmatch(value)
                or value.startswith("/")
                or ".." in Path(value).parts
                or any(character in SHELL_METACHARACTERS for character in value)
            ):
                raise ValueError("rsync exclusion is invalid")
        return values


class PostgresDumpStep(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["postgres_dump"]
    container: str
    expected_compose_project: str
    expected_compose_service: str
    database: str
    role: str
    component: str = "database"
    filename: str = "database.dump"
    timeout_seconds: int = Field(default=1800, ge=30, le=86_400, strict=True)

    @field_validator(
        "container",
        "expected_compose_project",
        "expected_compose_service",
        "database",
        "role",
    )
    @classmethod
    def validate_target(cls, value: str) -> str:
        return _safe_target(value, label="PostgreSQL target")

    @field_validator("component")
    @classmethod
    def validate_component(cls, value: str) -> str:
        if not ID_PATTERN.fullmatch(value):
            raise ValueError("component is invalid")
        return value

    @field_validator("filename")
    @classmethod
    def validate_filename(cls, value: str) -> str:
        if not FILENAME_PATTERN.fullmatch(value):
            raise ValueError("dump filename is invalid")
        return value


class CopyFilesStep(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["copy_files"]
    sources: list[Path] = Field(min_length=1, max_length=256)
    component: str

    @field_validator("sources", mode="before")
    @classmethod
    def validate_sources(cls, value: object) -> list[Path]:
        if not isinstance(value, list):
            raise ValueError("copy sources must be a list")
        return [_absolute_path(item, label="copy source") for item in value]

    @field_validator("sources")
    @classmethod
    def validate_unique_sources(cls, values: list[Path]) -> list[Path]:
        if len(values) != len(set(values)):
            raise ValueError("copy sources must be unique")
        return values

    @field_validator("component")
    @classmethod
    def validate_component(cls, value: str) -> str:
        if not ID_PATTERN.fullmatch(value):
            raise ValueError("component is invalid")
        return value


class VerificationStep(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["verification"]
    mode: Literal["sha256", "inventory"] = "sha256"


class ManifestStep(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["manifest"]


BackupStep = Annotated[
    RsyncSnapshotStep
    | PostgresDumpStep
    | CopyFilesStep
    | VerificationStep
    | ManifestStep,
    Field(discriminator="type"),
]


class BackupPlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    display_name: str
    description: str
    enabled: bool
    disabled_reason: str | None = None
    destination: Path
    timeout_seconds: int = Field(ge=60, le=604_800, strict=True)
    estimated_size_bytes: int = Field(ge=1, le=10_000_000_000_000, strict=True)
    confirmation_level: Literal["high"] = "high"
    retention: RetentionPolicy
    steps: list[BackupStep] = Field(min_length=3, max_length=32)

    @field_validator("id")
    @classmethod
    def validate_id(cls, value: str) -> str:
        if not ID_PATTERN.fullmatch(value):
            raise ValueError("plan id is invalid")
        return value

    @field_validator("display_name")
    @classmethod
    def validate_display_name(cls, value: str) -> str:
        return _safe_human_text(value, label="display name", maximum=80)

    @field_validator("description")
    @classmethod
    def validate_description(cls, value: str) -> str:
        return _safe_human_text(value, label="description", maximum=300)

    @field_validator("disabled_reason")
    @classmethod
    def validate_disabled_reason(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return _safe_human_text(value, label="disabled reason", maximum=240)

    @field_validator("destination", mode="before")
    @classmethod
    def validate_destination(cls, value: object) -> Path:
        return _absolute_path(value, label="plan destination")

    @model_validator(mode="after")
    def validate_steps(self) -> "BackupPlan":
        if self.enabled and self.disabled_reason is not None:
            raise ValueError("enabled plans cannot have a disabled reason")
        if not self.enabled and self.disabled_reason is None:
            raise ValueError("disabled plans require a blocking reason")
        step_types = [step.type for step in self.steps]
        if step_types.count("manifest") != 1 or step_types.count("verification") != 1:
            raise ValueError("plans require exactly one verification and manifest step")
        if step_types[-2:] != ["verification", "manifest"]:
            raise ValueError("verification and manifest must be the final plan steps")
        data_steps = step_types[:-2]
        if not data_steps or any(step in {"verification", "manifest"} for step in data_steps):
            raise ValueError("plan data steps are invalid")
        components = [
            step.component
            for step in self.steps
            if isinstance(step, (RsyncSnapshotStep, PostgresDumpStep, CopyFilesStep))
        ]
        if len(components) != len(set(components)):
            raise ValueError("plan components must be unique")
        return self


class BackupRegistry(BaseModel):
    model_config = ConfigDict(extra="forbid")

    version: Literal[1]
    cold_mount: Path
    destination_root: Path
    raid_device: Path
    minimum_free_bytes: int = Field(
        ge=1_073_741_824,
        le=2_199_023_255_552,
        strict=True,
    )
    capacity_overhead_percent: int = Field(default=10, ge=0, le=100, strict=True)
    plans: list[BackupPlan] = Field(min_length=1, max_length=32)

    @field_validator("cold_mount", "destination_root", "raid_device", mode="before")
    @classmethod
    def validate_absolute_setting(cls, value: object) -> Path:
        return _absolute_path(value, label="registry path")

    @model_validator(mode="after")
    def validate_plan_ids(self) -> "BackupRegistry":
        identifiers = [plan.id for plan in self.plans]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError("duplicate backup plan ids are forbidden")
        return self

    def get_plan(self, plan_id: str) -> BackupPlan | None:
        return next((plan for plan in self.plans if plan.id == plan_id), None)

    @property
    def fingerprint(self) -> str:
        payload = self.model_dump(mode="json")
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


def load_backup_registry(
    path: Path,
    *,
    enforce_metadata: bool = True,
    check_paths: bool = True,
    expected_cold_mount: Path = DEFAULT_COLD_MOUNT,
    expected_destination_root: Path = DEFAULT_DESTINATION_ROOT,
    approved_source_roots: tuple[Path, ...] = APPROVED_SOURCE_ROOTS,
    forbidden_postgres_roots: tuple[Path, ...] = FORBIDDEN_POSTGRES_ROOTS,
) -> BackupRegistry:
    if not path.is_absolute():
        raise RegistryValidationError("Backup registry validation failed.")
    try:
        metadata = path.lstat()
        parent_metadata = path.parent.stat()
    except OSError as error:
        raise RegistryValidationError("Backup registry is unavailable.") from error
    if metadata.st_size > MAX_REGISTRY_BYTES:
        raise RegistryValidationError("Backup registry validation failed.")
    if enforce_metadata and (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_gid != 0
        or stat.S_IMODE(metadata.st_mode) != 0o600
        or not stat.S_ISDIR(parent_metadata.st_mode)
        or parent_metadata.st_uid != 0
        or parent_metadata.st_gid != 0
        or stat.S_IMODE(parent_metadata.st_mode) & 0o022
    ):
        raise RegistryValidationError("Backup registry permissions are invalid.")
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, yaml.YAMLError) as error:
        raise RegistryValidationError("Backup registry validation failed.") from error
    return validate_backup_registry(
        payload,
        check_paths=check_paths,
        expected_cold_mount=expected_cold_mount,
        expected_destination_root=expected_destination_root,
        approved_source_roots=approved_source_roots,
        forbidden_postgres_roots=forbidden_postgres_roots,
    )


def validate_backup_registry(
    payload: object,
    *,
    check_paths: bool = True,
    expected_cold_mount: Path = DEFAULT_COLD_MOUNT,
    expected_destination_root: Path = DEFAULT_DESTINATION_ROOT,
    approved_source_roots: tuple[Path, ...] = APPROVED_SOURCE_ROOTS,
    forbidden_postgres_roots: tuple[Path, ...] = FORBIDDEN_POSTGRES_ROOTS,
) -> BackupRegistry:
    try:
        registry = BackupRegistry.model_validate(payload)
        _validate_registry_paths(
            registry,
            check_paths=check_paths,
            expected_cold_mount=expected_cold_mount,
            expected_destination_root=expected_destination_root,
            approved_source_roots=approved_source_roots,
            forbidden_postgres_roots=forbidden_postgres_roots,
        )
    except (OSError, ValidationError, ValueError) as error:
        raise RegistryValidationError("Backup registry validation failed.") from error
    return registry


def _validate_registry_paths(
    registry: BackupRegistry,
    *,
    check_paths: bool,
    expected_cold_mount: Path,
    expected_destination_root: Path,
    approved_source_roots: tuple[Path, ...],
    forbidden_postgres_roots: tuple[Path, ...],
) -> None:
    cold_mount = _resolved(registry.cold_mount, strict=check_paths)
    destination_root = _resolved(registry.destination_root, strict=False)
    if cold_mount != _resolved(expected_cold_mount, strict=check_paths):
        raise ValueError("cold mount is not approved")
    if destination_root != _resolved(expected_destination_root, strict=False):
        raise ValueError("destination root is not approved")
    if destination_root.parent != cold_mount:
        raise ValueError("destination root must be directly below the cold mount")
    if not re.fullmatch(r"/dev/md[0-9]+", str(registry.raid_device)):
        raise ValueError("RAID device is invalid")
    if check_paths and _has_symlink_component(registry.cold_mount, require_leaf=True):
        raise ValueError("cold mount contains a symlink")
    if check_paths and _has_symlink_component(registry.destination_root, require_leaf=True):
        raise ValueError("destination root contains a symlink")

    resolved_approved = tuple(_resolved(root, strict=check_paths) for root in approved_source_roots)
    resolved_forbidden = tuple(_resolved(root, strict=False) for root in forbidden_postgres_roots)

    for plan in registry.plans:
        plan_destination = _resolved(plan.destination, strict=False)
        if plan_destination.parent != destination_root or plan_destination.name != plan.id:
            raise ValueError("plan destination is outside its approved root")
        if check_paths and _has_symlink_component(plan.destination, require_leaf=True):
            raise ValueError("plan destination contains a symlink")
        for step in plan.steps:
            if isinstance(step, RsyncSnapshotStep):
                _validate_source(
                    step.source,
                    destination_root=destination_root,
                    approved_roots=resolved_approved,
                    forbidden_roots=resolved_forbidden,
                    check_paths=check_paths,
                    require_directory=True,
                    allow_source_root=step.allow_source_root,
                )
            elif isinstance(step, CopyFilesStep):
                for source in step.sources:
                    _validate_source(
                        source,
                        destination_root=destination_root,
                        approved_roots=resolved_approved,
                        forbidden_roots=resolved_forbidden,
                        check_paths=check_paths,
                        require_directory=False,
                        allow_source_root=False,
                    )


def _validate_source(
    source: Path,
    *,
    destination_root: Path,
    approved_roots: tuple[Path, ...],
    forbidden_roots: tuple[Path, ...],
    check_paths: bool,
    require_directory: bool,
    allow_source_root: bool,
) -> None:
    if check_paths and _has_symlink_component(source, require_leaf=True):
        raise ValueError("source contains a symlink")
    resolved = _resolved(source, strict=check_paths)
    matching_roots = [root for root in approved_roots if _within(resolved, root)]
    if not matching_roots:
        raise ValueError("source is outside approved roots")
    if resolved in matching_roots and not allow_source_root:
        raise ValueError("approved source roots require explicit approval")
    if _overlaps(resolved, destination_root):
        raise ValueError("source and destination overlap")
    if any(_overlaps(resolved, forbidden) for forbidden in forbidden_roots):
        raise ValueError("live PostgreSQL storage cannot be copied")
    if _is_postgres_data_path(resolved):
        raise ValueError("live PostgreSQL storage cannot be copied")
    if check_paths:
        if require_directory and not resolved.is_dir():
            raise ValueError("rsync source is not a directory")
        if not require_directory and not resolved.is_file():
            raise ValueError("copy source is not a regular file")


def _resolved(path: Path, *, strict: bool) -> Path:
    return path.resolve(strict=strict)


def _within(path: Path, root: Path) -> bool:
    return path == root or path.is_relative_to(root)


def _overlaps(left: Path, right: Path) -> bool:
    return _within(left, right) or _within(right, left)


def _has_symlink_component(path: Path, *, require_leaf: bool) -> bool:
    current = Path(path.anchor)
    parts = path.parts[1:]
    for index, part in enumerate(parts):
        current /= part
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            if require_leaf or index < len(parts) - 1:
                return False
            return False
        if stat.S_ISLNK(metadata.st_mode):
            return True
    return False


def _is_postgres_data_path(path: Path) -> bool:
    candidate = path if path.is_dir() else path.parent
    for parent in (candidate, *candidate.parents):
        try:
            if (parent / "PG_VERSION").is_file():
                return True
        except OSError:
            return True
    return False
