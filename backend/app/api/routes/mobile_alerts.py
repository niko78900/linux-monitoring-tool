from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.config import Settings, get_settings
from app.core.mobile_alert_auth import require_mobile_alert_token
from app.models.mobile_alerts import (
    MobileAlertRegistrationRequest,
    MobileAlertStatusResponse,
    MobileAlertTestRequest,
    MobileAlertTestResponse,
)
from app.services.alerts.firebase_sender import (
    FirebaseMobilePushSender,
    FirebaseNotConfiguredError,
)
from app.services.alerts.mobile_push import MobilePushOutboxWorker
from app.services.alerts.models import MobileInstallation
from app.services.alerts.store import AlertStore

router = APIRouter(
    prefix="/mobile-alerts",
    tags=["mobile-alerts"],
    dependencies=[Depends(require_mobile_alert_token)],
)


@router.get("/status", response_model=MobileAlertStatusResponse)
def get_mobile_alert_status(
    installation_id: str | None = Query(default=None),
    settings: Settings = Depends(get_settings),
) -> MobileAlertStatusResponse:
    store = _store(settings)
    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    return _status_response(
        store.status_for_installation(installation_id),
        installation_id=installation_id,
        push_configured=sender.configured,
    )


@router.post("/register", response_model=MobileAlertStatusResponse)
def register_mobile_alert_device(
    request: MobileAlertRegistrationRequest,
    settings: Settings = Depends(get_settings),
) -> MobileAlertStatusResponse:
    store = _store(settings)
    installation = store.upsert_installation(
        installation_id=request.installation_id,
        device_name=request.device_name,
        platform=request.platform,
        fcm_token=request.fcm_token,
        enabled=request.enabled,
        include_recovery=request.include_recovery,
    )
    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    return _status_response(
        installation,
        installation_id=request.installation_id,
        push_configured=sender.configured,
    )


@router.delete("/register/{installation_id}", response_model=MobileAlertStatusResponse)
def unregister_mobile_alert_device(
    installation_id: str,
    settings: Settings = Depends(get_settings),
) -> MobileAlertStatusResponse:
    store = _store(settings)
    store.disable_installation(installation_id)
    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    return _status_response(
        store.status_for_installation(installation_id),
        installation_id=installation_id,
        push_configured=sender.configured,
    )


@router.post("/test", response_model=MobileAlertTestResponse)
async def send_mobile_alert_test(
    request: MobileAlertTestRequest,
    settings: Settings = Depends(get_settings),
) -> MobileAlertTestResponse:
    store = _store(settings)
    installation = store.get_installation(request.installation_id)
    if installation is None or not installation.enabled:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mobile alert installation is not registered",
        )

    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    worker = MobilePushOutboxWorker(settings=settings, store=store, sender=sender)
    try:
        sent_count = await worker.send_test(installation)
    except FirebaseNotConfiguredError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Firebase mobile push is not configured",
        ) from error

    if sent_count <= 0:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Firebase mobile push test did not deliver",
        )
    store.mark_test_sent(request.installation_id)
    return MobileAlertTestResponse(status="sent", sent_count=sent_count)


def _store(settings: Settings) -> AlertStore:
    store = AlertStore(settings.alert_db_path)
    store.initialize()
    return store


def _status_response(
    installation: MobileInstallation | None,
    *,
    installation_id: str | None,
    push_configured: bool,
) -> MobileAlertStatusResponse:
    if installation is None or not installation.enabled:
        return MobileAlertStatusResponse(
            push_configured=push_configured,
            registered=False,
            enabled=False,
            installation_id=installation_id,
        )
    return MobileAlertStatusResponse(
        push_configured=push_configured,
        registered=True,
        enabled=installation.enabled,
        installation_id=installation.installation_id,
        device_name=installation.device_name,
        platform=installation.platform,
        include_recovery=installation.include_recovery,
        last_registered_at=installation.last_registered_at,
        last_test_sent_at=installation.last_test_sent_at,
    )
