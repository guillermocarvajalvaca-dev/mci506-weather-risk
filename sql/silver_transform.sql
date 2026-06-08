-- MODULE: silver_transform.sql
-- AUTHOR: Montserrat Barba
-- PROJECT: MCI506 Weather Risk Intelligence
-- LAYER: Silver - BigQuery
-- PURPOSE:
--   Transform raw Open-Meteo JSON payloads from
--   `mci506-weather-risk.silver.raw_weather_json`
--   into typed, deduplicated Silver tables.
--
-- CONTRACT:
--   Bronze raw files live in GCS.
--   BigQuery reads staged raw JSON from:
--     `mci506-weather-risk.silver.raw_weather_json`
--   This script creates and populates:
--     `mci506-weather-risk.silver.cities_dim`
--     `mci506-weather-risk.silver.weathercode_dim`
--     `mci506-weather-risk.silver.daily_weather_clean`
--     `mci506-weather-risk.silver.quarantine_log`
--
-- EXECUTION:
--   Run in BigQuery Standard SQL as a script.
--
-- SAFETY:
--   This file creates Silver tables only.
--   Gold tables must be implemented in a separate PR.

CREATE OR REPLACE TABLE `mci506-weather-risk.silver.cities_dim` AS
SELECT 'santa_cruz' AS city_id, 'Santa Cruz de la Sierra' AS city_name, -17.7833 AS latitude, -63.1833 AS longitude, 416 AS elevation_m, 'Santa Cruz' AS department, 'Lowlands' AS region
UNION ALL SELECT 'la_paz', 'La Paz', -16.5000, -68.1500, 3640, 'La Paz', 'Altiplano'
UNION ALL SELECT 'cochabamba', 'Cochabamba', -17.3895, -66.1568, 2558, 'Cochabamba', 'Valleys'
UNION ALL SELECT 'sucre', 'Sucre', -19.0431, -65.2591, 2810, 'Chuquisaca', 'Valleys'
UNION ALL SELECT 'oruro', 'Oruro', -17.9833, -67.1500, 3706, 'Oruro', 'Altiplano'
UNION ALL SELECT 'tarija', 'Tarija', -21.5353, -64.7298, 1866, 'Tarija', 'Valleys';

CREATE OR REPLACE TABLE `mci506-weather-risk.silver.weathercode_dim` AS
SELECT 0 AS weathercode, 'Clear sky' AS weather_description
UNION ALL SELECT 1, 'Mainly clear'
UNION ALL SELECT 2, 'Partly cloudy'
UNION ALL SELECT 3, 'Overcast'
UNION ALL SELECT 45, 'Fog'
UNION ALL SELECT 48, 'Depositing rime fog'
UNION ALL SELECT 51, 'Light drizzle'
UNION ALL SELECT 53, 'Moderate drizzle'
UNION ALL SELECT 55, 'Dense drizzle'
UNION ALL SELECT 61, 'Slight rain'
UNION ALL SELECT 63, 'Moderate rain'
UNION ALL SELECT 65, 'Heavy rain'
UNION ALL SELECT 71, 'Slight snow fall'
UNION ALL SELECT 73, 'Moderate snow fall'
UNION ALL SELECT 75, 'Heavy snow fall'
UNION ALL SELECT 80, 'Slight rain showers'
UNION ALL SELECT 81, 'Moderate rain showers'
UNION ALL SELECT 82, 'Violent rain showers'
UNION ALL SELECT 95, 'Thunderstorm'
UNION ALL SELECT 96, 'Thunderstorm with slight hail'
UNION ALL SELECT 99, 'Thunderstorm with heavy hail';

