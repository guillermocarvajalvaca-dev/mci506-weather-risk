"""MODULE: load.py
PURPOSE: Upload raw Open-Meteo JSON files to GCS and stage them in BigQuery.
AUTHOR: Andres Poiche
VERSION: 1.0.0

This module implements the load layer for the MCI506 Weather Risk pipeline.

Input contract:
    Local raw JSON files produced by scripts/extract.py under data/raw/.

Storage contract:
    Upload immutable raw JSON objects to the Bronze GCS bucket.

BigQuery contract:
    Create and populate `mci506-weather-risk.silver.raw_weather_json` as the
    staging table consumed by sql/silver_transform.sql.

Security contract:
    This module must not contain secrets, service account contents, absolute
    local paths, or hardcoded credential values.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from google.api_core.exceptions import NotFound
from google.cloud import bigquery, storage

from utils import get_logger


DEFAULT_PROJECT_ID = "mci506-weather-risk"
DEFAULT_BUCKET_NAME = "mci506-weather-risk-bronze"
DEFAULT_SILVER_DATASET = "silver"
DEFAULT_RAW_TABLE = "raw_weather_json"
DEFAULT_INPUT_ROOT = "data/raw"


def load_environment() -> None:
    """Load local environment files without printing secret values."""
    load_dotenv(".env.local", override=False)
    load_dotenv(".env", override=False)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments for the load layer."""
    load_environment()

    parser = argparse.ArgumentParser(
        description="Upload raw Open-Meteo JSON files to GCS and BigQuery."
    )
    parser.add_argument(
        "--input-root",
        default=DEFAULT_INPUT_ROOT,
        help="Root folder containing local raw JSON files from extract.py.",
    )
    parser.add_argument(
        "--project-id",
        default=os.getenv("GCP_PROJECT_ID", DEFAULT_PROJECT_ID),
        help="Google Cloud project ID.",
    )
    parser.add_argument(
        "--bucket-name",
        default=os.getenv("GCS_BUCKET_NAME", DEFAULT_BUCKET_NAME),
        help="Bronze GCS bucket name.",
    )
    parser.add_argument(
        "--silver-dataset",
        default=os.getenv("BQ_SILVER_DATASET", DEFAULT_SILVER_DATASET),
        help="BigQuery Silver dataset ID.",
    )
    parser.add_argument(
        "--raw-table",
        default=DEFAULT_RAW_TABLE,
        help="BigQuery raw weather staging table name.",
    )
    parser.add_argument(
        "--gcs-prefix",
        default="",
        help="Optional prefix inside the Bronze bucket.",
    )
    parser.add_argument(
        "--allow-empty",
        action="store_true",
        help="Allow successful execution when no JSON files are found.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Plan the load without writing to GCS or BigQuery.",
    )

    return parser.parse_args()


def sha256_file(path: Path) -> str:
    """Compute a SHA256 checksum for one local file."""
    digest = hashlib.sha256()

    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)

    return digest.hexdigest()


def discover_json_files(input_root: Path) -> list[Path]:
    """Discover raw JSON files below the extract.py output root."""
    if not input_root.exists():
        raise FileNotFoundError(f"Input root does not exist: {input_root}")

    if not input_root.is_dir():
        raise NotADirectoryError(f"Input root is not a directory: {input_root}")

    return sorted(path for path in input_root.rglob("*.json") if path.is_file())


def read_json_payload(path: Path) -> dict[str, Any]:
    """Read and validate one raw Open-Meteo payload wrapper."""
    with path.open("r", encoding="utf-8-sig") as file:
        payload = json.load(file)

    if not isinstance(payload, dict):
        raise TypeError(f"Raw file is not a JSON object: {path}")

    meta = payload.get("meta")
    data = payload.get("data")

    if not isinstance(meta, dict):
        raise ValueError(f"Raw file is missing object field meta: {path}")

    if not isinstance(data, dict):
        raise ValueError(f"Raw file is missing object field data: {path}")

    required_meta = {
        "city_id",
        "city_name",
        "source_type",
        "extraction_date",
        "extraction_timestamp_utc",
        "record_count",
    }
    missing_meta = required_meta.difference(meta)

    if missing_meta:
        raise ValueError(
            f"Raw file {path} is missing meta fields: {sorted(missing_meta)}"
        )

    return payload


def build_gcs_blob_name(
    *,
    payload: dict[str, Any],
    local_path: Path,
    gcs_prefix: str,
) -> str:
    """Build the canonical Bronze object path for a raw JSON file."""
    meta = payload["meta"]
    extraction_date = str(meta["extraction_date"])
    year, month, day = extraction_date.split("-")

    parts = [
        str(meta["source_type"]),
        str(meta["city_id"]),
        year,
        month,
        day,
        local_path.name,
    ]

    normalized_prefix = gcs_prefix.strip("/")

    if normalized_prefix:
        return "/".join([normalized_prefix, *parts])

    return "/".join(parts)


def build_raw_file_record(
    *,
    local_path: Path,
    gcs_prefix: str,
) -> dict[str, Any]:
    """Build a validated load record from one local raw JSON file."""
    payload = read_json_payload(local_path)
    meta = payload["meta"]

    return {
        "local_path": local_path,
        "payload": payload,
        "city_id": str(meta["city_id"]),
        "city_name": str(meta["city_name"]),
        "source_type": str(meta["source_type"]),
        "extraction_date": str(meta["extraction_date"]),
        "extraction_timestamp_utc": str(meta["extraction_timestamp_utc"]),
        "record_count": int(meta["record_count"]),
        "payload_sha256": sha256_file(local_path),
        "gcs_blob_name": build_gcs_blob_name(
            payload=payload,
            local_path=local_path,
            gcs_prefix=gcs_prefix,
        ),
    }


