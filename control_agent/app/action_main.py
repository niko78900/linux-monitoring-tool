from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.action_router import router
from app.core.action_config import ActionServiceSettings, get_action_service_settings
from app.core.config import get_settings
from app.core.logging import configure_logging
from app.services.action_registry import load_action_registry
from app.services.action_service import DashboardActionService, HelperRunner
from app.services.action_store import ActionStore

base_settings = get_settings()
configure_logging(base_settings.log_level)
logger = logging.getLogger(__name__)


def create_app(
    *,
    action_settings: ActionServiceSettings | None = None,
    helper: HelperRunner | None = None,
) -> FastAPI:
    settings = action_settings or get_action_service_settings()

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        settings.validate_for_startup(require_helper=helper is None)
        registry = load_action_registry(settings.registry_path)
        store = ActionStore(
            settings.database_path,
            retention_records=settings.retention_records,
            retention_days=settings.retention_days,
        )
        service = DashboardActionService(
            settings=settings,
            registry=registry,
            store=store,
            helper=helper,
        )
        application.state.dashboard_action_service = service
        await service.start()
        logger.info(
            "Starting Dashboard action service with %s service target(s)",
            len(registry.services),
        )
        try:
            yield
        finally:
            await service.stop()
            logger.info("Stopping Dashboard action service")

    application = FastAPI(
        title="Linux Monitor Dashboard Action Service",
        version=base_settings.app_version,
        openapi_url=None,
        docs_url=None,
        redoc_url=None,
        lifespan=lifespan,
    )
    application.state.action_settings = settings
    application.include_router(router)

    @application.exception_handler(RequestValidationError)
    async def validation_error_handler(
        _request: Request,
        _exception: RequestValidationError,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"detail": "Request validation failed"},
        )

    @application.exception_handler(Exception)
    async def unhandled_exception_handler(
        request: Request,
        exception: Exception,
    ) -> JSONResponse:
        logger.error(
            "Dashboard action request failed on %s (%s)",
            request.url.path,
            type(exception).__name__,
        )
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"},
        )

    return application


app = create_app()
