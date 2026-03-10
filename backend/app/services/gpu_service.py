from __future__ import annotations

import logging

from app.models.gpu import GPUResponse
from app.models.system import GPUSpecs

try:
    from pynvml import (
        NVMLError,
        NVMLError_NotSupported,
        nvmlDeviceGetCount,
        nvmlDeviceGetCudaComputeCapability,
        nvmlDeviceGetFanSpeed,
        nvmlDeviceGetHandleByIndex,
        nvmlDeviceGetMemoryInfo,
        nvmlDeviceGetName,
        nvmlDeviceGetPowerUsage,
        nvmlDeviceGetTemperature,
        nvmlDeviceGetUtilizationRates,
        nvmlInit,
        nvmlShutdown,
        nvmlSystemGetDriverVersion,
    )
except ImportError:  # pragma: no cover - handled at runtime
    NVMLError = Exception  # type: ignore[assignment]
    NVMLError_NotSupported = Exception  # type: ignore[assignment]
    nvmlDeviceGetCount = None  # type: ignore[assignment]
    nvmlDeviceGetCudaComputeCapability = None  # type: ignore[assignment]
    nvmlDeviceGetFanSpeed = None  # type: ignore[assignment]
    nvmlDeviceGetHandleByIndex = None  # type: ignore[assignment]
    nvmlDeviceGetMemoryInfo = None  # type: ignore[assignment]
    nvmlDeviceGetName = None  # type: ignore[assignment]
    nvmlDeviceGetPowerUsage = None  # type: ignore[assignment]
    nvmlDeviceGetTemperature = None  # type: ignore[assignment]
    nvmlDeviceGetUtilizationRates = None  # type: ignore[assignment]
    nvmlInit = None  # type: ignore[assignment]
    nvmlShutdown = None  # type: ignore[assignment]
    nvmlSystemGetDriverVersion = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)
NVML_TEMPERATURE_GPU = 0


