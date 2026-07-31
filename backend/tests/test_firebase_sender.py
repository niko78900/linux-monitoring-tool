from __future__ import annotations

from pathlib import Path

from app.services.alerts.firebase_sender import FirebaseMobilePushSender


def test_configured_fails_closed_when_credential_path_is_inaccessible(
    monkeypatch,
) -> None:
    credential_path = Path("/protected/firebase-service-account.json")
    monkeypatch.setattr(
        Path,
        "is_file",
        lambda _path: (_ for _ in ()).throw(PermissionError("denied")),
    )

    sender = FirebaseMobilePushSender(credential_path)

    assert sender.configured is False
