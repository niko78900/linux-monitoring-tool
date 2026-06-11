from __future__ import annotations

from pydantic import BaseModel


class ObservedNeighbor(BaseModel):
    ip: str
    mac_address: str | None = None
    interface_name: str | None = None
    state: str | None = None
    hostname: str | None = None


class NeighborsResponse(BaseModel):
    neighbors: list[ObservedNeighbor]
    notice: str
