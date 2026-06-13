from __future__ import annotations

from typing import Any

import httpx


class MonitoringAPIError(RuntimeError):
    pass


class MonitoringClient:
    def __init__(
        self,
        base_url: str,
        timeout_seconds: float = 8.0,
        alert_consumer_api_token: str | None = None,
    ) -> None:
        headers = {"Accept": "application/json"}
        if alert_consumer_api_token:
            headers["Authorization"] = f"Bearer {alert_consumer_api_token}"
        self._client = httpx.AsyncClient(
            base_url=base_url.rstrip("/"),
            timeout=timeout_seconds,
            headers=headers,
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def fetch_health(self) -> dict[str, Any]:
        return await self._get_json("/health")

    async def fetch_summary(self) -> dict[str, Any]:
        return await self._get_json("/summary")

    async def fetch_system(self) -> dict[str, Any]:
        return await self._get_json("/system")

    async def fetch_gpu(self) -> dict[str, Any]:
        return await self._get_json("/gpu")

    async def fetch_docker(self) -> dict[str, Any]:
        return await self._get_json("/docker")

    async def fetch_alert_status(self) -> dict[str, Any]:
        return await self._get_json("/alerts/status")

    async def fetch_alert_events(
        self,
        *,
        after_id: int,
        limit: int = 100,
    ) -> dict[str, Any]:
        return await self._get_json(
            "/alerts/events",
            params={"after_id": max(0, int(after_id)), "limit": max(1, int(limit))},
        )

    async def _get_json(
        self,
        path: str,
        *,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        try:
            response = await self._client.get(path, params=params)
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
