from __future__ import annotations

import json


def _payload(token: str = "fcm-token-" + "x" * 32) -> dict[str, object]:
    return {
        "installation_id": "tablet-install-1",
        "device_name": "Homelab Tablet",
        "fcm_token": token,
        "platform": "android",
        "enabled": True,
        "include_recovery": False,
    }


def test_mobile_alert_endpoints_require_scoped_token(client) -> None:
    endpoints = [
        ("get", "/api/mobile-alerts/status"),
        ("post", "/api/mobile-alerts/register"),
        ("delete", "/api/mobile-alerts/register/tablet-install-1"),
        ("post", "/api/mobile-alerts/test"),
    ]

    for method, path in endpoints:
        if method == "get":
            response = client.get(path)
            wrong = client.get(path, headers={"Authorization": "Bearer test-token"})
        elif method == "delete":
            response = client.delete(path)
            wrong = client.delete(path, headers={"Authorization": "Bearer test-token"})
        else:
            response = client.post(path, json={})
            wrong = client.post(path, headers={"Authorization": "Bearer test-token"}, json={})
        assert response.status_code == 401
        assert wrong.status_code == 401


def test_register_and_status_do_not_expose_fcm_token(
    client,
    mobile_alert_headers,
) -> None:
    response = client.post(
        "/api/mobile-alerts/register",
        headers=mobile_alert_headers,
        json=_payload(),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["registered"] is True
    assert payload["installation_id"] == "tablet-install-1"
    assert payload["include_recovery"] is False
    assert "fcm_token" not in json.dumps(payload)

    status_response = client.get(
        "/api/mobile-alerts/status?installation_id=tablet-install-1",
        headers=mobile_alert_headers,
    )
    assert status_response.status_code == 200
    assert status_response.json()["registered"] is True
    assert "fcm_token" not in json.dumps(status_response.json())


def test_unregister_disables_registration(client, mobile_alert_headers) -> None:
    client.post("/api/mobile-alerts/register", headers=mobile_alert_headers, json=_payload())

    response = client.delete(
        "/api/mobile-alerts/register/tablet-install-1",
        headers=mobile_alert_headers,
    )

    assert response.status_code == 200
    assert response.json()["registered"] is False
    assert response.json()["enabled"] is False


def test_test_push_calls_backend_sender(
    client,
    mobile_alert_headers,
    monkeypatch,
) -> None:
    client.post("/api/mobile-alerts/register", headers=mobile_alert_headers, json=_payload())

    async def fake_send_test(self, installation):
        assert installation.installation_id == "tablet-install-1"
        return 1

    monkeypatch.setattr(
        "app.services.alerts.mobile_push.MobilePushOutboxWorker.send_test",
        fake_send_test,
    )

    response = client.post(
        "/api/mobile-alerts/test",
        headers=mobile_alert_headers,
        json={"installation_id": "tablet-install-1"},
    )

    assert response.status_code == 200
    assert response.json() == {"status": "sent", "sent_count": 1}
