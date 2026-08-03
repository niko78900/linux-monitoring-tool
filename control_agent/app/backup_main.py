from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.backup_router import router
from app.core.backup_config import BackupServiceSettings, get_backup_service_settings
from app.core.config import get_settings
from app.core.logging import configure_logging
from app.services.backup_executor import BackupHelper
from app.services.backup_registry import BackupRegistry, load_backup_registry
from app.services.backup_service import DashboardBackupService
from app.services.backup_store import BackupStore

base_settings = get_settings()
configure_logging(base_settings.log_level)
logger = logging.getLogger(__name__)


def create_app(
    *,
    backup_settings: BackupServiceSettings | None = None,
    helper: BackupHelper | None = None,
    registry_override: BackupRegistry | None = None,
) -> FastAPI:
    settings = backup_settings or get_backup_service_settings()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        settings.validate_for_startup(require_helper=helper is None)
        registry = registry_override or load_backup_registry(
            settings.registry_path,
            enforce_metadata=not settings.registry_is_credential,
        )
        store = BackupStore(
            settings.database_path,
            retention_records=settings.retention_records,
            retention_days=settings.retention_days,
        )
        service = DashboardBackupService(
            settings=settings,
            registry=registry,
            store=store,
            helper=helper,
            version=base_settings.app_version,
        )
        application.state.dashboard_backup_service = service
        await service.start()
        logger.info("Starting Dashboard backup service with %s plan(s)", len(registry.plans))
        try:
            yield
        finally:
            await service.stop()
            logger.info("Stopping Dashboard backup service")

    application = FastAPI(
        title="Linux Monitor Dashboard Backup Service",
        version=base_settings.app_version,
        openapi_url=None,
        docs_url=None,
        redoc_url=None,
        lifespan=lifespan,
    )
    application.state.backup_settings = settings
    application.include_router(router)

    @application.exception_handler(RequestValidationError)
    async def validation_error_handler(
        _request: Request,
        _exception: RequestValidationError,
    ) -> JSONResponse:
        return JSONResponse(status_code=422, content={"detail": "Request validation failed"})

    @application.exception_handler(Exception)
    async def unhandled_exception_handler(
        request: Request,
        exception: Exception,
    ) -> JSONResponse:
        logger.error(
            "Dashboard backup request failed on %s (%s)",
            request.url.path,
            type(exception).__name__,
        )
        return JSONResponse(status_code=500, content={"detail": "Internal server error"})

    return application


app = create_app()
