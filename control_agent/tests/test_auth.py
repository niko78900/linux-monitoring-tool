from __future__ import annotations


def test_invalid_bearer_token_is_rejected(client) -> None:
    response = client.get("/api/health", headers={"Authorization": "Bearer wrong"})

    assert response.status_code == 401
    assert response.json() == {"detail": "Unauthorized"}
