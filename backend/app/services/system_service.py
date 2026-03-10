from __future__ import annotations

import logging
import os
import platform
import re
import shutil
import socket
import subprocess
from datetime import datetime
from functools import lru_cache

from app.core.utils import format_duration, to_utc_datetime, utc_now
from app.models.system import (
    CpuMetrics,
    CpuSpecs,
    DiskDeviceMetrics,
    DiskHealth,
    DiskMetrics,
    GPUSpecs,
    LoadAverage,
    MemoryModuleSpecs,
    MemoryMetrics,
    MemorySpecs,
    NetworkMetrics,
    PhysicalDiskMetrics,
    PlatformInfo,
    MotherboardSpecs,
    RaidArrayMetrics,
    RaidHealth,
    SwapMetrics,
    SystemResponse,
    SystemSpecs,
)
from app.services.gpu_service import get_gpu_static_specs

try:
    import psutil
except ImportError:  # pragma: no cover - handled at runtime
    psutil = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)

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
IGNORED_EXACT_MOUNTPOINTS = {"/boot/efi"}
IGNORED_PHYSICAL_DEVICE_PREFIXES = ("loop", "ram", "zram", "dm-", "md", "fd", "sr")

DMI_UNKNOWN_VALUES = {
    "",
    "not specified",
    "not provided",
    "none",
    "unknown",
    "to be filled by o.e.m.",
    "to be filled by oem",
    "n/a",
    "na",
}

CHIPSET_HINT_PATTERN = re.compile(
    r"\b((?:[ABHQWXZ]\d{2,4})|(?:TRX\d{2,4})|(?:X\d{2,4})|(?:C\d{2,4})|(?:PCH))\b",
    re.IGNORECASE,
)


def get_system_metrics(mountpoint: str) -> SystemResponse:
    now = utc_now()
    boot_time = _get_boot_time(now)
    uptime_seconds = max(0, int((now - boot_time).total_seconds()))
    primary_disk = _get_disk_metrics(mountpoint)
    raid_arrays = _get_raid_arrays_metrics()
    memory_metrics = _get_memory_metrics()
    swap_metrics = _get_swap_metrics()
    cpu_metrics = _get_cpu_metrics()

    return SystemResponse(
        hostname=_get_hostname(),
        os=_get_platform_info(),
        kernel_version=platform.release(),
        specs=_get_system_specs(memory_metrics=memory_metrics, swap_metrics=swap_metrics, cpu_metrics=cpu_metrics),
        uptime_seconds=uptime_seconds,
        uptime_human=format_duration(uptime_seconds),
        boot_time=boot_time,
        cpu=cpu_metrics,
        memory=memory_metrics,
        swap=swap_metrics,
        disk=primary_disk,
        disks=_get_disks_metrics(mountpoint, primary_disk, raid_arrays),
        raid_arrays=raid_arrays,
        physical_disks=_get_physical_disks_metrics(raid_arrays),
        network=_get_network_metrics(),
    )


def _get_hostname() -> str:
    try:
        return socket.gethostname()
    except OSError as exc:
        logger.warning("Could not read hostname: %s", exc)
        return "unknown"


def _get_platform_info() -> PlatformInfo:
    return PlatformInfo(
        system=platform.system(),
        release=platform.release(),
        version=platform.version(),
        machine=platform.machine(),
        platform=platform.platform(),
    )


def _get_boot_time(now: datetime) -> datetime:
    if psutil is None:
        return now
    try:
        return to_utc_datetime(psutil.boot_time())
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read boot time: %s", exc)
        return now


def _get_load_average() -> LoadAverage | None:
    try:
        one, five, fifteen = os.getloadavg()
    except (AttributeError, OSError):
        return None
    return LoadAverage(
        one_min=round(float(one), 2),
        five_min=round(float(five), 2),
        fifteen_min=round(float(fifteen), 2),
    )


def _get_cpu_metrics() -> CpuMetrics:
    if psutil is None:
        return CpuMetrics(usage_percent=0.0, physical_cores=0, logical_cores=0, load_average=None)

    try:
        usage_percent = round(float(psutil.cpu_percent(interval=0.1)), 2)
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read CPU usage: %s", exc)
        usage_percent = 0.0

    try:
        physical_cores = int(psutil.cpu_count(logical=False) or 0)
        logical_cores = int(psutil.cpu_count(logical=True) or 0)
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read CPU core counts: %s", exc)
        physical_cores = 0
        logical_cores = 0

    return CpuMetrics(
        usage_percent=usage_percent,
        physical_cores=physical_cores,
        logical_cores=logical_cores,
        load_average=_get_load_average(),
    )


