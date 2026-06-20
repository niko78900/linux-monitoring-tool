from __future__ import annotations

import os
import re

IGNORED_FSTYPES = {
    "autofs",
    "binfmt_misc",
    "cgroup",
    "cgroup2",
    "configfs",
    "debugfs",
    "devpts",
    "devtmpfs",
    "fusectl",
    "hugetlbfs",
    "mqueue",
    "nsfs",
    "overlay",
    "proc",
    "pstore",
    "ramfs",
    "securityfs",
    "squashfs",
    "sysfs",
    "tmpfs",
    "tracefs",
}

IGNORED_MOUNT_PREFIXES = ("/proc", "/sys", "/dev", "/run", "/snap")
DEFAULT_IGNORED_MOUNT_PREFIXES_EXTRA = ("/srv/sftp",)
IGNORED_EXACT_MOUNTPOINTS = {"/boot/efi"}
IGNORED_PHYSICAL_DEVICE_PREFIXES = ("loop", "ram", "zram", "dm-", "md", "fd", "sr")


def read_text_file(path: str) -> str | None:
    try:
        with open(path, "r", encoding="utf-8") as file:
            return file.read().strip() or None
    except OSError:
        return None


def parse_int(raw_value: str | None, default: int = 0) -> int:
    if raw_value is None:
        return default
    try:
        return max(0, int(raw_value))
    except ValueError:
        return default


def parse_bool_text(raw_value: str | None, default: bool = False) -> bool:
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on", "y"}


def normalize_block_device_name(device_or_path: str) -> str:
    if not device_or_path:
        return ""
    basename = os.path.basename(device_or_path.strip())
    if not basename:
        return ""

    if basename.startswith(("nvme", "mmcblk")):
        partition_match = re.match(r"^(.+?)p\d+$", basename)
        if partition_match:
            return partition_match.group(1)
        return basename

    trailing_digits_match = re.match(r"^([a-zA-Z]+)\d+$", basename)
    if trailing_digits_match:
        return trailing_digits_match.group(1)

    return basename


def is_physical_block_device_name(device_name: str) -> bool:
    if not device_name:
        return False
    if device_name.startswith(IGNORED_PHYSICAL_DEVICE_PREFIXES):
        return False
    return True


def is_relevant_partition(partition_mountpoint: str, partition_fstype: str) -> bool:
    mountpoint = partition_mountpoint.strip()
    fstype = partition_fstype.strip().lower()
    if not mountpoint:
        return False
    normalized_mountpoint = mountpoint.rstrip("/") or "/"
    visible_mountpoints = _csv_env_set("VISIBLE_MOUNTPOINTS")
    if visible_mountpoints and normalized_mountpoint not in visible_mountpoints:
        return False
    if normalized_mountpoint in IGNORED_EXACT_MOUNTPOINTS:
        return False
    if fstype in IGNORED_FSTYPES:
        return False
    extra_ignored_prefixes = tuple(
        _csv_env_values(
            "IGNORED_MOUNT_PREFIXES_EXTRA",
            DEFAULT_IGNORED_MOUNT_PREFIXES_EXTRA,
        )
    )
    if mountpoint != "/" and mountpoint.startswith(extra_ignored_prefixes):
        return False
    if os.name != "nt" and mountpoint != "/" and mountpoint.startswith(IGNORED_MOUNT_PREFIXES):
        return False
    return True


def _csv_env_values(name: str, default: tuple[str, ...] = ()) -> list[str]:
    raw = os.getenv(name)
    if raw is None:
        return list(default)
    return [item.strip().rstrip("/") for item in raw.split(",") if item.strip()]


def _csv_env_set(name: str) -> set[str]:
    return {item or "/" for item in _csv_env_values(name)}
