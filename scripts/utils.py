"""MODULE: utils.py
PURPOSE: Shared utilities for the MCI506 Open-Meteo extraction layer.
AUTHOR: Andres Poiche
VERSION: 1.0.0

This module centralizes configuration loading, URL construction, logging, and
HTTP retry logic for the extraction layer. Functions are intentionally small
and deterministic so they can be reused by future scripts and tests.

Open-Meteo does not require credentials. This module must not introduce tokens,
keys, absolute local paths, or machine-specific paths.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


REQUIRED_CITY_FIELDS = {"id", "name", "lat", "lon"}


def load_cities(path: str | Path) -> list[dict[str, Any]]:
    """Load and validate the city configuration file."""
    config_path = Path(path)

    if not config_path.exists():
        raise FileNotFoundError(f"City config file not found: {config_path}")

    with config_path.open("r", encoding="utf-8-sig") as file:
        payload = json.load(file)

    cities = payload.get("cities")
    if not isinstance(cities, list) or not cities:
        raise ValueError("config/cities.json must contain a cities list.")

    for position, city in enumerate(cities, start=1):
        if not isinstance(city, dict):
            raise TypeError(f"City record #{position} must be a JSON object.")

        missing_fields = REQUIRED_CITY_FIELDS.difference(city)
        if missing_fields:
            raise ValueError(
                f"City record #{position} is missing fields: "
                f"{sorted(missing_fields)}"
            )

        try:
            float(city["lat"])
            float(city["lon"])
        except (TypeError, ValueError) as error:
            raise ValueError(
                f"City record #{position} has invalid lat/lon values."
            ) from error

    return cities


def build_url(base: str, lat: float, lon: float, **params: Any) -> str:
    """Build an Open-Meteo URL with encoded query parameters."""
    query_params: dict[str, Any] = {
        "latitude": lat,
        "longitude": lon,
        **params,
    }
    return f"{base}?{urlencode(query_params)}"


def get_logger(name: str) -> logging.Logger:
    """Create a standard console logger for pipeline scripts."""
    logger = logging.getLogger(name)

    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)

    handler = logging.StreamHandler()
    handler.setLevel(logging.INFO)
    handler.setFormatter(
        logging.Formatter(
            fmt="[%(levelname)s] %(asctime)s - %(name)s - %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )

    logger.addHandler(handler)
    return logger


def retry_get(url: str, max_retries: int = 3, timeout: int = 30) -> dict[str, Any]:
    """Execute an HTTP GET request with exponential backoff."""
    if max_retries < 1:
        raise ValueError("max_retries must be greater than or equal to 1.")

    delays_seconds = [2, 4, 8]
    last_error: Exception | None = None

    for attempt in range(1, max_retries + 1):
        try:
            request = Request(
                url,
                method="GET",
                headers={"User-Agent": "mci506-weather-risk-pipeline/1.0"},
            )

            with urlopen(request, timeout=timeout) as response:
                status_code = response.getcode()
                response_body = response.read().decode("utf-8")

            if status_code != 200:
                raise RuntimeError(f"Unexpected HTTP status code: {status_code}")

            payload = json.loads(response_body)
            if not isinstance(payload, dict):
                raise ValueError("Open-Meteo response is not a JSON object.")

            return payload

        except (HTTPError, URLError, TimeoutError, ValueError) as error:
            last_error = error

            if attempt == max_retries:
                break

            delay = delays_seconds[min(attempt - 1, len(delays_seconds) - 1)]
            time.sleep(delay)

    raise RuntimeError(
        f"GET request failed after {max_retries} attempts: {url}"
    ) from last_error