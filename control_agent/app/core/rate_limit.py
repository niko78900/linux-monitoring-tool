from __future__ import annotations

import threading
import time
from collections.abc import Callable
from dataclasses import dataclass


@dataclass(frozen=True)
class RateLimitError(Exception):
    retry_after_seconds: int


class ActionRateLimiter:
    def __init__(self, time_source: Callable[[], float] | None = None) -> None:
        self._time_source = time_source or time.monotonic
        self._last_called: dict[str, float] = {}
        self._lock = threading.Lock()

    def check(self, action: str, window_seconds: int) -> None:
        now = self._time_source()
        with self._lock:
            last_called = self._last_called.get(action)
            if last_called is not None:
                elapsed = now - last_called
                if elapsed < window_seconds:
                    raise RateLimitError(retry_after_seconds=max(1, int(window_seconds - elapsed)))
            self._last_called[action] = now

    def reset(self) -> None:
        with self._lock:
            self._last_called.clear()


rate_limiter = ActionRateLimiter()
