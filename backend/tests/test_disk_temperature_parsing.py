from __future__ import annotations

import pytest

from app.services.system.storage_metrics import (
    _normalize_temperature,
    _parse_smartctl_json_temperature,
    _parse_smartctl_text_temperature,
)


def test_parse_smartctl_json_temperature_from_ata_attributes() -> None:
    raw_json = """
    {
      "ata_smart_attributes": {
        "table": [
          {"id": 1, "raw": {"value": 0}},
          {"id": 194, "raw": {"value": 37}}
        ]
      }
    }
    """

    assert _parse_smartctl_json_temperature(raw_json) == 37.0


def test_parse_smartctl_json_temperature_from_nvme_kelvin_value() -> None:
    raw_json = """
    {
      "nvme_smart_health_information_log": {
        "temperature": 315
      }
    }
    """

    assert _parse_smartctl_json_temperature(raw_json) == 41.9


def test_parse_smartctl_text_temperature() -> None:
    raw_text = """
    SMART Attributes Data Structure revision number: 16
    194 Temperature_Celsius     0x0022   063   046   000    Old_age   Always       -       37
    """

    assert _parse_smartctl_text_temperature(raw_text) == 37.0


def test_normalize_temperature_rejects_out_of_range_values() -> None:
    assert _normalize_temperature(-55) is None
    assert _normalize_temperature(260) == pytest.approx(-13.15, abs=0.01)
    assert _normalize_temperature(1000) is None
