from __future__ import annotations

from typing import Any

import httpx


class MonitoringAPIError(RuntimeError):
    pass


class MonitoringClient:
    def __init__(self, base_url: str, timeout_seconds: float = 8.0) -> None:
        self._client = httpx.AsyncClient(
            base_url=base_url.rstrip("/"),
            timeout=timeout_seconds,
            headers={"Accept": "application/json"},
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def fetch_health(self) -> dict[str, Any]:
        return await self._get_json("/api/health")

    async def fetch_summary(self) -> dict[str, Any]:
        return await self._get_json("/api/summary")

    async def fetch_system(self) -> dict[str, Any]:
        return await self._get_json("/api/system")

    async def fetch_gpu(self) -> dict[str, Any]:
        return await self._get_json("/api/gpu")

    async def fetch_docker(self) -> dict[str, Any]:
        return await self._get_json("/api/docker")

    async def _get_json(self, path: str) -> dict[str, Any]:
        try:
            response = await self._client.get(path)
        except httpx.RequestError as exc:
            raise MonitoringAPIError(f"{path}: request failed: {exc}") from exc

        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise MonitoringAPIError(f"{path}: returned HTTP {response.status_code}.") from exc

        try:
            payload = response.json()
        except ValueError as exc:
            raise MonitoringAPIError(f"{path}: returned invalid JSON.") from exc

        if not isinstance(payload, dict):
            raise MonitoringAPIError(f"{path}: returned non-object JSON payload.")
        return payload