def raw_weather_table_schema() -> list[bigquery.SchemaField]:
    """Return the schema for the Silver raw JSON staging table."""
    return [
        bigquery.SchemaField("source_type", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("city_id", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("city_name", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("extraction_date", "DATE", mode="REQUIRED"),
        bigquery.SchemaField(
            "extraction_timestamp_utc",
            "TIMESTAMP",
            mode="REQUIRED",
        ),
        bigquery.SchemaField("record_count", "INT64", mode="REQUIRED"),
        bigquery.SchemaField("gcs_uri", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("source_file_name", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("payload_sha256", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("payload", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("uploaded_at_utc", "TIMESTAMP", mode="REQUIRED"),
    ]


def ensure_raw_weather_table(
    *,
    client: bigquery.Client,
    project_id: str,
    dataset_id: str,
    table_name: str,
) -> str:
    """Create the raw weather staging table if it does not already exist."""
    table_id = f"{project_id}.{dataset_id}.{table_name}"

    try:
        client.get_table(table_id)
        return table_id
    except NotFound:
        table = bigquery.Table(table_id, schema=raw_weather_table_schema())
        client.create_table(table)
        return table_id


def upload_raw_file_to_gcs(
    *,
    client: storage.Client,
    bucket_name: str,
    record: dict[str, Any],
) -> str:
    """Upload one raw JSON file to the Bronze bucket."""
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(record["gcs_blob_name"])
    blob.upload_from_filename(
        str(record["local_path"]),
        content_type="application/json",
    )
    return f"gs://{bucket_name}/{record['gcs_blob_name']}"


def build_bigquery_row(
    *,
    record: dict[str, Any],
    gcs_uri: str,
    uploaded_at_utc: str,
) -> dict[str, Any]:
    """Build one BigQuery row for the raw weather staging table."""
    return {
        "source_type": record["source_type"],
        "city_id": record["city_id"],
        "city_name": record["city_name"],
        "extraction_date": record["extraction_date"],
        "extraction_timestamp_utc": record["extraction_timestamp_utc"],
        "record_count": record["record_count"],
        "gcs_uri": gcs_uri,
        "source_file_name": record["local_path"].name,
        "payload_sha256": record["payload_sha256"],
        "payload": json.dumps(
            record["payload"],
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        "uploaded_at_utc": uploaded_at_utc,
    }


def insert_rows(
    *,
    client: bigquery.Client,
    table_id: str,
    rows: list[dict[str, Any]],
) -> None:
    """Insert rows into BigQuery and fail loudly on insert errors."""
    if not rows:
        return

    row_ids = [
        f"{row['city_id']}:{row['source_type']}:{row['extraction_date']}"
        for row in rows
    ]

    errors = client.insert_rows_json(table_id, rows, row_ids=row_ids)

    if errors:
        raise RuntimeError(f"BigQuery insert_rows_json failed: {errors}")


def run_load(args: argparse.Namespace) -> None:
    """Run the GCS and BigQuery load workflow."""
    logger = get_logger("mci506.load")

    input_root = Path(args.input_root)
    json_files = discover_json_files(input_root)

    if not json_files and not args.allow_empty:
        raise FileNotFoundError(
            f"No JSON files found below {input_root}. Run scripts/extract.py first."
        )

    records = [
        build_raw_file_record(local_path=path, gcs_prefix=args.gcs_prefix)
        for path in json_files
    ]

    logger.info("Discovered raw JSON files: %s", len(records))

    if args.dry_run:
        for record in records:
            logger.info(
                "DRY RUN file=%s blob=%s source_type=%s city_id=%s records=%s",
                record["local_path"].as_posix(),
                record["gcs_blob_name"],
                record["source_type"],
                record["city_id"],
                record["record_count"],
            )
        logger.info("Dry run completed. No GCS or BigQuery writes performed.")
        return

    storage_client = storage.Client(project=args.project_id)
    bigquery_client = bigquery.Client(project=args.project_id)

    table_id = ensure_raw_weather_table(
        client=bigquery_client,
        project_id=args.project_id,
        dataset_id=args.silver_dataset,
        table_name=args.raw_table,
    )

    uploaded_at_utc = datetime.now(UTC).isoformat()
    rows: list[dict[str, Any]] = []

    for record in records:
        gcs_uri = upload_raw_file_to_gcs(
            client=storage_client,
            bucket_name=args.bucket_name,
            record=record,
        )
        rows.append(
            build_bigquery_row(
                record=record,
                gcs_uri=gcs_uri,
                uploaded_at_utc=uploaded_at_utc,
            )
        )
        logger.info("Uploaded raw file to %s", gcs_uri)

    insert_rows(client=bigquery_client, table_id=table_id, rows=rows)

    logger.info("BigQuery raw staging table: %s", table_id)
    logger.info("Rows inserted into raw staging table: %s", len(rows))
    logger.info("Load workflow completed successfully.")


def main() -> None:
    """Parse arguments and execute the load workflow."""
    args = parse_args()
    run_load(args)


if __name__ == "__main__":
    main()