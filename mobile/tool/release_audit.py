from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

SECRET_MARKERS = (
    b"replace-with-long-random-token",
    b"BEGIN OPENSSH PRIVATE KEY",
    b"BEGIN RSA PRIVATE KEY",
    b"BEGIN EC PRIVATE KEY",
    b"BEGIN PRIVATE KEY",
)

SUSPICIOUS_SUFFIXES = (
    ".env",
    ".jks",
    ".keystore",
    ".key",
    ".pem",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk_path", type=Path)
    args = parser.parse_args()

    apk_path = args.apk_path
    if not apk_path.is_file():
        print(f"APK not found: {apk_path}", file=sys.stderr)
        return 2

    payload = apk_path.read_bytes()
    findings: list[str] = []

    for marker in SECRET_MARKERS:
        if marker in payload:
            findings.append(f"matched forbidden marker: {marker.decode('ascii', errors='ignore')}")

    with zipfile.ZipFile(apk_path) as archive:
        for name in archive.namelist():
            lowered = name.lower()
            if lowered.endswith(SUSPICIOUS_SUFFIXES):
                findings.append(f"suspicious embedded file: {name}")
            if lowered.endswith("key.properties"):
                findings.append(f"suspicious embedded file: {name}")

    if findings:
        print("Release audit failed:")
        for finding in findings:
            print(f"- {finding}")
        return 1

    print("Release audit passed: no configured secret markers found in APK.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
