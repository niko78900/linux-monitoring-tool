from __future__ import annotations

import importlib

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def app(monkeypatch):
    monkeypatch.setenv("CONTROL_API_TOKEN", "test-token")
    monkeypatch.setenv("MAIN_PC_MAC", "AA:BB:CC:DD:EE:FF")
    monkeypatch.setenv("WAKE_RATE_LIMIT_SECONDS", "30")

    import app.core.config as config_module

    config_module.get_settings.cache_clear()

    import app.main as main_module

    importlib.reload(main_module)
    import app.core.rate_limit as rate_limit_module

    rate_limit_module.rate_limiter.reset()
    yield main_module.app
    config_module.get_settings.cache_clear()
    rate_limit_module.rate_limiter.reset()


@pytest.fixture
def client(app):
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def auth_headers() -> dict[str, str]:
    return {"Authorization": "Bearer test-token"}
