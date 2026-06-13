from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request

from app.core.config import Settings, get_settings
from app.core.mobile_alert_auth import require_alert_consumer_token
from app.models.alerts import (
    ActiveAlertResponse,
    ActiveAlertsResponse,
    AlertEventResponse,
    AlertEventsResponse,
    AlertStatusResponse,
)
from app.services.alerts.firebase_sender import FirebaseMobilePushSender
from app.services.alerts.store import AlertStore

router = APIRouter(
    prefix="/alerts",
    tags=["alerts"],
    dependencies=[Depends(require_alert_consumer_token)],
)


@router.get("/events", response_model=AlertEventsResponse)
def get_alert_events(
    after_id: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=500),
    settings: Settings = Depends(get_settings),
) -> AlertEventsResponse:
    store = _store(settings)
    events = store.list_events(after_id=after_id, limit=limit)
    return AlertEventsResponse(
        events=[
            AlertEventResponse(
                event_id=event.event_id,
                alert_key=event.alert_key,
                event_type=event.event_type,
                category=event.category,
                severity=event.severity,
                title=event.title,
                message=event.message,
                route=event.route,
                created_at=event.created_at,
                recovered_after_seconds=event.recovered_after_seconds,
            )
            for event in events
        ],
        latest_event_id=store.latest_event_id(),
    )


@router.get("/active", response_model=ActiveAlertsResponse)
def get_active_alerts(settings: Settings = Depends(get_settings)) -> ActiveAlertsResponse:
    store = _store(settings)
    return ActiveAlertsResponse(
        alerts=[
            ActiveAlertResponse(
                alert_key=alert.alert_key,
                category=alert.category,
                severity=alert.severity,
                title=alert.title,
                message=alert.message,
                first_seen_at=alert.first_seen_at,
                active_since=alert.active_since,
                last_seen_at=alert.last_seen_at,
            )
            for alert in store.active_alerts()
        ]
    )


@router.get("/status", response_model=AlertStatusResponse)
def get_alert_status(
    request: Request,
    settings: Settings = Depends(get_settings),
) -> AlertStatusResponse:
    store = _store(settings)
    monitor = getattr(request.app.state, "alert_monitor", None)
    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    return AlertStatusResponse(
        alerts_enabled=settings.alerts_enabled,
        alert_monitor_running=bool(getattr(monitor, "running", False)),
        firebase_configured=sender.configured,
        enabled_installation_count=store.enabled_installation_count(),
        pending_mobile_delivery_count=store.pending_mobile_delivery_count(),
        latest_event_id=store.latest_event_id(),
    )


def _store(settings: Settings) -> AlertStore:
    store = AlertStore(settings.alert_db_path)
    store.initialize()
    return store
