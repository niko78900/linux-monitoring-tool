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

from app.core.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(autouse=True)
def clear_settings_cache() -> None:
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
def api_prefix() -> str:
    return get_settings().api_prefix


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as test_client:
        yield test_client