def _read_cpuinfo_fields() -> dict[str, str]:
    if platform.system().lower() != "linux":
        return {}

    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8") as cpuinfo_file:
            content = cpuinfo_file.read()
    except OSError as exc:
        logger.warning("Could not read /proc/cpuinfo: %s", exc)
        return {}

    first_block = content.split("\n\n", 1)[0]
    fields: dict[str, str] = {}
    for line in first_block.splitlines():
        if ":" not in line:
            continue
        key, raw_value = line.split(":", 1)
        normalized_key = key.strip().lower()
        value = raw_value.strip()
        if not normalized_key or not value:
            continue
        fields[normalized_key] = value

    return fields


def _cpu_model_name(cpuinfo_fields: dict[str, str]) -> str:
    model_candidates = [
        cpuinfo_fields.get("model name"),
        cpuinfo_fields.get("hardware"),
        cpuinfo_fields.get("processor"),
        platform.processor(),
        platform.uname().processor,
    ]

    for candidate in model_candidates:
        if candidate:
            cleaned = str(candidate).strip()
            if cleaned:
                return cleaned
    return "unknown"


def _cpu_vendor(cpuinfo_fields: dict[str, str]) -> str | None:
    vendor_candidates = [
        cpuinfo_fields.get("vendor_id"),
        cpuinfo_fields.get("cpu implementer"),
        cpuinfo_fields.get("vendor"),
    ]
    for candidate in vendor_candidates:
        if candidate:
            cleaned = str(candidate).strip()
            if cleaned:
                return cleaned
    return None


def _cpu_capabilities(cpuinfo_fields: dict[str, str]) -> list[str]:
    raw_capabilities = cpuinfo_fields.get("flags") or cpuinfo_fields.get("features")
    if not raw_capabilities:
        return []

    capabilities: list[str] = []
    seen: set[str] = set()
    for capability in raw_capabilities.split():
        normalized = capability.strip().lower()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        capabilities.append(normalized)
    return capabilities


def _normalize_frequency_mhz(value: float | None) -> float | None:
    if value is None:
        return None
    if value <= 0:
        return None
    return round(float(value), 2)


def _cpu_frequency_bounds() -> tuple[float | None, float | None]:
    if psutil is None:
        return None, None

    try:
        freq = psutil.cpu_freq()
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read CPU frequency: %s", exc)
        return None, None

    if freq is None:
        return None, None

    min_frequency = _normalize_frequency_mhz(getattr(freq, "min", None))
    max_frequency = _normalize_frequency_mhz(getattr(freq, "max", None))
    return min_frequency, max_frequency


def _get_system_specs(
    *,
    memory_metrics: MemoryMetrics,
    swap_metrics: SwapMetrics,
    cpu_metrics: CpuMetrics,
) -> SystemSpecs:
    cpuinfo_fields = _read_cpuinfo_fields()
    min_frequency_mhz, max_frequency_mhz = _cpu_frequency_bounds()
    motherboard_specs = _get_motherboard_specs_cached().model_copy(deep=True)
    memory_specs = _build_memory_specs(memory_total_bytes=memory_metrics.total)
    gpu_specs = _get_gpu_static_specs_cached().model_copy(deep=True)

    return SystemSpecs(
        cpu=CpuSpecs(
            model_name=_cpu_model_name(cpuinfo_fields),
            vendor=_cpu_vendor(cpuinfo_fields),
            architecture=platform.machine() or "unknown",
            physical_cores=cpu_metrics.physical_cores,
            logical_cores=cpu_metrics.logical_cores,
            min_frequency_mhz=min_frequency_mhz,
            max_frequency_mhz=max_frequency_mhz,
            capabilities=_cpu_capabilities(cpuinfo_fields),
        ),
        memory_total_bytes=memory_metrics.total,
        swap_total_bytes=swap_metrics.total,
        memory=memory_specs,
        motherboard=motherboard_specs,
        gpu=gpu_specs,
    )


