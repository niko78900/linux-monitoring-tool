from __future__ import annotations

import re
from ipaddress import IPv4Address
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

import yaml
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from ..models.dashboard_actions import (
    ConfirmationLevel,
    RuntimeKind,
    ServiceAction,
)

ID_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")
TARGET_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.@-]{0,127}$")
INTERFACE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,31}$")
MAC_PATTERN = re.compile(r"^(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")
SHELL_METACHARACTERS = frozenset("$`;&|><\\\n\r")

FORBIDDEN_SYSTEMD_UNITS = {
    "containerd.service",
    "docker.service",
    "linux-monitor-dashboard-action.service",
    "linux-monitor-dashboard-read-bridge.service",
    "networking.service",
    "smbd.service",
    "ssh.service",
    "sshd.service",
    "tailscaled.service",
    "ufw.service",
}
FORBIDDEN_CONTAINER_FRAGMENTS = (
    "dashboard-backend",
    "dashboard-frontend",
    "immich_machine_learning",
    "immich_postgres",
    "immich_redis",
)
FORBIDDEN_CONTAINERS = {"portainer"}


def _reject_unsafe_text(value: str, *, label: str) -> str:
    normalized = value.strip()
    if not normalized:
        raise ValueError(f"{label} cannot be empty")
    if any(character in SHELL_METACHARACTERS for character in normalized):
        raise ValueError(f"{label} contains forbidden characters")
    return normalized


class ManagedActionService(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    name: str = Field(min_length=1, max_length=80)
    kind: RuntimeKind
    allowed_actions: list[ServiceAction] = Field(min_length=1, max_length=3)
    timeout_seconds: int = Field(default=90, ge=5, le=300, strict=True)
    health_url: str | None = None
    confirmation_level: ConfirmationLevel = "normal"
    container_name: str | None = None
    expected_compose_project: str | None = None
    expected_compose_service: str | None = None
    systemd_unit: str | None = None

    @field_validator("id")
    @classmethod
    def validate_id(cls, value: str) -> str:
        if not ID_PATTERN.fullmatch(value):
            raise ValueError("service id is invalid")
        return value

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        return _reject_unsafe_text(value, label="service name")

    @field_validator(
        "container_name",
        "expected_compose_project",
        "expected_compose_service",
        "systemd_unit",
    )
    @classmethod
    def validate_runtime_target(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = _reject_unsafe_text(value, label="runtime target")
        if not TARGET_PATTERN.fullmatch(normalized):
            raise ValueError("runtime target is invalid")
        return normalized

    @field_validator("allowed_actions")
    @classmethod
    def validate_unique_actions(
        cls, value: list[ServiceAction]
    ) -> list[ServiceAction]:
        if len(set(value)) != len(value):
            raise ValueError("allowed actions must be unique")
        return value

    @field_validator("health_url")
    @classmethod
    def validate_health_url(cls, value: str | None) -> str | None:
        if value is None:
            return None
        parsed = urlsplit(value)
        if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost"}:
            raise ValueError("health URL must use HTTP on loopback")
        if parsed.username or parsed.password or parsed.fragment:
            raise ValueError("health URL contains unsupported components")
        try:
            parsed_port = parsed.port
        except ValueError as error:
            raise ValueError("health URL port is invalid") from error
        if parsed_port is None:
            raise ValueError("health URL must contain an explicit port")
        return value

    @model_validator(mode="after")
    def validate_adapter_fields(self) -> "ManagedActionService":
        if self.kind == "docker_container":
            if not all(
                (
                    self.container_name,
                    self.expected_compose_project,
                    self.expected_compose_service,
                )
            ):
                raise ValueError("docker container identity is incomplete")
            if self.systemd_unit is not None:
                raise ValueError("docker service cannot define a systemd unit")
            container = self.container_name or ""
            if container in FORBIDDEN_CONTAINERS or any(
                fragment in container for fragment in FORBIDDEN_CONTAINER_FRAGMENTS
            ):
                raise ValueError("container is explicitly excluded from actions")
        elif self.kind == "systemd":
            if self.systemd_unit is None or not self.systemd_unit.endswith(".service"):
                raise ValueError("systemd service requires an exact .service unit")
            if any(
                value is not None
                for value in (
                    self.container_name,
                    self.expected_compose_project,
                    self.expected_compose_service,
                )
            ):
                raise ValueError("systemd service cannot define container fields")
            if self.systemd_unit in FORBIDDEN_SYSTEMD_UNITS:
                raise ValueError("systemd unit is explicitly excluded from actions")
        return self


class WakeTarget(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: Literal["main-pc"]
    name: str = Field(min_length=1, max_length=80)
    allowed_actions: list[Literal["wake"]]
    mac_address: str
    broadcast_address: IPv4Address
    interface: str
    port: int = Field(default=9, ge=1, le=65535, strict=True)
    timeout_seconds: int = Field(default=10, ge=1, le=30, strict=True)
    confirmation_level: ConfirmationLevel = "normal"

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        return _reject_unsafe_text(value, label="wake target name")

    @field_validator("allowed_actions")
    @classmethod
    def validate_wake_actions(cls, value: list[Literal["wake"]]) -> list[Literal["wake"]]:
        if value != ["wake"]:
            raise ValueError("wake target must allow exactly one wake action")
        return value

    @field_validator("mac_address")
    @classmethod
    def validate_mac(cls, value: str) -> str:
        if not MAC_PATTERN.fullmatch(value):
            raise ValueError("wake target MAC address is invalid")
        return value.upper()

    @field_validator("broadcast_address")
    @classmethod
    def validate_broadcast(cls, value: IPv4Address) -> IPv4Address:
        if value.is_loopback or value.is_multicast or value.is_unspecified:
            raise ValueError("wake broadcast address is invalid")
        return value

    @field_validator("interface")
    @classmethod
    def validate_interface(cls, value: str) -> str:
        normalized = _reject_unsafe_text(value, label="wake interface")
        if not INTERFACE_PATTERN.fullmatch(normalized):
            raise ValueError("wake interface is invalid")
        return normalized


class ActionRegistry(BaseModel):
    model_config = ConfigDict(extra="forbid")

    services: list[ManagedActionService] = Field(default_factory=list)
    wake_targets: list[WakeTarget] = Field(default_factory=list, max_length=1)

    @model_validator(mode="after")
    def validate_unique_ids(self) -> "ActionRegistry":
        identifiers = [item.id for item in self.services] + [
            item.id for item in self.wake_targets
        ]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError("registry target IDs must be unique")
        return self

    def get_service(self, service_id: str) -> ManagedActionService | None:
        return next((item for item in self.services if item.id == service_id), None)

    def get_wake_target(self) -> WakeTarget | None:
        return self.wake_targets[0] if self.wake_targets else None


def load_action_registry(path: Path) -> ActionRegistry:
    if not path.is_absolute():
        raise ValueError("action registry path must be absolute")
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError("action registry is unavailable") from error
    try:
        payload = yaml.safe_load(raw_text)
    except yaml.YAMLError as error:
        raise ValueError("action registry is invalid YAML") from error
    if not isinstance(payload, dict):
        raise ValueError("action registry must be a mapping")
    try:
        return ActionRegistry.model_validate(payload)
    except ValueError as error:
        raise ValueError("action registry validation failed") from error
