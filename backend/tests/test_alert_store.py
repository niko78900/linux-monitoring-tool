from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace

from app.services.alerts.mobile_push import MobilePushOutboxWorker
from app.services.alerts.models import AlertCandidate, MobilePushResult
from app.services.alerts.store import AlertStore


def _now() -> datetime:
    return datetime(2026, 6, 13, 12, 0, tzinfo=timezone.utc)


def _cpu_candidate() -> AlertCandidate:
    return AlertCandidate(
        key="cpu-usage",
        category="cpu",
        severity="warning",
        title="CPU usage high",
        message="92% is above threshold.",
        route="/overview",
        mobile_scope=True,
    )


def test_brief_spike_does_not_alert(tmp_path: Path) -> None:
    store = AlertStore(tmp_path / "alerts.sqlite3")
    store.initialize()

    events = store.transition_alerts(
        [_cpu_candidate()],
        now=_now(),
        grace_seconds=300,
        mobile_push_enabled=True,
        include_recovery=True,
    )
    recovered = store.transition_alerts(
        [],
        now=_now() + timedelta(seconds=30),
        grace_seconds=300,
        mobile_push_enabled=True,
        include_recovery=True,
    )

    assert events == []
    assert recovered == []
    assert store.latest_event_id() == 0


def test_sustained_alert_dedupes_and_recovers(tmp_path: Path) -> None:
    store = AlertStore(tmp_path / "alerts.sqlite3")
    store.initialize()

    first = store.transition_alerts(
        [_cpu_candidate()],
        now=_now(),
        grace_seconds=300,
        mobile_push_enabled=False,
        include_recovery=True,
    )
    active = store.transition_alerts(
        [_cpu_candidate()],
        now=_now() + timedelta(seconds=301),
        grace_seconds=300,
        mobile_push_enabled=False,
        include_recovery=True,
    )
    duplicate = store.transition_alerts(
        [_cpu_candidate()],
        now=_now() + timedelta(seconds=360),
        grace_seconds=300,
        mobile_push_enabled=False,
        include_recovery=True,
    )
    recovery = store.transition_alerts(
        [],
        now=_now() + timedelta(seconds=420),
        grace_seconds=300,
        mobile_push_enabled=False,
        include_recovery=True,
    )

    assert first == []
    assert [event.event_type for event in active] == ["active"]
    assert duplicate == []
    assert [event.event_type for event in recovery] == ["recovery"]
    assert recovery[0].recovered_after_seconds == 119


def test_registration_token_rotation_and_status_are_token_safe(tmp_path: Path) -> None:
    store = AlertStore(tmp_path / "alerts.sqlite3")
    store.initialize()

    store.upsert_installation(
        installation_id="tablet-install-1",
        device_name="Homelab Tablet",
        platform="android",
        fcm_token="first-token-" + "x" * 32,
        enabled=True,
        include_recovery=False,
        now=_now(),
    )
    store.upsert_installation(
        installation_id="tablet-install-1",
        device_name="Homelab Tablet",
        platform="android",
        fcm_token="second-token-" + "y" * 32,
        enabled=True,
        include_recovery=True,
        now=_now(),
    )

    installation = store.get_installation("tablet-install-1")

    assert installation is not None
    assert installation.fcm_token.startswith("second-token-")
    assert installation.include_recovery is True


def test_stale_active_delivery_cancelled_before_recovery(tmp_path: Path) -> None:
    store = AlertStore(tmp_path / "alerts.sqlite3")
    store.initialize()
    store.upsert_installation(
        installation_id="tablet-install-1",
        device_name="Homelab Tablet",
        platform="android",
        fcm_token="token-" + "x" * 32,
        enabled=True,
        include_recovery=True,
        now=_now(),
    )

    store.transition_alerts(
        [_cpu_candidate()],
        now=_now(),
        grace_seconds=0,
        mobile_push_enabled=True,
        include_recovery=True,
    )
    assert store.pending_mobile_delivery_count() == 1

    store.transition_alerts(
        [],
        now=_now() + timedelta(seconds=60),
        grace_seconds=0,
        mobile_push_enabled=True,
        include_recovery=True,
    )

    pending = store.due_mobile_deliveries(now=_now() + timedelta(seconds=60))
    assert store.pending_mobile_delivery_count() == 1
    assert len(pending) == 1
    assert pending[0].event_type == "recovery"


class _FakeSender:
    configured = True

    def __init__(self, result: MobilePushResult) -> None:
        self.result = result

    def send_to_installation(self, **_: object) -> MobilePushResult:
        return self.result


def test_invalid_token_disables_installation(tmp_path: Path) -> None:
    store = AlertStore(tmp_path / "alerts.sqlite3")
    store.initialize()
    store.upsert_installation(
        installation_id="tablet-install-1",
        device_name="Homelab Tablet",
        platform="android",
        fcm_token="token-" + "x" * 32,
        enabled=True,
        include_recovery=True,
        now=_now(),
    )
    store.transition_alerts(
        [_cpu_candidate()],
        now=_now(),
        grace_seconds=0,
        mobile_push_enabled=True,
        include_recovery=True,
    )
    worker = MobilePushOutboxWorker(
        settings=SimpleNamespace(
            mobile_push_enabled=True,
            mobile_push_retry_initial_seconds=1,
            mobile_push_retry_max_seconds=2,
        ),
        store=store,
        sender=_FakeSender(
            MobilePushResult(
                sent_count=0,
                invalid_token=True,
                safe_error="invalid-registration-token",
            )
        ),
    )

    import asyncio

    asyncio.run(worker.process_due())

    assert store.get_installation("tablet-install-1").enabled is False  # type: ignore[union-attr]
    assert store.pending_mobile_delivery_count() == 0