def _clean_hardware_value(raw_value: str | None) -> str | None:
    if raw_value is None:
        return None
    cleaned = raw_value.strip()
    if not cleaned:
        return None
    if cleaned.lower() in DMI_UNKNOWN_VALUES:
        return None
    return cleaned


def _read_dmi_value(field_name: str) -> str | None:
    if os.name == "nt":
        return None

    candidates = (
        f"/sys/class/dmi/id/{field_name}",
        f"/sys/devices/virtual/dmi/id/{field_name}",
    )
    for candidate in candidates:
        value = _clean_hardware_value(_read_text_file(candidate))
        if value is not None:
            return value
    return None


def _extract_chipset_hint(*values: str | None) -> str | None:
    fallback_values: list[str] = []
    for value in values:
        cleaned = _clean_hardware_value(value)
        if cleaned is None:
            continue
        fallback_values.append(cleaned)
        match = CHIPSET_HINT_PATTERN.search(cleaned)
        if match is not None:
            return match.group(1).upper()
    if fallback_values:
        return fallback_values[0]
    return None


@lru_cache(maxsize=1)
def _get_motherboard_specs_cached() -> MotherboardSpecs:
    vendor = _read_dmi_value("board_vendor")
    model = _read_dmi_value("board_name")
    version = _read_dmi_value("board_version")
    product_name = _read_dmi_value("product_name")

    chipset = _extract_chipset_hint(model, product_name)
    return MotherboardSpecs(
        vendor=vendor,
        model=model,
        version=version,
        chipset=chipset,
    )


def _parse_memory_size_bytes(raw_value: str | None) -> int | None:
    cleaned = _clean_hardware_value(raw_value)
    if cleaned is None:
        return None

    lowered = cleaned.lower()
    if "no module installed" in lowered:
        return None

    match = re.search(r"(\d+)\s*(kb|mb|gb|tb)\b", lowered)
    if match is None:
        return None

    quantity = int(match.group(1))
    unit = match.group(2)
    multiplier_map = {
        "kb": 1024,
        "mb": 1024 ** 2,
        "gb": 1024 ** 3,
        "tb": 1024 ** 4,
    }
    return quantity * multiplier_map[unit]


def _parse_speed_mhz(raw_value: str | None) -> int | None:
    cleaned = _clean_hardware_value(raw_value)
    if cleaned is None:
        return None

    lowered = cleaned.lower()
    match = re.search(r"(\d+)\s*(mt/s|mhz)\b", lowered)
    if match is None:
        return None
    return int(match.group(1))


def _run_safe_command(args: list[str], timeout_seconds: float = 4.0) -> str | None:
    try:
        result = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="ignore",
            timeout=timeout_seconds,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        logger.debug("Command %s failed: %s", args[0] if args else "unknown", exc)
        return None

    if result.returncode != 0:
        logger.debug(
            "Command %s exited with %s: %s",
            args[0] if args else "unknown",
            result.returncode,
            result.stderr.strip(),
        )
        return None

    output = result.stdout.strip()
    return output or None


def _parse_dmidecode_memory_modules(raw_output: str) -> list[MemoryModuleSpecs]:
    modules: list[MemoryModuleSpecs] = []

    blocks = raw_output.split("Memory Device")
    for block in blocks[1:]:
        lines = block.splitlines()
        fields: dict[str, str] = {}
        for line in lines:
            if ":" not in line:
                continue
            key, raw_value = line.split(":", 1)
            normalized_key = key.strip().lower()
            value = raw_value.strip()
            if not normalized_key:
                continue
            fields[normalized_key] = value

        size_bytes = _parse_memory_size_bytes(fields.get("size"))
        if size_bytes is None or size_bytes <= 0:
            continue

        locator = _clean_hardware_value(fields.get("locator")) or _clean_hardware_value(fields.get("bank locator"))
        manufacturer = _clean_hardware_value(fields.get("manufacturer"))
        part_number = _clean_hardware_value(fields.get("part number"))
        memory_type = _clean_hardware_value(fields.get("type"))
        speed_mhz = _parse_speed_mhz(fields.get("configured memory speed")) or _parse_speed_mhz(fields.get("speed"))

        modules.append(
            MemoryModuleSpecs(
                slot=locator,
                manufacturer=manufacturer,
                part_number=part_number,
                memory_type=memory_type,
                size_bytes=size_bytes,
                speed_mhz=speed_mhz,
            )
        )

    modules.sort(key=lambda module: (module.slot or "", module.part_number or ""))
    return modules


