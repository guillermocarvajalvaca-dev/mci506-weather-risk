"""MODULE: extract.py
PURPOSE: Extract Open-Meteo historical and forecast data for Bolivian cities.
AUTHOR: Andres Poiche
VERSION: 1.0.0

This script reads config/cities.json, calls Open-Meteo without credentials,
adds auditable metadata, and writes raw JSON files under data/raw/.

The output is local raw data and must remain excluded from Git. The script is
the first executable artifact of the data engineering ingestion flow.
"""

from __future__ import annotations

import argparse
import json
from datetime import UTC, date, datetime
from pathlib import Path
from time import perf_counter
from typing import Any

from utils import build_url, get_logger, load_cities, retry_get


ARCHIVE_BASE_URL = "https://archive-api.open-meteo.com/v1/archive"
FORECAST_BASE_URL = "https://api.open-meteo.com/v1/forecast"
TIMEZONE = "America/La_Paz"

HISTORICAL_DAILY_VARIABLES = [
    "temperature_2m_max",
    "temperature_2m_min",
    "temperature_2m_mean",
    "precipitation_sum",
    "windspeed_10m_max",
    "weathercode",
    "et0_fao_evapotranspiration",
]

FORECAST_DAILY_VARIABLES = [
    "temperature_2m_max",
    "temperature_2m_min",
    "precipitation_sum",
    "windspeed_10m_max",
    "weathercode",
]


def default_start_date(today: date) -> date:
    """Return the default historical extraction start date."""
    return date(today.year - 3, 1, 1)


def validate_daily_payload(payload: dict[str, Any], endpoint_name: str) -> None:
    """Validate the minimum Open-Meteo structure required by the pipeline."""
    required_root_fields = {"latitude", "longitude", "daily"}
    missing_root_fields = required_root_fields.difference(payload)

    if missing_root_fields:
        raise ValueError(
            f"{endpoint_name} response is missing root fields: "
            f"{sorted(missing_root_fields)}"
        )

    daily = payload["daily"]
    if not isinstance(daily, dict):
        raise TypeError(f"{endpoint_name} field daily must be a JSON object.")

    time_values = daily.get("time")
    if not isinstance(time_values, list) or not time_values:
        raise ValueError(
            f"{endpoint_name} response needs a non-empty daily.time array."
        )


def count_daily_records(payload: dict[str, Any]) -> int:
    """Count records using the Open-Meteo daily.time array."""
    daily = payload.get("daily", {})
    time_values = daily.get("time", []) if isinstance(daily, dict) else []

    if not isinstance(time_values, list):
        return 0

    return len(time_values)


def build_raw_payload(
    *,
    city: dict[str, Any],
    source_url: str,
    source_type: str,
    payload: dict[str, Any],
    extraction_date: date,
) -> dict[str, Any]:
    """Wrap the Open-Meteo response with auditable project metadata."""
    return {
        "meta": {
            "project": "mci506-weather-risk",
            "source_system": "Open-Meteo",
            "source_type": source_type,
            "extraction_date": extraction_date.isoformat(),
            "extraction_timestamp_utc": datetime.now(UTC).isoformat(),
            "city_id": city["id"],
            "city_name": city["name"],
            "latitude": float(city["lat"]),
            "longitude": float(city["lon"]),
            "elevation_m": city.get("elevation_m"),
            "timezone": TIMEZONE,
            "source_url": source_url,
            "record_count": count_daily_records(payload),
        },
        "data": payload,
    }


def write_json_payload(
    *,
    output_root: Path,
    city_id: str,
    source_type: str,
    extraction_date: date,
    payload: dict[str, Any],
) -> Path:
    """Write one raw JSON payload using a city/date partitioned path."""
    partition_dir = (
        output_root
        / city_id
        / f"{extraction_date:%Y}"
        / f"{extraction_date:%m}"
        / f"{extraction_date:%d}"
    )
    partition_dir.mkdir(parents=True, exist_ok=True)

    output_file = partition_dir / f"{source_type}_{extraction_date:%Y%m%d}.json"

    with output_file.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)

    return output_file


def build_historical_url(
    *,
    city: dict[str, Any],
    start_date: date,
    end_date: date,
) -> str:
    """Build the historical Open-Meteo URL."""
    return build_url(
        ARCHIVE_BASE_URL,
        lat=float(city["lat"]),
        lon=float(city["lon"]),
        start_date=start_date.isoformat(),
        end_date=end_date.isoformat(),
        daily=",".join(HISTORICAL_DAILY_VARIABLES),
        timezone=TIMEZONE,
    )


