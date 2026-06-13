from __future__ import annotations

import sys
from pathlib import Path

from ..models.mobile_alerts import (
    MobileAlertRegistrationRequest,
    MobileAlertStatusResponse,
)

_REPO_ROOT = Path(__file__).resolve().parents[3]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from shared.mobile_push_registry import (  # noqa: E402
    LockedMobilePushRegistry,
    MobilePushInstallation,
    MobilePushRegistryFormatError,
)


class MobilePushTokenRegistry(LockedMobilePushRegistry):
    def upsert(
        self,
        request: MobileAlertRegistrationRequest,
    ) -> MobilePushInstallation:
        return super().upsert(
            installation_id=request.installation_id,
            device_name=request.device_name,
            fcm_token=request.fcm_token,
            platform=request.platform,
            enabled=request.enabled,
            include_recovery=request.include_recovery,
        )

    def status(
        self,
        *,
        installation_id: str | None,
        push_configured: bool,
    ) -> MobileAlertStatusResponse:
        installation = self.get(installation_id) if installation_id else None
        if installation is None or not installation.enabled:
            return MobileAlertStatusResponse(
                push_configured=push_configured,
                registered=False,
                installation_id=installation_id,
            )
        return MobileAlertStatusResponse(
            push_configured=push_configured,
            registered=True,
            installation_id=installation.installation_id,
            device_name=installation.device_name,
            platform=installation.platform,
            enabled=installation.enabled,
            include_recovery=installation.include_recovery,
            last_registered_at=installation.last_registered_at,
            last_test_sent_at=installation.last_test_sent_at,
        )