@lru_cache(maxsize=1)
def _read_memory_modules_cached() -> list[MemoryModuleSpecs]:
    if os.name == "nt":
        return []

    dmidecode_path = shutil.which("dmidecode")
    if dmidecode_path is None:
        return []

    raw_output = _run_safe_command([dmidecode_path, "-t", "memory"])
    if raw_output is None:
        return []

    return _parse_dmidecode_memory_modules(raw_output)


def _build_memory_specs(memory_total_bytes: int) -> MemorySpecs:
    modules = [module.model_copy(deep=True) for module in _read_memory_modules_cached()]
    module_speeds = [module.speed_mhz for module in modules if module.speed_mhz is not None]
    manufacturers = sorted({module.manufacturer for module in modules if module.manufacturer})
    memory_type = next((module.memory_type for module in modules if module.memory_type), None)

    return MemorySpecs(
        total_bytes=max(0, memory_total_bytes),
        speed_mhz=max(module_speeds) if module_speeds else None,
        memory_type=memory_type,
        manufacturers=manufacturers,
        modules=modules,
    )


@lru_cache(maxsize=1)
def _get_gpu_static_specs_cached() -> GPUSpecs:
    return get_gpu_static_specs()


def _get_memory_metrics() -> MemoryMetrics:
    if psutil is None:
        return MemoryMetrics(total=0, available=0, used=0, percent=0.0)
    try:
        memory = psutil.virtual_memory()
        return MemoryMetrics(
            total=int(memory.total),
            available=int(memory.available),
            used=int(memory.used),
            percent=round(float(memory.percent), 2),
        )
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read memory metrics: %s", exc)
        return MemoryMetrics(total=0, available=0, used=0, percent=0.0)


def _get_swap_metrics() -> SwapMetrics:
    if psutil is None:
        return SwapMetrics(total=0, used=0, percent=0.0)
    try:
        swap = psutil.swap_memory()
        return SwapMetrics(total=int(swap.total), used=int(swap.used), percent=round(float(swap.percent), 2))
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read swap metrics: %s", exc)
        return SwapMetrics(total=0, used=0, percent=0.0)


def _fallback_mountpoint() -> str:
    if os.name == "nt":
        return f"{os.getenv('SystemDrive', 'C:')}\\"
    return "/"


def _get_disk_metrics(mountpoint: str) -> DiskMetrics:
    resolved_mountpoint = mountpoint or _fallback_mountpoint()
    if psutil is None:
        return DiskMetrics(total=0, used=0, free=0, percent=0.0, mountpoint=resolved_mountpoint)

    try:
        disk = psutil.disk_usage(resolved_mountpoint)
    except (AttributeError, OSError, PermissionError) as exc:
        fallback = _fallback_mountpoint()
        logger.warning("Could not read disk metrics from %s: %s. Falling back to %s.", resolved_mountpoint, exc, fallback)
        resolved_mountpoint = fallback
        try:
            disk = psutil.disk_usage(resolved_mountpoint)
        except (AttributeError, OSError, PermissionError) as fallback_exc:
            logger.warning("Could not read fallback disk metrics: %s", fallback_exc)
            return DiskMetrics(total=0, used=0, free=0, percent=0.0, mountpoint=resolved_mountpoint)

    return DiskMetrics(
        total=int(disk.total),
        used=int(disk.used),
        free=int(disk.free),
        percent=round(float(disk.percent), 2),
        mountpoint=resolved_mountpoint,
    )


def _mount_options_set(options: str) -> set[str]:
    return {item.strip().lower() for item in options.split(",") if item.strip()}


def _build_disk_health(percent: float, available: bool, read_only: bool, reason: str | None = None) -> DiskHealth:
    if not available:
        return DiskHealth(status="unknown", reason=reason or "Disk metrics unavailable.")
    if percent >= 95:
        return DiskHealth(status="critical", reason="Disk usage is above 95%.")
    if percent >= 85:
        return DiskHealth(status="warning", reason="Disk usage is above 85%.")
    if read_only:
        return DiskHealth(status="warning", reason="Disk is mounted read-only.")
    return DiskHealth(status="healthy", reason="Disk usage is within normal range.")