def build_forecast_url(city: dict[str, Any], forecast_days: int) -> str:
    """Build the forecast Open-Meteo URL."""
    return build_url(
        FORECAST_BASE_URL,
        lat=float(city["lat"]),
        lon=float(city["lon"]),
        daily=",".join(FORECAST_DAILY_VARIABLES),
        forecast_days=forecast_days,
        timezone=TIMEZONE,
    )


def extract_city(
    *,
    city: dict[str, Any],
    start_date: date,
    end_date: date,
    forecast_days: int,
    output_root: Path,
    extraction_date: date,
) -> list[Path]:
    """Extract historical and forecast data for one city."""
    logger = get_logger("mci506.extract")
    city_start = perf_counter()
    written_files: list[Path] = []

    historical_url = build_historical_url(
        city=city,
        start_date=start_date,
        end_date=end_date,
    )
    logger.info("Extracting historical data for city_id=%s", city["id"])
    historical_response = retry_get(historical_url)
    validate_daily_payload(historical_response, "historical")

    historical_payload = build_raw_payload(
        city=city,
        source_url=historical_url,
        source_type="historical",
        payload=historical_response,
        extraction_date=extraction_date,
    )
    written_files.append(
        write_json_payload(
            output_root=output_root,
            city_id=str(city["id"]),
            source_type="historical",
            extraction_date=extraction_date,
            payload=historical_payload,
        )
    )

    forecast_url = build_forecast_url(city, forecast_days)
    logger.info("Extracting forecast data for city_id=%s", city["id"])
    forecast_response = retry_get(forecast_url)
    validate_daily_payload(forecast_response, "forecast")

    forecast_payload = build_raw_payload(
        city=city,
        source_url=forecast_url,
        source_type="forecast",
        payload=forecast_response,
        extraction_date=extraction_date,
    )
    written_files.append(
        write_json_payload(
            output_root=output_root,
            city_id=str(city["id"]),
            source_type="forecast",
            extraction_date=extraction_date,
            payload=forecast_payload,
        )
    )

    elapsed_seconds = perf_counter() - city_start
    logger.info(
        "City completed: city_id=%s files=%s seconds=%.2f",
        city["id"],
        len(written_files),
        elapsed_seconds,
    )

    return written_files


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    today = date.today()

    parser = argparse.ArgumentParser(
        description="Extract Open-Meteo data for Bolivian cities."
    )
    parser.add_argument(
        "--cities-path",
        default="config/cities.json",
        help="Path to config/cities.json.",
    )
    parser.add_argument(
        "--output-root",
        default="data/raw",
        help="Root directory for local raw JSON outputs.",
    )
    parser.add_argument(
        "--start-date",
        default=default_start_date(today).isoformat(),
        help="Historical start date in YYYY-MM-DD format.",
    )
    parser.add_argument(
        "--end-date",
        default=today.isoformat(),
        help="Historical end date in YYYY-MM-DD format.",
    )
    parser.add_argument(
        "--forecast-days",
        type=int,
        default=7,
        help="Number of forecast days to request.",
    )

    return parser.parse_args()


def main() -> None:
    """Run the Open-Meteo extraction workflow for all configured cities."""
    args = parse_args()
    logger = get_logger("mci506.extract")

    start_date = date.fromisoformat(args.start_date)
    end_date = date.fromisoformat(args.end_date)

    if start_date > end_date:
        raise ValueError("start-date cannot be later than end-date.")

    if not 1 <= args.forecast_days <= 16:
        raise ValueError("forecast-days must be between 1 and 16.")

    cities = load_cities(args.cities_path)
    output_root = Path(args.output_root)
    extraction_date = date.today()

    logger.info("Loaded %s cities from %s", len(cities), args.cities_path)
    logger.info("Historical window: %s to %s", start_date, end_date)

    all_written_files: list[Path] = []

    for city in cities:
        try:
            city_files = extract_city(
                city=city,
                start_date=start_date,
                end_date=end_date,
                forecast_days=args.forecast_days,
                output_root=output_root,
                extraction_date=extraction_date,
            )
        except Exception:
            logger.exception("Extraction failed for city_id=%s", city.get("id"))
            raise

        all_written_files.extend(city_files)

    logger.info("Extraction completed. Files written: %s", len(all_written_files))

    for file_path in all_written_files:
        logger.info("Written file: %s", file_path.as_posix())


if __name__ == "__main__":
    main()