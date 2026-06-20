from app.services.system.common import is_relevant_partition


def test_sftp_bind_mount_is_hidden_by_default(monkeypatch) -> None:
    monkeypatch.delenv("VISIBLE_MOUNTPOINTS", raising=False)
    monkeypatch.delenv("IGNORED_MOUNT_PREFIXES_EXTRA", raising=False)

    assert is_relevant_partition("/mnt/warm", "ext4") is True
    assert (
        is_relevant_partition("/srv/sftp/tablet_sftp/WarmStorage", "ext4")
        is False
    )


def test_visible_mountpoints_allowlist(monkeypatch) -> None:
    monkeypatch.setenv("VISIBLE_MOUNTPOINTS", "/,/mnt/storage,/mnt/warm")

    assert is_relevant_partition("/", "ext4") is True
    assert is_relevant_partition("/mnt/storage", "ext4") is True
    assert is_relevant_partition("/srv/sftp/tablet_sftp/WarmStorage", "ext4") is False
