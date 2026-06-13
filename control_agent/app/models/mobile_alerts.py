from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class MobileAlertRegistrationRequest(BaseModel):
    installation_id: str = Field(min_length=8, max_length=128)
    device_name: str = Field(min_length=1, max_length=80)
    fcm_token: str = Field(min_length=20, max_length=4096)
    platform: Literal["android"] = "android"
    enabled: bool = True
    include_recovery: bool = True


class MobileAlertStatusResponse(BaseModel):
    push_configured: bool
    registered: bool
    installation_id: str | None = None
    device_name: str | None = None
    platform: str | None = None
    enabled: bool = False
    include_recovery: bool = True
    last_registered_at: datetime | None = None
    last_test_sent_at: datetime | None = None


class MobileAlertTestRequest(BaseModel):
    installation_id: str = Field(min_length=8, max_length=128)


class MobileAlertTestResponse(BaseModel):
    status: str
    sent_count: int