def _to_disk_device_metrics(
    *,
    device: str,
    mountpoint: str,
    fstype: str,
    total: int,
    used: int,
    free: int,
    percent: float,
    read_only: bool,
    available: bool,
    raid_array: str | None = None,
    raid_level: str | None = None,
    reason: str | None = None,
) -> DiskDeviceMetrics:
    return DiskDeviceMetrics(
        device=device or "unknown",
        mountpoint=mountpoint,
        fstype=fstype or "unknown",
        total=total,
        used=used,
        free=free,
        percent=percent,
        read_only=read_only,
        available=available,
        raid_array=raid_array,
        raid_level=raid_level,
        health=_build_disk_health(percent=percent, available=available, read_only=read_only, reason=reason),
    )


def _is_relevant_partition(partition_mountpoint: str, partition_fstype: str) -> bool:
    mountpoint = partition_mountpoint.strip()
    fstype = partition_fstype.strip().lower()
    if not mountpoint:
        return False
    normalized_mountpoint = mountpoint.rstrip("/") or "/"
    if normalized_mountpoint in IGNORED_EXACT_MOUNTPOINTS:
        return False
    if fstype in IGNORED_FSTYPES:
        return False
    if os.name != "nt" and mountpoint != "/" and mountpoint.startswith(IGNORED_MOUNT_PREFIXES):
        return False
    return True


def _find_raid_array_for_device(
    device: str, raid_arrays_by_device: dict[str, RaidArrayMetrics]
) -> RaidArrayMetrics | None:
    if not device:
        return None

    candidates = [device]
    md_partition_match = re.match(r"^(\/dev\/md[^\/\s]+)p\d+$", device)
    if md_partition_match:
        candidates.append(md_partition_match.group(1))

    md_named_partition_match = re.match(r"^(\/dev\/md\/[^\/\s]+)p\d+$", device)
    if md_named_partition_match:
        candidates.append(md_named_partition_match.group(1))

    for candidate in candidates:
        raid_array = raid_arrays_by_device.get(candidate)
        if raid_array is not None:
            return raid_array
    return None


def _build_raid_array_device_map(raid_arrays: list[RaidArrayMetrics]) -> dict[str, RaidArrayMetrics]:
    raid_arrays_by_device = {raid_array.device: raid_array for raid_array in raid_arrays}
    md_dir = "/dev/md"
    if not os.path.isdir(md_dir):
        return raid_arrays_by_device

    try:
        aliases = os.listdir(md_dir)
    except OSError as exc:
        logger.warning("Could not list RAID aliases in %s: %s", md_dir, exc)
        return raid_arrays_by_device

    for alias in aliases:
        alias_path = os.path.join(md_dir, alias)
        resolved_path = os.path.realpath(alias_path)
        raid_array = raid_arrays_by_device.get(resolved_path)
        if raid_array is not None:
            raid_arrays_by_device[alias_path] = raid_array

    return raid_arrays_by_device


def _collect_partition_disk_metrics(raid_arrays: list[RaidArrayMetrics]) -> list[DiskDeviceMetrics]:
    if psutil is None:
        return []

    try:
        partitions = psutil.disk_partitions(all=False)
    except (AttributeError, OSError) as exc:
        logger.warning("Could not list disk partitions: %s", exc)
        return []

    raid_arrays_by_device = _build_raid_array_device_map(raid_arrays)
    disks_by_mountpoint: dict[str, DiskDeviceMetrics] = {}
    for partition in partitions:
        mountpoint = str(getattr(partition, "mountpoint", "") or "")
        fstype = str(getattr(partition, "fstype", "") or "unknown")
        if not _is_relevant_partition(mountpoint, fstype):
            continue

        device = str(getattr(partition, "device", "") or "unknown")
        options = str(getattr(partition, "opts", "") or "")
        read_only = "ro" in _mount_options_set(options)
        raid_array = _find_raid_array_for_device(device, raid_arrays_by_device)
        raid_array_name = raid_array.name if raid_array is not None else None
        raid_array_level = raid_array.level if raid_array is not None else None

        try:
            usage = psutil.disk_usage(mountpoint)
            disk_metric = _to_disk_device_metrics(
                device=device,
                mountpoint=mountpoint,
                fstype=fstype,
                total=int(usage.total),
                used=int(usage.used),
                free=int(usage.free),
                percent=round(float(usage.percent), 2),
                read_only=read_only,
                available=True,
                raid_array=raid_array_name,
                raid_level=raid_array_level,
            )
        except (AttributeError, OSError, PermissionError) as exc:
            logger.warning("Could not read disk usage for mountpoint %s: %s", mountpoint, exc)
            disk_metric = _to_disk_device_metrics(
                device=device,
                mountpoint=mountpoint,
                fstype=fstype,
                total=0,
                used=0,
                free=0,
                percent=0.0,
                read_only=read_only,
                available=False,
                raid_array=raid_array_name,
                raid_level=raid_array_level,
                reason=f"Metrics unavailable: {exc}",
            )

        existing = disks_by_mountpoint.get(mountpoint)
        if (
            existing is None
            or (not existing.available and disk_metric.available)
            or (existing.raid_array is None and disk_metric.raid_array is not None)
        ):
            disks_by_mountpoint[mountpoint] = disk_metric

    return list(disks_by_mountpoint.values())


