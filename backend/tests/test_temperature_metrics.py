from __future__ import annotations

from app.services.system import temperature_metrics


def test_cpu_temperature_prefers_psutil_candidates(monkeypatch) -> None:
    monkeypatch.setattr(
        temperature_metrics,
        "_temperatures_from_psutil",
        lambda **_: [54.2, 61.7],
    )
    monkeypatch.setattr(
        temperature_metrics,
        "_temperatures_from_sysfs",
        lambda **_: [],
    )

    assert temperature_metrics.get_cpu_temperature_c() == 61.7


def test_chassis_temperature_prefers_sysfs_when_available(monkeypatch) -> None:
    monkeypatch.setattr(
        temperature_metrics,
        "_temperatures_from_sysfs",
        lambda **_: [33.4, 35.0],
    )
    monkeypatch.setattr(
        temperature_metrics,
        "_temperatures_from_psutil",
        lambda **_: [29.1],
    )

    assert temperature_metrics.get_chassis_temperature_c() == 35.0


def test_chassis_temperature_falls_back_to_psutil(monkeypatch) -> None:
    monkeypatch.setattr(
        temperature_metrics,
        "_temperatures_from_sysfs",
        lambda **_: [],
    )
    monkeypatch.setattr(
        temperature_metrics,
        "_temperatures_from_psutil",
        lambda **_: [31.2],
    )

    assert temperature_metrics.get_chassis_temperature_c() == 31.2
