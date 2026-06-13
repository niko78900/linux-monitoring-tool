from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

os.environ.setdefault("HISTORY_ENABLED", "false")
os.environ.setdefault("HISTORY_DB_PATH", str(BACKEND_ROOT / ".test-history.sqlite3"))
os.environ.setdefault("ALERTS_ENABLED", "false")
os.environ.setdefault("ALERT_DB_PATH", str(BACKEND_ROOT / ".test-alerts.sqlite3"))
os.environ.setdefault("MOBILE_ALERT_API_TOKEN", "test-mobile-alert-token")
os.environ.setdefault("ALERT_CONSUMER_API_TOKEN", "test-alert-consumer-token")

from app.core.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(autouse=True)
def clear_settings_cache() -> None:
    alert_db = BACKEND_ROOT / ".test-alerts.sqlite3"
    alert_db.unlink(missing_ok=True)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()
    alert_db.unlink(missing_ok=True)


@pytest.fixture
def api_prefix() -> str:
    return get_settings().api_prefix


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def mobile_alert_headers() -> dict[str, str]:
    return {"Authorization": "Bearer test-mobile-alert-token"}


@pytest.fixture
def alert_consumer_headers() -> dict[str, str]:
    return {"Authorization": "Bearer test-alert-consumer-token"}
