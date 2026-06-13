from __future__ import annotations

import json


def test_mobile_alert_routes_are_not_exposed(client, auth_headers) -> None:
    endpoints = [
        ("get", "/api/mobile-alerts/status"),
        ("post", "/api/mobile-alerts/register"),
        ("delete", "/api/mobile-alerts/register/tablet-install-1"),
        ("post", "/api/mobile-alerts/test"),
    ]

    for method, path in endpoints:
        if method == "get":
            response = client.get(path, headers=auth_headers)
        elif method == "delete":
            response = client.delete(path, headers=auth_headers)
        else:
            response = client.post(path, headers=auth_headers, json={})
        assert response.status_code == 404
        assert "fcm" not in json.dumps(response.json()).lower()


def test_control_agent_settings_do_not_include_mobile_push_config(app) -> None:
    from app.core.config import get_settings

    settings = get_settings()

    assert not hasattr(settings, "mobile_push_token_registry_file")
    assert not hasattr(settings, "firebase_service_account_file")