def _get_disks_metrics(mountpoint: str, primary_disk: DiskMetrics, raid_arrays: list[RaidArrayMetrics]) -> list[DiskDeviceMetrics]:
    primary_mountpoint = primary_disk.mountpoint or mountpoint or _fallback_mountpoint()

    if psutil is None:
        return [
            _to_disk_device_metrics(
                device="unknown",
                mountpoint=primary_mountpoint,
                fstype="unknown",
                total=primary_disk.total,
                used=primary_disk.used,
                free=primary_disk.free,
                percent=primary_disk.percent,
                read_only=False,
                available=False,
                reason="psutil is unavailable.",
            )
        ]

    disks = _collect_partition_disk_metrics(raid_arrays)
    has_primary = any(disk.mountpoint == primary_mountpoint for disk in disks)
    if not has_primary:
        primary_available = primary_disk.total > 0
        disks.append(
            _to_disk_device_metrics(
                device="unknown",
                mountpoint=primary_mountpoint,
                fstype="unknown",
                total=primary_disk.total,
                used=primary_disk.used,
                free=primary_disk.free,
                percent=primary_disk.percent,
                read_only=False,
                available=primary_available,
                reason=None if primary_available else "Disk metrics unavailable.",
            )
        )

    disks.sort(key=lambda disk: (0 if disk.mountpoint == primary_mountpoint else 1, disk.mountpoint.lower()))
    return disks


def _read_text_file(path: str) -> str | None:
    try:
        with open(path, "r", encoding="utf-8") as file:
            return file.read().strip() or None
    except OSError:
        return None


def _parse_int(raw_value: str | None, default: int = 0) -> int:
    if raw_value is None:
        return default
    try:
        return max(0, int(raw_value))
    except ValueError:
        return default


def _build_raid_health(level: str, state: str, degraded_devices: int, sync_action: str | None) -> RaidHealth:
    normalized_state = state.strip().lower()
    normalized_sync = (sync_action or "").strip().lower()
    normalized_level = level.strip().lower()

    if degraded_devices > 0:
        return RaidHealth(
            status="critical",
            reason=f"Array is degraded ({degraded_devices} missing device{'s' if degraded_devices > 1 else ''}).",
        )

    if normalized_state in {"inactive", "clear", "suspended"}:
        return RaidHealth(status="warning", reason=f"Array state is '{state}'.")

    if normalized_sync and normalized_sync not in {"idle", "none"}:
        return RaidHealth(status="warning", reason=f"Array sync action is '{sync_action}'.")

    if normalized_level == "unknown":
        return RaidHealth(status="unknown", reason="RAID level could not be determined.")

    return RaidHealth(status="healthy", reason="RAID array reports healthy state.")


