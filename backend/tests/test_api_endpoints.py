from __future__ import annotations

from datetime import datetime

from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.docker import DockerContainerInfo, DockerResponse
from app.models.gpu import GPUResponse
from app.models.summary import SummaryResponse


def _sample_system_payload() -> dict:
    return {
        "hostname": "homelab-server",
        "os": {
            "system": "Linux",
            "release": "6.8.0",
            "version": "#1 SMP",
            "machine": "x86_64",
            "platform": "Linux-6.8.0-x86_64",
        },
        "kernel_version": "6.8.0",
        "specs": {
            "cpu": {
                "model_name": "AMD Ryzen 7 5800X",
                "vendor": "AuthenticAMD",
                "architecture": "x86_64",
                "physical_cores": 8,
                "logical_cores": 16,
                "min_frequency_mhz": 2200.0,
                "max_frequency_mhz": 4700.0,
                "capabilities": ["sse2", "avx2", "aes"],
            },
            "memory_total_bytes": 34359738368,
            "swap_total_bytes": 8589934592,
            "memory": {
                "total_bytes": 34359738368,
                "speed_mhz": 3200,
                "memory_type": "DDR4",
                "manufacturers": ["Kingston"],
                "modules": [
                    {
                        "slot": "DIMM_A1",
                        "manufacturer": "Kingston",
                        "part_number": "HX432C16",
                        "memory_type": "DDR4",
                        "size_bytes": 17179869184,
                        "speed_mhz": 3200,
                    }
                ],
            },
            "motherboard": {
                "vendor": "ASUS",
                "model": "TUF GAMING B550-PLUS",
                "version": "Rev 1.xx",
                "chipset": "B550",
            },
            "gpu": {
                "available": True,
                "reason": None,
                "brand": "NVIDIA",
                "model": "GeForce RTX 3070",
                "driver_version": "555.99",
                "vram_total_mb": 8192,
                "cuda_compute_capability": "8.6",
                "capabilities": ["temperature telemetry", "memory telemetry"],
            },
        },
        "uptime_seconds": 123456,
        "uptime_human": "1 day, 10 hours",
        "boot_time": "2026-03-10T10:00:00Z",
        "cpu": {
            "usage_percent": 23.5,
            "physical_cores": 8,
            "logical_cores": 16,
            "load_average": {
                "one_min": 0.7,
                "five_min": 0.9,
                "fifteen_min": 1.2,
            },
        },
        "memory": {
            "total": 34359738368,
            "available": 21474836480,
            "used": 12884901888,
            "percent": 37.5,
        },
        "swap": {
            "total": 8589934592,
            "used": 1073741824,
            "percent": 12.5,
        },
        "disk": {
            "total": 1000000000000,
            "used": 450000000000,
            "free": 550000000000,
            "percent": 45.0,
            "mountpoint": "/",
        },
        "disks": [
            {
                "device": "/dev/sda1",
                "mountpoint": "/",
                "fstype": "ext4",
                "total": 1000000000000,
                "used": 450000000000,
                "free": 550000000000,
                "percent": 45.0,
                "read_only": False,
                "available": True,
                "raid_array": None,
                "raid_level": None,
                "health": {"status": "healthy", "reason": "Disk usage is within normal range."},
            }
        ],
        "raid_arrays": [
            {
                "name": "md0",
                "device": "/dev/md0",
                "level": "raid1",
                "state": "clean",
                "raid_disks": 2,
                "active_devices": 2,
                "degraded_devices": 0,
                "sync_action": "idle",
                "members": ["/dev/sda1", "/dev/sdb1"],
                "health": {"status": "healthy", "reason": "RAID array reports healthy state."},
            }
        ],
        "physical_disks": [
            {
                "name": "sda",
                "device": "/dev/sda",
                "model": "Samsung SSD",
                "vendor": "Samsung",
                "serial": "XYZ123",
                "size_bytes": 1000000000000,
                "rotational": False,
                "removable": False,
                "state": "running",
                "mounted_partitions": ["/"],
                "raid_arrays": ["md0"],
                "health": {"status": "healthy", "reason": "Physical disk reports healthy kernel state."},
            }
        ],
        "network": {
            "bytes_sent": 123456789,
            "bytes_recv": 987654321,
            "packets_sent": 123456,
            "packets_recv": 654321,
            "top_speed_mbps": 1000,
        },
    }


def test_health_endpoint_returns_expected_payload(client: TestClient, api_prefix: str) -> None:
    response = client.get(f"{api_prefix}/health")
    assert response.status_code == 200

    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["app_name"] == get_settings().app_name
    assert payload["version"] == get_settings().app_version
    datetime.fromisoformat(payload["timestamp"].replace("Z", "+00:00"))


def test_docs_and_openapi_are_exposed(client: TestClient, api_prefix: str) -> None:
    docs_response = client.get(f"{api_prefix}/docs")
    assert docs_response.status_code == 200
    assert "text/html" in docs_response.headers.get("content-type", "")

    openapi_response = client.get(f"{api_prefix}/openapi.json")
    assert openapi_response.status_code == 200
    openapi = openapi_response.json()
    assert f"{api_prefix}/health" in openapi["paths"]
    assert f"{api_prefix}/system" in openapi["paths"]
    assert f"{api_prefix}/gpu" in openapi["paths"]
    assert f"{api_prefix}/docker" in openapi["paths"]
    assert f"{api_prefix}/summary" in openapi["paths"]


