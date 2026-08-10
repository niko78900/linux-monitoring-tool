from __future__ import annotations

from app.services.wake_on_lan import build_magic_packet


def test_wake_endpoint_uses_configured_mac_not_request_body(
    client, auth_headers, monkeypatch
) -> None:
    seen: dict[str, object] = {}

    def fake_send_magic_packet(mac_address: str, broadcast_host: str, port: int) -> None:
        seen["mac_address"] = mac_address
        seen["broadcast_host"] = broadcast_host
        seen["port"] = port

    monkeypatch.setattr("app.api.routes.actions.send_magic_packet", fake_send_magic_packet)

    response = client.post(
        "/api/actions/wake-main-pc",
        headers=auth_headers,
        json={"mac_address": "11:22:33:44:55:66"},
    )

    assert response.status_code == 202
    assert seen == {
        "mac_address": "AA:BB:CC:DD:EE:FF",
        "broadcast_host": "255.255.255.255",
        "port": 9,
    }
    payload = response.json()
    assert payload["action"] == "wake-main-pc"
    assert payload["status"] == "accepted"
    assert payload["target"] == "main_pc"


def test_wake_endpoint_accepts_scoped_wake_token(
    client, wake_auth_headers, monkeypatch
) -> None:
    monkeypatch.setattr("app.api.routes.actions.send_magic_packet", lambda *_: None)

    response = client.post(
        "/api/actions/wake-main-pc",
        headers=wake_auth_headers,
    )

    assert response.status_code == 202
    assert response.json()["action"] == "wake-main-pc"


def test_wake_endpoint_rate_limits_requests(client, auth_headers, monkeypatch) -> None:
    monkeypatch.setattr("app.api.routes.actions.send_magic_packet", lambda *_: None)

    first = client.post("/api/actions/wake-main-pc", headers=auth_headers)
    second = client.post("/api/actions/wake-main-pc", headers=auth_headers)

    assert first.status_code == 202
    assert second.status_code == 429
    assert "rate limited" in second.json()["detail"]


def test_wake_endpoint_returns_sanitized_error(client, auth_headers, monkeypatch) -> None:
    def failing_send_magic_packet(*_args) -> None:
        raise OSError("network stack exploded")

    monkeypatch.setattr("app.api.routes.actions.send_magic_packet", failing_send_magic_packet)

    response = client.post("/api/actions/wake-main-pc", headers=auth_headers)

    assert response.status_code == 500
    assert response.json() == {"detail": "Action failed"}


def test_build_magic_packet() -> None:
    packet = build_magic_packet("aa:bb:cc:dd:ee:ff")

    assert len(packet) == 102
    assert packet[:6] == b"\xff" * 6
    assert packet[6:12] == bytes.fromhex("aabbccddeeff")