def _get_raid_arrays_metrics() -> list[RaidArrayMetrics]:
    if os.name == "nt":
        return []

    sys_block = "/sys/block"
    if not os.path.isdir(sys_block):
        return []

    arrays: list[RaidArrayMetrics] = []
    try:
        block_devices = os.listdir(sys_block)
    except OSError as exc:
        logger.warning("Could not list block devices for RAID discovery: %s", exc)
        return []

    for block_device in block_devices:
        if not block_device.startswith("md"):
            continue

        md_dir = os.path.join(sys_block, block_device, "md")
        if not os.path.isdir(md_dir):
            continue

        device = f"/dev/{block_device}"
        level = _read_text_file(os.path.join(md_dir, "level")) or "unknown"
        state = _read_text_file(os.path.join(md_dir, "array_state")) or "unknown"
        raid_disks = _parse_int(_read_text_file(os.path.join(md_dir, "raid_disks")))
        degraded_devices = _parse_int(_read_text_file(os.path.join(md_dir, "degraded")))
        sync_action = _read_text_file(os.path.join(md_dir, "sync_action"))

        slaves_dir = os.path.join(sys_block, block_device, "slaves")
        members: list[str] = []
        if os.path.isdir(slaves_dir):
            try:
                members = sorted(f"/dev/{name}" for name in os.listdir(slaves_dir))
            except OSError as exc:
                logger.warning("Could not read RAID member devices for %s: %s", device, exc)

        active_devices = max(0, raid_disks - degraded_devices) if raid_disks > 0 else len(members)
        arrays.append(
            RaidArrayMetrics(
                name=block_device,
                device=device,
                level=level,
                state=state,
                raid_disks=raid_disks,
                active_devices=active_devices,
                degraded_devices=degraded_devices,
                sync_action=sync_action,
                members=members,
                health=_build_raid_health(
                    level=level,
                    state=state,
                    degraded_devices=degraded_devices,
                    sync_action=sync_action,
                ),
            )
        )

    arrays.sort(key=lambda raid_array: raid_array.device.lower())
    return arrays


def _parse_bool_text(raw_value: str | None, default: bool = False) -> bool:
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on", "y"}


def _normalize_block_device_name(device_or_path: str) -> str:
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


def _is_physical_block_device_name(device_name: str) -> bool:
    if not device_name:
        return False
    if device_name.startswith(IGNORED_PHYSICAL_DEVICE_PREFIXES):
        return False
    return True


def _collect_mountpoints_by_physical_disk() -> dict[str, list[str]]:
    mounts_by_disk: dict[str, set[str]] = {}
    if psutil is None:
        return {}

    try:
        partitions = psutil.disk_partitions(all=False)
    except (AttributeError, OSError) as exc:
        logger.warning("Could not collect partitions for physical disks: %s", exc)
        return {}

    for partition in partitions:
        mountpoint = str(getattr(partition, "mountpoint", "") or "").strip()
        fstype = str(getattr(partition, "fstype", "") or "").strip()
        device = str(getattr(partition, "device", "") or "").strip()
        if not mountpoint or not device:
            continue
        if not _is_relevant_partition(mountpoint, fstype):
            continue

        disk_name = _normalize_block_device_name(device)
        if not _is_physical_block_device_name(disk_name):
            continue

        mounts_by_disk.setdefault(disk_name, set()).add(mountpoint)

    return {
        disk_name: sorted(mounts)
        for disk_name, mounts in mounts_by_disk.items()
    }


def _build_raid_membership_by_physical_disk(raid_arrays: list[RaidArrayMetrics]) -> dict[str, list[RaidArrayMetrics]]:
    membership: dict[str, list[RaidArrayMetrics]] = {}
    for raid_array in raid_arrays:
        for member in raid_array.members:
            disk_name = _normalize_block_device_name(member)
            if not _is_physical_block_device_name(disk_name):
                continue
            membership.setdefault(disk_name, []).append(raid_array)

    for disk_name, arrays in membership.items():
        unique_arrays = {array.device: array for array in arrays}
        membership[disk_name] = sorted(unique_arrays.values(), key=lambda item: item.device.lower())
    return membership


def _build_physical_disk_health(
    *,
    size_bytes: int,
    state: str | None,
    raid_arrays: list[RaidArrayMetrics],
) -> DiskHealth:
    if size_bytes <= 0:
        return DiskHealth(status="unknown", reason="Disk size could not be determined.")

    normalized_state = (state or "").strip().lower()
    if normalized_state in {"offline", "faulty", "error", "dead"}:
        return DiskHealth(status="critical", reason=f"Kernel reports disk state '{state}'.")
    if normalized_state and normalized_state not in {"running", "live", "active"}:
        return DiskHealth(status="warning", reason=f"Kernel reports disk state '{state}'.")

    if raid_arrays:
        if any(raid_array.health.status == "critical" for raid_array in raid_arrays):
            return DiskHealth(status="warning", reason="Member of a degraded RAID array.")
        if any(raid_array.health.status == "warning" for raid_array in raid_arrays):
            return DiskHealth(status="warning", reason="Member of a RAID array under sync/recovery.")

    return DiskHealth(status="healthy", reason="Physical disk reports healthy kernel state.")


