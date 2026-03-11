from __future__ import annotations

import logging

from app.core.config import get_settings
from app.core.utils import format_duration, parse_docker_timestamp, utc_now
from app.models.docker import DockerContainerInfo, DockerResponse, DockerSummaryResponse

try:
    import docker
    from docker.errors import DockerException
except ImportError:  # pragma: no cover - handled at runtime
    docker = None  # type: ignore[assignment]
    DockerException = Exception  # type: ignore[assignment]

logger = logging.getLogger(__name__)


def get_docker_metrics() -> DockerResponse:
    if docker is None:
        return DockerResponse(
            docker_available=False,
            reason="docker SDK is not installed.",
            container_count=0,
            containers=[],
        )

    client = None
    try:
        client = _create_docker_client()
        raw_containers = client.containers.list(all=True)
        containers = [_to_container_info(item) for item in raw_containers]
        return DockerResponse(
            docker_available=True,
            reason=None,
            container_count=len(containers),
            containers=containers,
        )
    except PermissionError as exc:
        logger.warning("Docker permission issue: %s", exc)
        return DockerResponse(
            docker_available=False,
            reason=f"Docker permission denied: {exc}",
            container_count=0,
            containers=[],
        )
    except DockerException as exc:
        logger.warning("Docker unavailable: %s", exc)
        return DockerResponse(
            docker_available=False,
            reason=f"Docker unavailable: {exc}",
            container_count=0,
            containers=[],
        )
    except Exception as exc:  # pragma: no cover - runtime fallback
        logger.exception("Unexpected Docker metrics failure.")
        return DockerResponse(
            docker_available=False,
            reason=f"Unexpected Docker error: {exc}",
            container_count=0,
            containers=[],
        )
    finally:
        _close_client(client)


def get_docker_summary() -> DockerSummaryResponse:
    if docker is None:
        return DockerSummaryResponse(docker_available=False, running_containers=0)

    client = None
    try:
        client = _create_docker_client()
        running = client.containers.list(all=False)
        return DockerSummaryResponse(docker_available=True, running_containers=len(running))
    except (PermissionError, DockerException) as exc:
        logger.warning("Docker summary unavailable: %s", exc)
        return DockerSummaryResponse(docker_available=False, running_containers=0)
    except Exception as exc:  # pragma: no cover - runtime fallback
        logger.exception("Unexpected Docker summary failure.")
        return DockerSummaryResponse(docker_available=False, running_containers=0)
    finally:
        _close_client(client)


def _to_container_info(container: object) -> DockerContainerInfo:
    attrs = getattr(container, "attrs", {}) or {}
    state_info = attrs.get("State", {}) or {}
    created_at = attrs.get("Created")
    running_for = _calculate_running_for(state_info)

    ports: dict[str, list[str]] = {}
    raw_ports = (attrs.get("NetworkSettings", {}) or {}).get("Ports") or {}
    for container_port, host_bindings in raw_ports.items():
        if not host_bindings:
            ports[str(container_port)] = []
            continue
        mapped = []
        for binding in host_bindings:
            if not binding:
                continue
            host_ip = binding.get("HostIp", "")
            host_port = binding.get("HostPort", "")
            if host_ip and host_port:
                mapped.append(f"{host_ip}:{host_port}")
            elif host_port:
                mapped.append(str(host_port))
        ports[str(container_port)] = mapped

    image = _extract_image(container, attrs)
    name = str(getattr(container, "name", "") or attrs.get("Name", "")).lstrip("/")
    state = str(getattr(container, "status", "") or state_info.get("Status", "unknown"))
    status = str(state_info.get("Status", state))
    short_id = str(getattr(container, "short_id", "") or getattr(container, "id", "")[:12])

    return DockerContainerInfo(
        id=short_id,
        name=name or short_id or "unknown",
        image=image,
        state=state,
        status=status,
        ports=ports,
        created=created_at,
        running_for=running_for,
    )


def _extract_image(container: object, attrs: dict) -> str:
    image_obj = getattr(container, "image", None)
    tags = getattr(image_obj, "tags", None)
    if tags:
        return str(tags[0])

    config_image = (attrs.get("Config", {}) or {}).get("Image")
    if config_image:
        return str(config_image)

    short_id = getattr(image_obj, "short_id", None)
    if short_id:
        return str(short_id)

    return "unknown"


def _calculate_running_for(state_info: dict) -> str | None:
    if not state_info.get("Running"):
        return None
    started_at = parse_docker_timestamp(state_info.get("StartedAt"))
    if started_at is None:
        return None
    seconds = int((utc_now() - started_at).total_seconds())
    return format_duration(seconds)


def _close_client(client: object | None) -> None:
    if client is None:
        return
    try:
        client.close()
    except Exception as exc:  # pragma: no cover - runtime fallback
        logger.debug("Failed to close Docker client cleanly: %s", exc)


def _create_docker_client() -> object:
    timeout_seconds = get_settings().docker_timeout_seconds
    return docker.from_env(timeout=timeout_seconds)
