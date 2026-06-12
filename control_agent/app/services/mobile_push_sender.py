from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .mobile_push_registry import MobilePushInstallation


class MobilePushNotConfiguredError(RuntimeError):
    pass


@dataclass(frozen=True)
class MobilePushSendResult:
    sent_count: int


class FirebaseMobilePushSender:
    def __init__(self, service_account_file: Path) -> None:
        self.service_account_file = service_account_file

    @property
    def configured(self) -> bool:
        return self.service_account_file.exists()

    def send_test(self, installation: MobilePushInstallation) -> MobilePushSendResult:
        return self.send(
            installation=installation,
            title="Homelab test alert",
            body="Round-trip mobile push delivery is configured.",
            route="/overview",
            alert_key="test",
        )

    def send(
        self,
        *,
        installation: MobilePushInstallation,
        title: str,
        body: str,
        route: str,
        alert_key: str,
    ) -> MobilePushSendResult:
        if not self.configured:
            raise MobilePushNotConfiguredError("Firebase service account is not configured.")

        import firebase_admin
        from firebase_admin import credentials, messaging

        if not firebase_admin._apps:
            credential = credentials.Certificate(str(self.service_account_file))
            firebase_admin.initialize_app(credential)

        message = messaging.Message(
            token=installation.fcm_token,
            notification=messaging.Notification(title=title, body=body),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="homelab_urgent_alerts_v1",
                    priority="high",
                    visibility="public",
                    default_sound=True,
                    default_vibrate_timings=True,
                ),
            ),
            data={
                "alert_key": alert_key,
                "route": route,
            },
        )
        messaging.send(message)
        return MobilePushSendResult(sent_count=1)
