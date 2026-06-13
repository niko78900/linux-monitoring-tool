from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.router import api_router
from app.core.config import get_settings
from app.core.logging import configure_logging
from app.services.alerts import AlertMonitor, create_alert_monitor
from app.services.history_collector import HistoryCollector, create_history_collector

settings = get_settings()
configure_logging(settings.log_level)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting %s v%s", settings.app_name, settings.app_version)
    logger.info("API prefix: %s", settings.api_prefix)

    collector: HistoryCollector | None = None
    alert_monitor: AlertMonitor | None = None
    if settings.history_enabled:
        collector = create_history_collector(settings)
        app.state.history_collector = collector
        await collector.start()
    else:
        app.state.history_collector = None

    alert_monitor = create_alert_monitor(settings)
    app.state.alert_monitor = alert_monitor
    await alert_monitor.start()

    try:
        yield
    finally:
        if alert_monitor is not None:
            await alert_monitor.stop()
        if collector is not None:
            await collector.stop()
        logger.info("Shutting down %s", settings.app_name)


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    openapi_url=f"{settings.api_prefix}/openapi.json",
    docs_url=f"{settings.api_prefix}/docs",
    redoc_url=f"{settings.api_prefix}/redoc",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=False,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.api_prefix)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled exception on %s", request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})
