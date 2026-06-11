from __future__ import annotations

from fastapi import APIRouter, Depends

from ...core.auth import require_bearer_token
from ...models.network import NeighborsResponse
from ...services.neighbors import read_neighbors

router = APIRouter(
    prefix="/neighbors",
    tags=["neighbors"],
    dependencies=[Depends(require_bearer_token)],
)

NOTICE = (
    "This is an approximate server-side neighbor view, not a complete router or DHCP inventory."
)


@router.get("", response_model=NeighborsResponse)
def get_neighbors() -> NeighborsResponse:
    return NeighborsResponse(neighbors=read_neighbors(), notice=NOTICE)
