from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ...core.auth import require_bearer_token
from ...core.config import Settings, get_settings
from ...models.mobile_alerts import (
    MobileAlertRegistrationRequest,
    MobileAlertStatusResponse,
    MobileAlertTestRequest,
    MobileAlertTestResponse,
)
from ...services.mobile_push_registry import MobilePushTokenRegistry
from ...services.mobile_push_sender import (
    FirebaseMobilePushSender,
    MobilePushNotConfiguredError,
)

router = APIRouter(
    prefix="/mobile-alerts",
    tags=["mobile-alerts"],
    dependencies=[Depends(require_bearer_token)],
)


@router.get("/status", response_model=MobileAlertStatusResponse)
def get_mobile_alert_status(
    installation_id: str | None = Query(default=None),
    settings: Settings = Depends(get_settings),
) -> MobileAlertStatusResponse:
    registry = MobilePushTokenRegistry(settings.mobile_push_token_registry_file)
    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    return registry.status(
        installation_id=installation_id,
        push_configured=sender.configured,
    )


@router.post("/register", response_model=MobileAlertStatusResponse)
def register_mobile_alert_device(
    request: MobileAlertRegistrationRequest,
    settings: Settings = Depends(get_settings),
) -> MobileAlertStatusResponse:
    registry = MobilePushTokenRegistry(settings.mobile_push_token_registry_file)
    registry.upsert(request)
    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    return registry.status(
        installation_id=request.installation_id,
        push_configured=sender.configured,
    )


@router.delete("/register/{installation_id}", response_model=MobileAlertStatusResponse)
def unregister_mobile_alert_device(
    installation_id: str,
    settings: Settings = Depends(get_settings),
) -> MobileAlertStatusResponse:
    registry = MobilePushTokenRegistry(settings.mobile_push_token_registry_file)
    registry.disable(installation_id)
    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    return registry.status(
        installation_id=installation_id,
        push_configured=sender.configured,
    )


@router.post("/test", response_model=MobileAlertTestResponse)
def send_mobile_alert_test(
    request: MobileAlertTestRequest,
    settings: Settings = Depends(get_settings),
) -> MobileAlertTestResponse:
    registry = MobilePushTokenRegistry(settings.mobile_push_token_registry_file)
    installation = registry.get(request.installation_id)
    if installation is None or not installation.enabled:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mobile alert installation is not registered",
        )
    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    try:
        result = sender.send_test(installation)
    except MobilePushNotConfiguredError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Firebase mobile push is not configured",
        ) from error
    registry.mark_test_sent(request.installation_id)
    return MobileAlertTestResponse(status="sent", sent_count=result.sent_count)
