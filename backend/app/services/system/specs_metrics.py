from __future__ import annotations

import logging
import os
import platform
import re
import shutil
import subprocess
from functools import lru_cache

from app.models.system import (
    CpuMetrics,
    CpuSpecs,
    GPUSpecs,
    MemoryMetrics,
    MemoryModuleSpecs,
    MemorySpecs,
    MotherboardSpecs,
    SwapMetrics,
    SystemSpecs,
)
from app.services.gpu_service import get_gpu_static_specs
from app.services.system.common import read_text_file

try:
    import psutil
except ImportError:  # pragma: no cover - handled at runtime
    psutil = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)

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


def get_system_specs(
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
        value = _clean_hardware_value(read_text_file(candidate))
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
