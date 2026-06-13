from __future__ import annotations

import asyncio
import logging

from app.core.config import Settings

from .firebase_sender import FirebaseMobilePushSender, FirebaseNotConfiguredError
from .models import MobileInstallation
from .store import AlertStore

logger = logging.getLogger(__name__)


class MobilePushOutboxWorker:
    def __init__(
        self,
        *,
        settings: Settings,
        store: AlertStore,
        sender: FirebaseMobilePushSender,
    ) -> None:
        self._settings = settings
        self._store = store
        self._sender = sender

    async def process_due(self) -> None:
        if not self._settings.mobile_push_enabled:
            return
        if not self._sender.configured:
            return

        for delivery in self._store.due_mobile_deliveries():
            try:
                result = await asyncio.to_thread(
                    self._sender.send_to_installation,
                    fcm_token=delivery.fcm_token,
                    title=delivery.title,
                    body=delivery.message,
                    route=delivery.route,
                    alert_key=delivery.alert_key,
                    event_id=delivery.event_id,
                    event_type=delivery.event_type,
                )
            except FirebaseNotConfiguredError:
                return
            except Exception:
                delay = self._store.mark_delivery_retry(
                    delivery.delivery_id,
                    retry_initial_seconds=self._settings.mobile_push_retry_initial_seconds,
                    retry_max_seconds=self._settings.mobile_push_retry_max_seconds,
                    error="firebase-send-failed",
                )
                logger.exception(
                    "Mobile push delivery raised: delivery_id=%s event_id=%s retry_in=%ss",
                    delivery.delivery_id,
                    delivery.event_id,
                    delay,
                )
                continue
            if result.sent_count > 0:
                self._store.mark_delivery_delivered(delivery.delivery_id)
                continue
            if result.invalid_token:
                self._store.disable_installation(delivery.installation_id)
                self._store.mark_delivery_cancelled(
                    delivery.delivery_id,
                    error=result.safe_error or "invalid-registration-token",
                )
                logger.info(
                    "Disabled mobile installation after invalid FCM token: installation_id=%s",
                    delivery.installation_id,
                )
                continue

            delay = self._store.mark_delivery_retry(
                delivery.delivery_id,
                retry_initial_seconds=self._settings.mobile_push_retry_initial_seconds,
                retry_max_seconds=self._settings.mobile_push_retry_max_seconds,
                error=result.safe_error or "firebase-send-failed",
            )
            logger.warning(
                "Mobile push delivery failed: delivery_id=%s event_id=%s retry_in=%ss",
                delivery.delivery_id,
                delivery.event_id,
                delay,
            )

    async def send_test(self, installation: MobileInstallation) -> int:
        if not self._sender.configured:
            raise FirebaseNotConfiguredError("Firebase service account is not configured.")
        result = await asyncio.to_thread(
            self._sender.send_to_installation,
            fcm_token=installation.fcm_token,
            title="Homelab mobile alert test",
            body="Backend to Firebase to tablet delivery is working.",
            route="/settings",
            alert_key="mobile-alert-test",
            event_id=0,
            event_type="test",
        )
        if result.invalid_token:
            self._store.disable_installation(installation.installation_id)
            return 0
        return result.sent_count