def _get_physical_disks_metrics(raid_arrays: list[RaidArrayMetrics]) -> list[PhysicalDiskMetrics]:
    if os.name == "nt":
        return []

    sys_block = "/sys/block"
    if not os.path.isdir(sys_block):
        return []

    try:
        block_devices = os.listdir(sys_block)
    except OSError as exc:
        logger.warning("Could not list physical block devices: %s", exc)
        return []

    mounts_by_disk = _collect_mountpoints_by_physical_disk()
    raid_membership = _build_raid_membership_by_physical_disk(raid_arrays)

    physical_disks: list[PhysicalDiskMetrics] = []
    for device_name in block_devices:
        if not _is_physical_block_device_name(device_name):
            continue

        device_path = os.path.join(sys_block, device_name)
        if not os.path.isdir(device_path):
            continue

        # Skip pseudo devices that do not represent a real hardware-backed disk.
        if not os.path.exists(os.path.join(device_path, "device")):
            continue

        size_sectors = _parse_int(_read_text_file(os.path.join(device_path, "size")))
        logical_block_size = _parse_int(_read_text_file(os.path.join(device_path, "queue", "logical_block_size")), default=512)
        size_bytes = size_sectors * logical_block_size

        state = _read_text_file(os.path.join(device_path, "device", "state"))
        model = _read_text_file(os.path.join(device_path, "device", "model"))
        vendor = _read_text_file(os.path.join(device_path, "device", "vendor"))
        serial = _read_text_file(os.path.join(device_path, "device", "serial"))
        rotational_value = _read_text_file(os.path.join(device_path, "queue", "rotational"))
        rotational = None
        if rotational_value is not None:
            rotational = rotational_value.strip() == "1"
        removable = _parse_bool_text(_read_text_file(os.path.join(device_path, "removable")))
        mounted_partitions = mounts_by_disk.get(device_name, [])
        disk_raid_arrays = raid_membership.get(device_name, [])
        raid_array_names = [raid_array.name for raid_array in disk_raid_arrays]

        physical_disks.append(
            PhysicalDiskMetrics(
                name=device_name,
                device=f"/dev/{device_name}",
                model=model,
                vendor=vendor,
                serial=serial,
                size_bytes=size_bytes,
                rotational=rotational,
                removable=removable,
                state=state,
                mounted_partitions=mounted_partitions,
                raid_arrays=raid_array_names,
                health=_build_physical_disk_health(
                    size_bytes=size_bytes,
                    state=state,
                    raid_arrays=disk_raid_arrays,
                ),
            )
        )

    physical_disks.sort(key=lambda disk: disk.device.lower())
    return physical_disks


def _get_network_metrics() -> NetworkMetrics:
    if psutil is None:
        return NetworkMetrics(bytes_sent=0, bytes_recv=0, packets_sent=0, packets_recv=0, top_speed_mbps=None)

    try:
        network = psutil.net_io_counters()
        if network is None:
            raise ValueError("net_io_counters returned None")
        return NetworkMetrics(
            bytes_sent=int(network.bytes_sent),
            bytes_recv=int(network.bytes_recv),
            packets_sent=int(network.packets_sent),
            packets_recv=int(network.packets_recv),
            top_speed_mbps=_get_top_network_speed_mbps(),
        )
    except (AttributeError, OSError, ValueError) as exc:
        logger.warning("Could not read network metrics: %s", exc)
        return NetworkMetrics(bytes_sent=0, bytes_recv=0, packets_sent=0, packets_recv=0, top_speed_mbps=None)


def _get_top_network_speed_mbps() -> int | None:
    if psutil is None:
        return None

    try:
        interface_stats = psutil.net_if_stats()
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read network interface stats: %s", exc)
        return None

    if not interface_stats:
        return None

    up_speeds: list[int] = []
    all_speeds: list[int] = []
    for stats in interface_stats.values():
        raw_speed = getattr(stats, "speed", 0)
        if raw_speed is None:
            continue
        try:
            speed = int(raw_speed)
        except (TypeError, ValueError):
            continue
        if speed <= 0:
            continue

        all_speeds.append(speed)
        if bool(getattr(stats, "isup", False)):
            up_speeds.append(speed)

    if up_speeds:
        return max(up_speeds)
    if all_speeds:
        return max(all_speeds)
    return None
