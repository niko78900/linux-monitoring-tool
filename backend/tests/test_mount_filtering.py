from app.services.system.common import MountFilterConfig, is_relevant_partition


def test_sftp_bind_mount_is_hidden_when_prefix_is_ignored() -> None:
    config = MountFilterConfig(
        visible_mountpoints=set(),
        ignored_mount_prefixes_extra=("/srv/sftp",),
    )

    assert is_relevant_partition("/mnt/warm", "ext4", config) is True
    assert (
        is_relevant_partition(
            "/srv/sftp/tablet_sftp/WarmStorage",
            "ext4",
            config,
        )
        is False
    )


def test_visible_mountpoints_allowlist() -> None:
    config = MountFilterConfig(
        visible_mountpoints={"/", "/mnt/storage", "/mnt/warm"},
        ignored_mount_prefixes_extra=("/srv/sftp",),
    )

    assert is_relevant_partition("/", "ext4", config) is True
    assert is_relevant_partition("/mnt/storage", "ext4", config) is True
    assert is_relevant_partition("/mnt/warm", "ext4", config) is True
    assert (
        is_relevant_partition(
            "/srv/sftp/tablet_sftp/WarmStorage",
            "ext4",
            config,
        )
        is False
    )


def test_generic_filter_keeps_normal_mountpoints_without_allowlist() -> None:
    config = MountFilterConfig(
        visible_mountpoints=set(),
        ignored_mount_prefixes_extra=(),
    )

    assert is_relevant_partition("/mnt/warm", "ext4", config) is True