CREATE TABLE IF NOT EXISTS `mci506-weather-risk.silver.daily_weather_clean` (
    city_id STRING NOT NULL,
    city_name STRING NOT NULL,
    date DATE NOT NULL,
    temperature_2m_max FLOAT64,
    temperature_2m_min FLOAT64,
    temperature_2m_mean FLOAT64,
    precipitation_sum FLOAT64,
    windspeed_10m_max FLOAT64,
    weathercode INT64,
    et0_fao_evapotranspiration FLOAT64,
    year INT64,
    month INT64,
    season STRING,
    extraction_timestamp_utc TIMESTAMP,
    loaded_at_utc TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `mci506-weather-risk.silver.quarantine_log` (
    city_id STRING,
    city_name STRING,
    date DATE,
    quality_issue STRING,
    payload_source STRING,
    extraction_timestamp_utc TIMESTAMP,
    rejected_at_utc TIMESTAMP
);

CREATE TEMP TABLE parsed_daily_weather AS
WITH expanded_raw AS (
    SELECT
        CASE LOWER(JSON_VALUE(payload, '$.meta.city_name'))
            WHEN 'santa cruz de la sierra' THEN 'santa_cruz'
            WHEN 'la paz' THEN 'la_paz'
            WHEN 'cochabamba' THEN 'cochabamba'
            WHEN 'sucre' THEN 'sucre'
            WHEN 'oruro' THEN 'oruro'
            WHEN 'tarija' THEN 'tarija'
            ELSE LOWER(REPLACE(JSON_VALUE(payload, '$.meta.city_name'), ' ', '_'))
        END AS city_id,
        JSON_VALUE(payload, '$.meta.city_name') AS city_name,
        SAFE_CAST(JSON_VALUE(day_value) AS DATE) AS date,
        SAFE_CAST(JSON_VALUE_ARRAY(payload, '$.data.daily.temperature_2m_max')[SAFE_OFFSET(idx)] AS FLOAT64) AS temperature_2m_max,
        SAFE_CAST(JSON_VALUE_ARRAY(payload, '$.data.daily.temperature_2m_min')[SAFE_OFFSET(idx)] AS FLOAT64) AS temperature_2m_min,
        SAFE_CAST(JSON_VALUE_ARRAY(payload, '$.data.daily.temperature_2m_mean')[SAFE_OFFSET(idx)] AS FLOAT64) AS temperature_2m_mean,
        SAFE_CAST(JSON_VALUE_ARRAY(payload, '$.data.daily.precipitation_sum')[SAFE_OFFSET(idx)] AS FLOAT64) AS precipitation_sum,
        SAFE_CAST(JSON_VALUE_ARRAY(payload, '$.data.daily.windspeed_10m_max')[SAFE_OFFSET(idx)] AS FLOAT64) AS windspeed_10m_max,
        SAFE_CAST(JSON_VALUE_ARRAY(payload, '$.data.daily.weathercode')[SAFE_OFFSET(idx)] AS INT64) AS weathercode,
        SAFE_CAST(JSON_VALUE_ARRAY(payload, '$.data.daily.et0_fao_evapotranspiration')[SAFE_OFFSET(idx)] AS FLOAT64) AS et0_fao_evapotranspiration,
        extraction_timestamp_utc,
        '$.data.daily' AS payload_source
    FROM `mci506-weather-risk.silver.raw_weather_json` AS raw
    CROSS JOIN UNNEST(JSON_QUERY_ARRAY(payload, '$.data.daily.time')) AS day_value WITH OFFSET AS idx
),
typed_rows AS (
    SELECT
        city_id,
        city_name,
        date,
        temperature_2m_max,
        temperature_2m_min,
        temperature_2m_mean,
        precipitation_sum,
        windspeed_10m_max,
        weathercode,
        et0_fao_evapotranspiration,
        EXTRACT(YEAR FROM date) AS year,
        EXTRACT(MONTH FROM date) AS month,
        CASE
            WHEN EXTRACT(MONTH FROM date) IN (12, 1, 2) THEN 'Summer'
            WHEN EXTRACT(MONTH FROM date) IN (3, 4, 5) THEN 'Autumn'
            WHEN EXTRACT(MONTH FROM date) IN (6, 7, 8) THEN 'Winter'
            WHEN EXTRACT(MONTH FROM date) IN (9, 10, 11) THEN 'Spring'
            ELSE 'Unknown'
        END AS season,
        extraction_timestamp_utc,
        payload_source
    FROM expanded_raw
)
SELECT *
FROM typed_rows;

INSERT INTO `mci506-weather-risk.silver.daily_weather_clean` (
    city_id,
    city_name,
    date,
    temperature_2m_max,
    temperature_2m_min,
    temperature_2m_mean,
    precipitation_sum,
    windspeed_10m_max,
    weathercode,
    et0_fao_evapotranspiration,
    year,
    month,
    season,
    extraction_timestamp_utc,
    loaded_at_utc
)
SELECT
    p.city_id,
    p.city_name,
    p.date,
    p.temperature_2m_max,
    p.temperature_2m_min,
    p.temperature_2m_mean,
    p.precipitation_sum,
    p.windspeed_10m_max,
    p.weathercode,
    p.et0_fao_evapotranspiration,
    p.year,
    p.month,
    p.season,
    p.extraction_timestamp_utc,
    CURRENT_TIMESTAMP() AS loaded_at_utc
FROM parsed_daily_weather AS p
WHERE p.city_id IS NOT NULL
  AND p.date IS NOT NULL
  AND p.temperature_2m_max IS NOT NULL
  AND p.temperature_2m_min IS NOT NULL
  AND p.precipitation_sum IS NOT NULL
  AND p.temperature_2m_max >= p.temperature_2m_min
  AND p.precipitation_sum >= 0
  AND COALESCE(p.windspeed_10m_max, 0) >= 0
  AND NOT EXISTS (
      SELECT 1
      FROM `mci506-weather-risk.silver.daily_weather_clean` AS existing
      WHERE existing.city_id = p.city_id
        AND existing.date = p.date
  );

INSERT INTO `mci506-weather-risk.silver.quarantine_log` (
    city_id,
    city_name,
    date,
    quality_issue,
    payload_source,
    extraction_timestamp_utc,
    rejected_at_utc
)
SELECT
    p.city_id,
    p.city_name,
    p.date,
    ARRAY_TO_STRING(
        ARRAY_CONCAT(
            IF(p.city_id IS NULL, ['CITY_ID_NULL'], CAST([] AS ARRAY<STRING>)),
            IF(p.date IS NULL, ['DATE_NULL'], CAST([] AS ARRAY<STRING>)),
            IF(p.temperature_2m_max IS NULL, ['TEMP_MAX_NULL'], CAST([] AS ARRAY<STRING>)),
            IF(p.temperature_2m_min IS NULL, ['TEMP_MIN_NULL'], CAST([] AS ARRAY<STRING>)),
            IF(p.precipitation_sum IS NULL, ['PRECIPITATION_NULL'], CAST([] AS ARRAY<STRING>)),
            IF(p.temperature_2m_max < p.temperature_2m_min, ['TEMP_MAX_LT_TEMP_MIN'], CAST([] AS ARRAY<STRING>)),
            IF(p.precipitation_sum < 0, ['PRECIPITATION_NEGATIVE'], CAST([] AS ARRAY<STRING>)),
            IF(p.windspeed_10m_max < 0, ['WINDSPEED_NEGATIVE'], CAST([] AS ARRAY<STRING>))
        ),
        '|'
    ) AS quality_issue,
    p.payload_source,
    p.extraction_timestamp_utc,
    CURRENT_TIMESTAMP() AS rejected_at_utc
FROM parsed_daily_weather AS p
WHERE p.city_id IS NULL
   OR p.date IS NULL
   OR p.temperature_2m_max IS NULL
   OR p.temperature_2m_min IS NULL
   OR p.precipitation_sum IS NULL
   OR p.temperature_2m_max < p.temperature_2m_min
   OR p.precipitation_sum < 0
   OR p.windspeed_10m_max < 0;