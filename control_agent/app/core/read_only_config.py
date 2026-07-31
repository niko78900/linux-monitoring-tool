from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from ipaddress import IPv4Network, IPv6Network, ip_network

AllowedNetwork = IPv4Network | IPv6Network


def _parse_allowed_networks(raw_value: str | None) -> tuple[AllowedNetwork, ...]:
    if not raw_value:
        return ()

    networks: list[AllowedNetwork] = []
    for raw_network in raw_value.split(","):
        candidate = raw_network.strip()
        if not candidate:
            continue
        try:
            networks.append(ip_network(candidate, strict=False))
        except ValueError as error:
            raise ValueError(
                "DASHBOARD_CONTROL_ALLOWED_NETWORKS contains an invalid network"
            ) from error
    return tuple(networks)


@dataclass(frozen=True)
class ReadOnlyBridgeSettings:
    token: str | None
    allowed_networks: tuple[AllowedNetwork, ...]

    def validate_for_startup(self) -> None:
        if self.token is None or len(self.token) < 32:
            raise RuntimeError(
                "DASHBOARD_CONTROL_READ_TOKEN must contain at least 32 characters"
            )
        if not self.allowed_networks:
            raise RuntimeError(
                "DASHBOARD_CONTROL_ALLOWED_NETWORKS must contain at least one network"
            )


@lru_cache(maxsize=1)
def get_read_only_bridge_settings() -> ReadOnlyBridgeSettings:
    raw_token = os.getenv("DASHBOARD_CONTROL_READ_TOKEN")
    token = raw_token.strip() if raw_token and raw_token.strip() else None
    return ReadOnlyBridgeSettings(
        token=token,
        allowed_networks=_parse_allowed_networks(
            os.getenv("DASHBOARD_CONTROL_ALLOWED_NETWORKS")
        ),
    )