def test_system_endpoint_returns_service_data(client: TestClient, api_prefix: str, monkeypatch) -> None:
    from app.api.routes import system as system_route

    seen_mountpoint: dict[str, str] = {}

    def fake_get_system_metrics(mountpoint: str) -> dict:
        seen_mountpoint["value"] = mountpoint
        return _sample_system_payload()

    monkeypatch.setattr(system_route, "get_system_metrics", fake_get_system_metrics)

    response = client.get(f"{api_prefix}/system")
    assert response.status_code == 200

    payload = response.json()
    assert seen_mountpoint["value"] == get_settings().disk_mountpoint
    assert payload["hostname"] == "homelab-server"
    assert payload["cpu"]["logical_cores"] == 16
    assert payload["disks"][0]["health"]["status"] == "healthy"
    assert payload["raid_arrays"][0]["name"] == "md0"
    assert payload["physical_disks"][0]["device"] == "/dev/sda"


def test_gpu_endpoint_available_response(client: TestClient, api_prefix: str, monkeypatch) -> None:
    from app.api.routes import gpu as gpu_route

    monkeypatch.setattr(
        gpu_route,
        "get_gpu_metrics",
        lambda: GPUResponse(
            available=True,
            reason=None,
            name="NVIDIA RTX 3070",
            temperature_c=55,
            utilization_percent=28.5,
            memory_total_mb=8192,
            memory_used_mb=2048,
            memory_free_mb=6144,
            power_usage_w=118.2,
            fan_speed_percent=43,
            driver_version="555.99",
        ),
    )

    response = client.get(f"{api_prefix}/gpu")
    assert response.status_code == 200

    payload = response.json()
    assert payload["available"] is True
    assert payload["name"] == "NVIDIA RTX 3070"
    assert payload["utilization_percent"] == 28.5


def test_gpu_endpoint_unavailable_response(client: TestClient, api_prefix: str, monkeypatch) -> None:
    from app.api.routes import gpu as gpu_route

    monkeypatch.setattr(
        gpu_route,
        "get_gpu_metrics",
        lambda: GPUResponse(available=False, reason="No NVIDIA GPU detected."),
    )

    response = client.get(f"{api_prefix}/gpu")
    assert response.status_code == 200
    payload = response.json()
    assert payload["available"] is False
    assert payload["reason"] == "No NVIDIA GPU detected."
    assert payload["name"] is None


def test_docker_endpoint_returns_service_data(client: TestClient, api_prefix: str, monkeypatch) -> None:
    from app.api.routes import docker as docker_route

    docker_payload = DockerResponse(
        docker_available=True,
        reason=None,
        container_count=2,
        containers=[
            DockerContainerInfo(
                id="abc123",
                name="grafana",
                image="grafana/grafana:latest",
                state="running",
                status="running",
                ports={"3000/tcp": ["0.0.0.0:3000"]},
                created="2026-03-10T10:00:00Z",
                running_for="2 hours",
            ),
            DockerContainerInfo(
                id="def456",
                name="prometheus",
                image="prom/prometheus:latest",
                state="exited",
                status="exited",
                ports={},
                created="2026-03-10T09:00:00Z",
                running_for=None,
            ),
        ],
    )
    monkeypatch.setattr(docker_route, "get_docker_metrics", lambda: docker_payload)

    response = client.get(f"{api_prefix}/docker")
    assert response.status_code == 200

    payload = response.json()
    assert payload["docker_available"] is True
    assert payload["container_count"] == 2
    assert payload["containers"][0]["name"] == "grafana"
    assert payload["containers"][1]["state"] == "exited"


def test_summary_endpoint_returns_service_data(client: TestClient, api_prefix: str, monkeypatch) -> None:
    from app.api.routes import summary as summary_route

    seen_mountpoint: dict[str, str] = {}

    def fake_get_summary_metrics(mountpoint: str) -> SummaryResponse:
        seen_mountpoint["value"] = mountpoint
        return SummaryResponse(
            hostname="homelab-server",
            uptime_human="2 days",
            cpu_percent=19.5,
            memory_percent=43.2,
            disk_percent=58.7,
            gpu_available=True,
            gpu_utilization_percent=25.0,
            gpu_temp_c=57,
            docker_available=True,
            running_containers=6,
        )

    monkeypatch.setattr(summary_route, "get_summary_metrics", fake_get_summary_metrics)

    response = client.get(f"{api_prefix}/summary")
    assert response.status_code == 200

    payload = response.json()
    assert seen_mountpoint["value"] == get_settings().disk_mountpoint
    assert payload["hostname"] == "homelab-server"
    assert payload["running_containers"] == 6
    assert payload["gpu_available"] is True


def test_unhandled_service_exception_returns_500(api_prefix: str, monkeypatch) -> None:
    from app.api.routes import system as system_route

    def failing_service(_: str) -> dict:
        raise RuntimeError("boom")

    monkeypatch.setattr(system_route, "get_system_metrics", failing_service)

    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.get(f"{api_prefix}/system")

    assert response.status_code == 500
    assert response.json() == {"detail": "Internal server error"}
