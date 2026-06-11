from __future__ import annotations

from datetime import datetime


def test_health_endpoint_requires_auth(client) -> None:
    response = client.get("/api/health")

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}


def test_health_endpoint_returns_expected_payload(client, auth_headers) -> None:
    response = client.get("/api/health", headers=auth_headers)

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["app_name"] == "Homelab Control Agent"
    assert payload["version"] == "0.1.0"
    datetime.fromisoformat(payload["timestamp"].replace("Z", "+00:00"))
