from __future__ import annotations

from ipaddress import ip_address
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from fastapi.responses import JSONResponse

from ..core.backup_auth import (
    require_allowed_backup_source,
    require_dashboard_backup_token,
)
from ..models.dashboard_backups import (
    BackupAcceptedResponse,
    BackupErrorResponse,
    BackupHealthResponse,
    BackupJobHistoryResponse,
    BackupJobResponse,
    BackupPlanListResponse,
    BackupPlanResponse,
    BackupStartRequest,
)
from ..services.backup_service import (
    BackupQueueFullError,
    BackupStartRejected,
    DashboardBackupService,
)
from ..services.backup_store import BusyPlanError, CannotCancelError, JobNotFoundError

router = APIRouter(
    dependencies=[
        Depends(require_allowed_backup_source),
        Depends(require_dashboard_backup_token),
    ]
)


def get_backup_service(request: Request) -> DashboardBackupService:
    return request.app.state.dashboard_backup_service


@router.get("/health", response_model=BackupHealthResponse, tags=["backups"])
async def get_health(
    service: DashboardBackupService = Depends(get_backup_service),
) -> BackupHealthResponse:
    return await service.health()


@router.get("/plans", response_model=BackupPlanListResponse, tags=["backups"])
async def get_plans(
    service: DashboardBackupService = Depends(get_backup_service),
) -> BackupPlanListResponse:
    plans = [await service.describe_plan(plan) for plan in service.registry.plans]
    return BackupPlanListResponse(plans=plans)


@router.get("/plans/{plan_id}", response_model=BackupPlanResponse, tags=["backups"])
async def get_plan(
    plan_id: str,
    service: DashboardBackupService = Depends(get_backup_service),
) -> BackupPlanResponse:
    plan = service.registry.get_plan(plan_id)
    if plan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Backup plan not found")
    return await service.describe_plan(plan)


@router.get("/jobs", response_model=BackupJobHistoryResponse, tags=["backups"])
def get_jobs(
    limit: int = Query(default=50, ge=1, le=200),
    service: DashboardBackupService = Depends(get_backup_service),
) -> BackupJobHistoryResponse:
    return BackupJobHistoryResponse(jobs=service.store.list(limit=limit))


@router.get("/jobs/{job_id}", response_model=BackupJobResponse, tags=["backups"])
def get_job(
    job_id: UUID,
    service: DashboardBackupService = Depends(get_backup_service),
) -> BackupJobResponse:
    record = service.store.get(str(job_id))
    if record is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Backup job not found")
    return record


@router.post(
    "/plans/{plan_id}/jobs",
    response_model=BackupAcceptedResponse,
    status_code=status.HTTP_202_ACCEPTED,
    responses={
        409: {"model": BackupErrorResponse},
        429: {"model": BackupErrorResponse},
        507: {"model": BackupErrorResponse},
    },
    tags=["backups"],
)
async def start_backup(
    plan_id: str,
    request_body: BackupStartRequest,
    request: Request,
    response: Response,
    service: DashboardBackupService = Depends(get_backup_service),
) -> BackupAcceptedResponse | JSONResponse:
    plan = service.registry.get_plan(plan_id)
    if plan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Backup plan not found")
    try:
        accepted = await service.accept(
            plan=plan,
            request_body=request_body,
            source_address=_source_address(request),
        )
    except BusyPlanError:
        return _error_response(
            status_code=409,
            detail="This backup plan already has an active job.",
            error_code="plan_busy",
        )
    except BackupQueueFullError:
        return _error_response(
            status_code=429,
            detail="Backup queue is full.",
            error_code="queue_full",
        )
    except BackupStartRejected as error:
        return _error_response(
            status_code=error.status_code,
            detail=error.summary,
            error_code=error.error_code,
            job_id=error.record.job_id,
        )
    response.status_code = status.HTTP_200_OK if accepted.duplicate else status.HTTP_202_ACCEPTED
    response.headers["Location"] = accepted.polling_location
    return accepted


@router.post(
    "/jobs/{job_id}/cancel",
    response_model=BackupJobResponse,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["backups"],
)
async def cancel_backup(
    job_id: UUID,
    service: DashboardBackupService = Depends(get_backup_service),
) -> BackupJobResponse:
    try:
        return await service.cancel(str(job_id))
    except JobNotFoundError as error:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Backup job not found",
        ) from error
    except CannotCancelError as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Backup job is already terminal",
        ) from error


def _source_address(request: Request) -> str:
    client_host = request.client.host if request.client is not None else ""
    return str(ip_address(client_host))


def _error_response(
    *,
    status_code: int,
    detail: str,
    error_code: str,
    job_id: UUID | None = None,
) -> JSONResponse:
    payload = BackupErrorResponse(
        detail=detail,
        error_code=error_code,
        job_id=job_id,
    )
    return JSONResponse(status_code=status_code, content=payload.model_dump(mode="json"))
