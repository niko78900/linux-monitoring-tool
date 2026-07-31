from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.api.read_only_router import router
from app.core.config import get_settings
from app.core.logging import configure_logging
from app.core.read_only_config import get_read_only_bridge_settings

settings = get_settings()
configure_logging(settings.log_level)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    get_read_only_bridge_settings().validate_for_startup()
    logger.info("Starting read-only Dashboard bridge v%s", settings.app_version)
    yield
    logger.info("Stopping read-only Dashboard bridge")


def create_app() -> FastAPI:
    application = FastAPI(
        title="Linux Monitor Dashboard Read-Only Bridge",
        version=settings.app_version,
        openapi_url=None,
        docs_url=None,
        redoc_url=None,
        lifespan=lifespan,
    )
    application.include_router(router)

    @application.exception_handler(Exception)
    async def unhandled_exception_handler(
        request: Request,
        exception: Exception,
    ) -> JSONResponse:
        logger.error(
            "Read-only bridge request failed on %s (%s)",
            request.url.path,
            type(exception).__name__,
        )
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"},
        )

    return application


app = create_app()
