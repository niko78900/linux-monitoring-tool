from __future__ import annotations


def test_invalid_bearer_token_is_rejected(client) -> None:
    response = client.get("/api/health", headers={"Authorization": "Bearer wrong"})

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}


def test_wake_token_can_read_health(client, wake_auth_headers) -> None:
    response = client.get("/api/health", headers=wake_auth_headers)

    assert response.status_code == 200


def test_wake_token_cannot_access_full_control_routes(
    client, wake_auth_headers
) -> None:
    requests = (
        ("GET", "/api/devices"),
        ("GET", "/api/hosts"),
        ("GET", "/api/services"),
        ("GET", "/api/benchmarks/status"),
    )

    for method, path in requests:
        response = client.request(method, path, headers=wake_auth_headers)
        assert response.status_code == 401, path
        assert response.json() == {"detail": "Unauthorized"}
