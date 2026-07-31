from __future__ import annotations

from pathlib import Path

from .models import MobilePushResult

ANDROID_CHANNEL_ID = "homelab_urgent_alerts_v1"


class FirebaseNotConfiguredError(RuntimeError):
    pass


class FirebaseMobilePushSender:
    def __init__(self, service_account_file: Path) -> None:
        self.service_account_file = service_account_file

    @property
    def configured(self) -> bool:
        try:
            return self.service_account_file.is_file()
        except OSError:
            return False

    def send_to_installation(
        self,
        *,
        fcm_token: str,
        title: str,
        body: str,
        route: str | None,
        alert_key: str,
        event_id: int,
        event_type: str,
    ) -> MobilePushResult:
        if not self.configured:
            raise FirebaseNotConfiguredError("Firebase service account is not configured.")

        import firebase_admin
        from firebase_admin import credentials, messaging

        if not firebase_admin._apps:
            credential = credentials.Certificate(str(self.service_account_file))
            firebase_admin.initialize_app(credential)

        message = messaging.Message(
            token=fcm_token,
            notification=messaging.Notification(title=title, body=body),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id=ANDROID_CHANNEL_ID,
                    priority="high",
                    visibility="private",
                    icon="ic_homelab_notification",
                    default_sound=True,
                    default_vibrate_timings=True,
                ),
            ),
            data={
                "title": title,
                "body": body,
                "alert_key": alert_key,
                "route": route or "",
                "event_id": str(event_id),
                "event_type": event_type,
            },
        )

        try:
            messaging.send(message)
        except Exception as exc:  # Firebase exceptions are optional at import time.
            if _is_invalid_token_error(exc):
                return MobilePushResult(
                    sent_count=0,
                    invalid_token=True,
                    safe_error="invalid-registration-token",
                )
            return MobilePushResult(sent_count=0, safe_error=_safe_error(exc))
        return MobilePushResult(sent_count=1)


def _is_invalid_token_error(exc: Exception) -> bool:
    code = str(getattr(exc, "code", "") or "").lower()
    message = str(exc).lower()
    return code in {
        "registration-token-not-registered",
        "invalid-registration-token",
    } or "registration token" in message and "not registered" in message


def _safe_error(exc: Exception) -> str:
    text = str(exc).strip()
    if not text:
        return exc.__class__.__name__
    return text[:240]
