from __future__ import annotations

import json
import os
from pathlib import Path

from app.models.mobile_alerts import MobileAlertRegistrationRequest
from app.services.mobile_push_registry import MobilePushTokenRegistry
from app.services.mobile_push_sender import MobilePushSendResult


def _payload(fcm_token: str = "fcm-token-" + "x" * 32) -> dict[str, object]:
    return {
        "installation_id": "tablet-install-1",
        "device_name": "Homelab Tablet",
        "fcm_token": fcm_token,
        "platform": "android",
        "enabled": True,
    }


def test_mobile_alert_endpoints_require_bearer_token(client) -> None:
    endpoints = [
        ("get", "/api/mobile-alerts/status"),
        ("post", "/api/mobile-alerts/register"),
        ("delete", "/api/mobile-alerts/register/tablet-install-1"),
        ("post", "/api/mobile-alerts/test"),
    ]

    for method, path in endpoints:
        if method == "get":
            response = client.get(path)
        elif method == "delete":
            response = client.delete(path)
        else:
            response = getattr(client, method)(path, json={})
        assert response.status_code == 401


def test_register_and_status_do_not_expose_fcm_token(client, auth_headers) -> None:
    response = client.post(
        "/api/mobile-alerts/register",
        headers=auth_headers,
        json=_payload(),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["registered"] is True
    assert payload["installation_id"] == "tablet-install-1"
    assert "fcm_token" not in json.dumps(payload)

    status_response = client.get(
        "/api/mobile-alerts/status?installation_id=tablet-install-1",
        headers=auth_headers,
    )
    assert status_response.status_code == 200
    assert status_response.json()["registered"] is True
    assert "fcm_token" not in json.dumps(status_response.json())


def test_register_replaces_token_for_same_installation(tmp_path: Path) -> None:
    registry = MobilePushTokenRegistry(tmp_path / "tokens.json")
    first = MobileAlertRegistrationRequest.model_validate(_payload("first-" + "x" * 32))
    second = MobileAlertRegistrationRequest.model_validate(_payload("second-" + "y" * 32))

    registry.upsert(first)
    registry.upsert(second)

    installations = registry.enabled_installations()
    assert len(installations) == 1
    assert installations[0].fcm_token.startswith("second-")


def test_unregister_disables_installation(client, auth_headers) -> None:
    client.post("/api/mobile-alerts/register", headers=auth_headers, json=_payload())

    response = client.delete(
        "/api/mobile-alerts/register/tablet-install-1",
        headers=auth_headers,
    )

    assert response.status_code == 200
    assert response.json()["registered"] is False


def test_invalid_payload_rejected(client, auth_headers) -> None:
    response = client.post(
        "/api/mobile-alerts/register",
        headers=auth_headers,
        json={**_payload(), "platform": "ios"},
    )

    assert response.status_code == 422


def test_registry_persistence_is_atomic_and_private(tmp_path: Path) -> None:
    registry_path = tmp_path / "tokens.json"
    registry = MobilePushTokenRegistry(registry_path)

    registry.upsert(MobileAlertRegistrationRequest.model_validate(_payload()))

    assert registry_path.exists()
    assert not list(tmp_path.glob("*.tmp"))
    if os.name != "nt":
        assert registry_path.stat().st_mode & 0o777 == 0o600


def test_test_push_endpoint_calls_sender_safely(client, auth_headers, monkeypatch) -> None:
    client.post("/api/mobile-alerts/register", headers=auth_headers, json=_payload())

    sent_installations: list[str] = []

    def fake_send_test(self, installation):
        sent_installations.append(installation.installation_id)
        return MobilePushSendResult(sent_count=1)

    monkeypatch.setattr(
        "app.services.mobile_push_sender.FirebaseMobilePushSender.configured",
        property(lambda _self: True),
    )
    monkeypatch.setattr(
        "app.services.mobile_push_sender.FirebaseMobilePushSender.send_test",
        fake_send_test,
    )

    response = client.post(
        "/api/mobile-alerts/test",
        headers=auth_headers,
        json={"installation_id": "tablet-install-1"},
    )

    assert response.status_code == 200
    assert response.json() == {"status": "sent", "sent_count": 1}
    assert sent_installations == ["tablet-install-1"]


def test_test_push_reports_unconfigured_firebase(client, auth_headers) -> None:
    client.post("/api/mobile-alerts/register", headers=auth_headers, json=_payload())

    response = client.post(
        "/api/mobile-alerts/test",
        headers=auth_headers,
        json={"installation_id": "tablet-install-1"},
    )

    assert response.status_code == 503