def get_gpu_static_specs() -> GPUSpecs:
    if nvmlInit is None:
        return GPUSpecs(
            available=False,
            reason="nvidia-ml-py is not installed.",
            capabilities=[],
        )

    initialized = False
    try:
        nvmlInit()
        initialized = True

        device_count = int(nvmlDeviceGetCount())
        if device_count < 1:
            return GPUSpecs(available=False, reason="No NVIDIA GPU detected.", capabilities=[])

        handle = nvmlDeviceGetHandleByIndex(0)
        name_value = nvmlDeviceGetName(handle)
        model = name_value.decode("utf-8", errors="ignore") if isinstance(name_value, (bytes, bytearray)) else str(name_value)

        driver_raw = nvmlSystemGetDriverVersion()
        driver_version = (
            driver_raw.decode("utf-8", errors="ignore") if isinstance(driver_raw, (bytes, bytearray)) else str(driver_raw)
        )

        memory = nvmlDeviceGetMemoryInfo(handle)
        cuda_compute_capability = _safe_cuda_compute_capability(handle)

        capabilities = [
            "temperature telemetry",
            "memory telemetry",
        ]
        if cuda_compute_capability is not None:
            capabilities.append(f"CUDA compute {cuda_compute_capability}")
        if _safe_power_usage(handle) is not None:
            capabilities.append("power telemetry")
        if _safe_fan_speed(handle) is not None:
            capabilities.append("fan telemetry")

        return GPUSpecs(
            available=True,
            reason=None,
            brand=_gpu_brand_from_model(model),
            model=model,
            driver_version=driver_version or None,
            vram_total_mb=int(memory.total // (1024 * 1024)),
            cuda_compute_capability=cuda_compute_capability,
            capabilities=capabilities,
        )
    except NVMLError as exc:
        logger.warning("GPU static specs unavailable: %s", exc)
        return GPUSpecs(available=False, reason=f"NVML error: {exc}", capabilities=[])
    except Exception as exc:  # pragma: no cover - runtime fallback
        logger.exception("Unexpected GPU static specs failure.")
        return GPUSpecs(available=False, reason=f"Unexpected GPU error: {exc}", capabilities=[])
    finally:
        if initialized and nvmlShutdown is not None:
            try:
                nvmlShutdown()
            except NVMLError as exc:
                logger.warning("Failed to shutdown NVML cleanly: %s", exc)


def get_gpu_metrics() -> GPUResponse:
    if nvmlInit is None:
        return GPUResponse(available=False, reason="nvidia-ml-py is not installed.")

    initialized = False
    try:
        nvmlInit()
        initialized = True

        device_count = int(nvmlDeviceGetCount())
        if device_count < 1:
            return GPUResponse(available=False, reason="No NVIDIA GPU detected.")

        handle = nvmlDeviceGetHandleByIndex(0)

        name_value = nvmlDeviceGetName(handle)
        name = name_value.decode("utf-8", errors="ignore") if isinstance(name_value, (bytes, bytearray)) else str(name_value)

        utilization = nvmlDeviceGetUtilizationRates(handle)
        memory = nvmlDeviceGetMemoryInfo(handle)
        temperature = int(nvmlDeviceGetTemperature(handle, NVML_TEMPERATURE_GPU))
        driver_raw = nvmlSystemGetDriverVersion()
        driver_version = (
            driver_raw.decode("utf-8", errors="ignore") if isinstance(driver_raw, (bytes, bytearray)) else str(driver_raw)
        )

        power_usage_w = _safe_power_usage(handle)
        fan_speed_percent = _safe_fan_speed(handle)

        return GPUResponse(
            available=True,
            reason=None,
            name=name,
            temperature_c=temperature,
            utilization_percent=round(float(utilization.gpu), 2),
            memory_total_mb=int(memory.total // (1024 * 1024)),
            memory_used_mb=int(memory.used // (1024 * 1024)),
            memory_free_mb=int(memory.free // (1024 * 1024)),
            power_usage_w=power_usage_w,
            fan_speed_percent=fan_speed_percent,
            driver_version=driver_version,
        )
    except NVMLError as exc:
        logger.warning("GPU metrics unavailable: %s", exc)
        return GPUResponse(available=False, reason=f"NVML error: {exc}")
    except Exception as exc:  # pragma: no cover - runtime fallback
        logger.exception("Unexpected GPU metrics failure.")
        return GPUResponse(available=False, reason=f"Unexpected GPU error: {exc}")
    finally:
        if initialized and nvmlShutdown is not None:
            try:
                nvmlShutdown()
            except NVMLError as exc:
                logger.warning("Failed to shutdown NVML cleanly: %s", exc)


def _safe_power_usage(handle: object) -> float | None:
    if nvmlDeviceGetPowerUsage is None:
        return None
    try:
        milliwatts = int(nvmlDeviceGetPowerUsage(handle))
    except NVMLError_NotSupported:
        return None
    except NVMLError as exc:
        logger.warning("Power usage unavailable: %s", exc)
        return None
    return round(milliwatts / 1000.0, 2)


def _safe_fan_speed(handle: object) -> int | None:
    if nvmlDeviceGetFanSpeed is None:
        return None
    try:
        return int(nvmlDeviceGetFanSpeed(handle))
    except NVMLError_NotSupported:
        return None
    except NVMLError as exc:
        logger.warning("Fan speed unavailable: %s", exc)
        return None


def _safe_cuda_compute_capability(handle: object) -> str | None:
    if nvmlDeviceGetCudaComputeCapability is None:
        return None
    try:
        major, minor = nvmlDeviceGetCudaComputeCapability(handle)
    except NVMLError_NotSupported:
        return None
    except NVMLError as exc:
        logger.warning("CUDA compute capability unavailable: %s", exc)
        return None
    return f"{int(major)}.{int(minor)}"


def _gpu_brand_from_model(model: str | None) -> str | None:
    if not model:
        return None
    normalized = model.strip()
    if not normalized:
        return None

    upper = normalized.upper()
    if "NVIDIA" in upper:
        return "NVIDIA"
    if "AMD" in upper:
        return "AMD"
    if "INTEL" in upper:
        return "Intel"

    return normalized.split(" ", 1)[0]
