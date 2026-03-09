from __future__ import annotations

from pydantic import BaseModel, Field


class DockerContainerInfo(BaseModel):
    id: str
    name: str
    image: str
    state: str
    status: str
    ports: dict[str, list[str]]
    created: str | None = None
    running_for: str | None = None


class DockerResponse(BaseModel):
    docker_available: bool
    reason: str | None = None
    container_count: int = Field(ge=0)
    containers: list[DockerContainerInfo] = Field(default_factory=list)


class DockerSummaryResponse(BaseModel):
    docker_available: bool
    running_containers: int = Field(ge=0)
