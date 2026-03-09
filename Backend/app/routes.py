from datetime import datetime, timezone
import platform

from flask import Blueprint, jsonify

api = Blueprint("api", __name__, url_prefix="/api")


@api.get("/health")
def health():
    return jsonify(
        {
            "status": "ok",
            "service": "linux-monitoring-api",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "python": platform.python_version(),
        }
    )
