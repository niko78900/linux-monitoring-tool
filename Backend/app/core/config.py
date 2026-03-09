from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parents[2]
load_dotenv(BASE_DIR / ".env")

DEFAULT_ORIGINS = ["http://192.168.100.34:4041"]


def _parse_origins(raw_origins: str | None) -> list[str]:
    if not raw_origins:
        return DEFAULT_ORIGINS
    origins = [origin.strip() for origin in raw_origins.split(",") if origin.strip()]
    return origins or DEFAULT_ORIGINS


def _parse_bool(raw_value: str | None, default: bool) -> bool:
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    app_name: str
    app_version: str
    api_prefix: str
    cors_origins: list[str]
    disk_mountpoint: str
    log_level: str
    host: str
    port: int
    reload: bool


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings(
        app_name=os.getenv("APP_NAME", "linux-monitor"),
        app_version=os.getenv("APP_VERSION", "0.1.0"),
        api_prefix=os.getenv("API_PREFIX", "/api"),
        cors_origins=_parse_origins(os.getenv("CORS_ORIGINS")),
        disk_mountpoint=os.getenv("DISK_MOUNTPOINT", "/"),
        log_level=os.getenv("LOG_LEVEL", "INFO"),
        host=os.getenv("HOST", "192.168.100.34"),
        port=int(os.getenv("PORT", "4040")),
        reload=_parse_bool(os.getenv("RELOAD"), default=True),
    )
