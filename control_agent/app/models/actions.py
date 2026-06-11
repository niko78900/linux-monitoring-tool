from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class WakeActionResponse(BaseModel):
    action: str
    status: str
    target: str
    requested_at: datetime
    rate_limit_seconds: int
