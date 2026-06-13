from __future__ import annotations

from datetime import datetime, timezone

from app.core.config import get_settings
from app.services.alerts.models import AlertCandidate
from app.services.alerts.store import AlertStore


def test_alert_feed_requires_consumer_token(client) -> None:
    response = client.get("/api/alerts/events")
    wrong = client.get(
        "/api/alerts/events",
        headers={"Authorization": "Bearer test-mobile-alert-token"},
    )

    assert response.status_code == 401
    assert wrong.status_code == 401


def test_alert_feed_returns_ordered_events(client, alert_consumer_headers) -> None:
    store = AlertStore(get_settings().alert_db_path)
    store.initialize()
    store.transition_alerts(
        [
            AlertCandidate(
                key="memory-usage",
                category="memory",
                severity="critical",
                title="Memory usage high",
                message="95% is above threshold.",
                route="/overview",
                mobile_scope=True,
            )
        ],
        now=datetime(2026, 6, 13, 12, 0, tzinfo=timezone.utc),
        grace_seconds=0,
        mobile_push_enabled=False,
        include_recovery=True,
    )

    response = client.get("/api/alerts/events", headers=alert_consumer_headers)

    assert response.status_code == 200
    payload = response.json()
    assert payload["latest_event_id"] == 1
    assert payload["events"][0]["event_id"] == 1
    assert payload["events"][0]["alert_key"] == "memory-usage"
    assert "fcm" not in str(payload).lower()


def test_alert_status_is_secret_safe(client, alert_consumer_headers) -> None:
    response = client.get("/api/alerts/status", headers=alert_consumer_headers)

    assert response.status_code == 200
    payload = response.json()
    assert "latest_event_id" in payload
    assert "token" not in str(payload).lower()
    assert "firebase_service_account" not in str(payload).lower()
