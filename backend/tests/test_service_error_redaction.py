from __future__ import annotations

from app.services import docker_service, gpu_service


def test_docker_metrics_redacts_unexpected_exception(monkeypatch) -> None:
    def failing_client_factory() -> object:
        raise RuntimeError("socket error at /var/run/docker.sock")

    monkeypatch.setattr(docker_service, "docker", object())
    monkeypatch.setattr(docker_service, "_create_docker_client", failing_client_factory)

    response = docker_service.get_docker_metrics()
    assert response.docker_available is False
    assert response.reason == "Unexpected Docker error."
    assert "/var/run/docker.sock" not in (response.reason or "")


def test_gpu_metrics_redacts_nvml_error_details(monkeypatch) -> None:
    def failing_nvml_init() -> None:
        raise RuntimeError("NVML device 0000:17:00.0")

    monkeypatch.setattr(gpu_service, "nvmlInit", failing_nvml_init)
    monkeypatch.setattr(gpu_service, "NVMLError", RuntimeError)

    response = gpu_service.get_gpu_metrics()
    assert response.available is False
    assert response.reason == "GPU telemetry unavailable."
    assert "0000:17:00.0" not in (response.reason or "")


def test_gpu_static_specs_redacts_unexpected_exception(monkeypatch) -> None:
    def failing_nvml_init() -> None:
        raise ValueError("unexpected library path: /usr/lib64")

    monkeypatch.setattr(gpu_service, "nvmlInit", failing_nvml_init)
    monkeypatch.setattr(gpu_service, "NVMLError", RuntimeError)

    response = gpu_service.get_gpu_static_specs()
    assert response.available is False
    assert response.reason == "Unexpected GPU error."
    assert "/usr/lib64" not in (response.reason or "")
