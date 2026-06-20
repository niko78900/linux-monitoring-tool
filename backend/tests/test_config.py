from __future__ import annotations

import pytest

from app.core.config import get_settings


@pytest.fixture(autouse=True)
def clear_settings_cache() -> None:
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_settings_defaults_use_localhost_origins() -> None:
    settings = get_settings()
    assert settings.cors_origins == ["http://localhost:4041", "http://127.0.0.1:4041"]
    assert settings.cors_origin_regex is None
    assert settings.visible_mountpoints == set()
    assert settings.ignored_mount_prefixes_extra == ("/srv/sftp",)


def test_settings_parse_custom_origins_and_regex(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ORIGINS", "http://10.0.0.5:4041, http://100.64.0.2:4041")
    monkeypatch.setenv("CORS_ORIGIN_REGEX", r"^https?://100\.")

    settings = get_settings()
    assert settings.cors_origins == ["http://10.0.0.5:4041", "http://100.64.0.2:4041"]
    assert settings.cors_origin_regex == r"^https?://100\."


def test_settings_parse_mount_filtering(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("VISIBLE_MOUNTPOINTS", "/,/mnt/storage,/mnt/warm")
    monkeypatch.setenv("IGNORED_MOUNT_PREFIXES_EXTRA", "/srv/sftp,/tmp/hidden/")

    settings = get_settings()

    assert settings.visible_mountpoints == {"/", "/mnt/storage", "/mnt/warm"}
    assert settings.ignored_mount_prefixes_extra == ("/srv/sftp", "/tmp/hidden")
