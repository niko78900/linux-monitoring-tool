from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

AlertSeverity = Literal["warning", "critical"]


@dataclass(frozen=True)
class Alert:
    key: str
    title: str
    message: str
    severity: AlertSeverity


def evaluate_alerts(*, backend_error: str | None = None, **_: object) -> list[Alert]:
    if not backend_error:
        return []
    return [
        Alert(
            key="backend-unavailable",
            title="Monitoring API unavailable",
            message=backend_error,
            severity="critical",
        )
    ]
