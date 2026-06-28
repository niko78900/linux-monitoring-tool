from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ...core.auth import require_bearer_token
from ...core.config import Settings, get_settings
from ...models.benchmarks import BenchmarkStartRequest, BenchmarkStatusResponse
from ...services.benchmark_runner import (
    BenchmarkAlreadyRunningError,
    BenchmarkRunner,
    BenchmarkUnavailableError,
)

router = APIRouter(
    prefix="/benchmarks",
    tags=["benchmarks"],
    dependencies=[Depends(require_bearer_token)],
)

benchmark_runner = BenchmarkRunner()


@router.get("/status", response_model=BenchmarkStatusResponse)
def get_benchmark_status(
    settings: Settings = Depends(get_settings),
) -> BenchmarkStatusResponse:
    return benchmark_runner.status(settings)


@router.post(
    "/start",
    response_model=BenchmarkStatusResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def start_benchmark(
    request: BenchmarkStartRequest,
    settings: Settings = Depends(get_settings),
) -> BenchmarkStatusResponse:
    try:
        return benchmark_runner.start(request, settings)
    except BenchmarkAlreadyRunningError as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(error),
        ) from error
    except BenchmarkUnavailableError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(error),
        ) from error
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error),
        ) from error


@router.post(
    "/stop",
    response_model=BenchmarkStatusResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def stop_benchmark(
    settings: Settings = Depends(get_settings),
) -> BenchmarkStatusResponse:
    return benchmark_runner.stop(settings)
