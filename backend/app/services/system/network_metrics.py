from __future__ import annotations

import logging

from app.models.system import NetworkMetrics

try:
    import psutil
except ImportError:  # pragma: no cover - handled at runtime
    psutil = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)


def get_network_metrics() -> NetworkMetrics:
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
