from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.core.config import Settings, get_settings
from app.models.history import (
    DiskHistoryResponse,
    HistoryRange,
    HistoryRangesResponse,
    OverviewHistoryResponse,
    RaidHistoryResponse,
    StorageHistoryResponse,
)
from app.services.history_queries import (
    build_ranges_response,
    get_disk_history,
    get_overview_history,
    get_raid_history,
    get_storage_history,
    resolve_window,
)
from app.services.history_store import HistoryStore

router = APIRouter(prefix="/history")


@router.get("/ranges", response_model=HistoryRangesResponse)
def history_ranges(settings: Settings = Depends(get_settings)) -> HistoryRangesResponse:
    return build_ranges_response(settings.history_max_response_points)


@router.get("/overview", response_model=OverviewHistoryResponse)
def overview_history(
    range: HistoryRange = Query("24h"),
    max_points: int = Query(360, ge=1),
    settings: Settings = Depends(get_settings),
) -> OverviewHistoryResponse:
    store = HistoryStore(settings.history_db_path)
    store.initialize()
    window = resolve_window(range, max_points, settings.history_max_response_points)
    return get_overview_history(store, window)


@router.get("/storage", response_model=StorageHistoryResponse)
def storage_history(
    mountpoint: str = Query(..., min_length=1),
    range: HistoryRange = Query("24h"),
    max_points: int = Query(360, ge=1),
    settings: Settings = Depends(get_settings),
) -> StorageHistoryResponse:
    store = HistoryStore(settings.history_db_path)
    store.initialize()
    window = resolve_window(range, max_points, settings.history_max_response_points)
    return get_storage_history(store, window, mountpoint)


@router.get("/disks", response_model=DiskHistoryResponse)
def disk_history(
    device: str = Query(..., min_length=1),
    range: HistoryRange = Query("24h"),
    max_points: int = Query(360, ge=1),
    settings: Settings = Depends(get_settings),
) -> DiskHistoryResponse:
    store = HistoryStore(settings.history_db_path)
    store.initialize()
    window = resolve_window(range, max_points, settings.history_max_response_points)
    return get_disk_history(store, window, device)


@router.get("/raid", response_model=RaidHistoryResponse)
def raid_history(
    array: str = Query(..., min_length=1),
    range: HistoryRange = Query("24h"),
    max_points: int = Query(360, ge=1),
    settings: Settings = Depends(get_settings),
) -> RaidHistoryResponse:
    store = HistoryStore(settings.history_db_path)
    store.initialize()
    window = resolve_window(range, max_points, settings.history_max_response_points)
    return get_raid_history(store, window, array)
