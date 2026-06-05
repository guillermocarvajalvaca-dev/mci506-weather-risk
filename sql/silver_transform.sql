-- ============================================================
-- MODULE:  silver_transform.sql
-- PURPOSE: Limpia y estructura datos crudos de Open-Meteo
--          Bronze (GCS) -> Silver (BigQuery)
-- AUTHOR:  Montserrat Barba
-- VERSION: 1.0
-- ============================================================

-- ---------------------------------------------------------
-- TABLA 1: silver.daily_weather_clean
-- ---------------------------------------------------------
CREATE OR REPLACE TABLE `silver.daily_weather_clean` AS

WITH raw_data AS (
  SELECT
    JSON_VALUE(data, '$.meta.city_id')                AS city_id,
    CAST(daily.date AS DATE)                          AS date,
    CAST(daily.temperature_2m_max AS FLOAT64)         AS temperature_2m_max,
    CAST(daily.temperature_2m_min AS FLOAT64)         AS temperature_2m_min,
    CAST(daily.temperature_2m_mean AS FLOAT64)        AS temperature_2m_mean,
    CAST(daily.precipitation_sum AS FLOAT64)          AS precipitation_sum,
    CAST(daily.windspeed_10m_max AS FLOAT64)          AS windspeed_10m_max,
    CAST(daily.weathercode AS INT64)                  AS weathercode,
    CAST(daily.et0_fao_evapotranspiration AS FLOAT64) AS et0_fao_evapotranspiration,
    ROW_NUMBER() OVER (
      PARTITION BY JSON_VALUE(data, '$.meta.city_id'), daily.date
      ORDER BY JSON_VALUE(data, '$.meta.extracted_at') DESC
    ) AS row_num
  FROM `bronze.raw_weather`,
    UNNEST(JSON_QUERY_ARRAY(data, '$.data.daily')) AS daily
),

validated AS (
  SELECT * FROM raw_data
  WHERE
    row_num = 1
    AND city_id IS NOT NULL
    AND date IS NOT NULL
    AND temperature_2m_max IS NOT NULL
    AND precipitation_sum IS NOT NULL
    AND temperature_2m_max >= temperature_2m_min
    AND precipitation_sum >= 0
)

SELECT
  city_id, date,
  temperature_2m_max, temperature_2m_min, temperature_2m_mean,
  precipitation_sum, windspeed_10m_max, weathercode,
  et0_fao_evapotranspiration
FROM validated;


-- ---------------------------------------------------------
-- TABLA 2: silver.quarantine_log
-- Registros rechazados con motivo documentado
-- ---------------------------------------------------------
CREATE OR REPLACE TABLE `silver.quarantine_log` AS

SELECT
  JSON_VALUE(data, '$.meta.city_id')           AS city_id,
  CAST(daily.date AS DATE)                      AS date,
  CAST(daily.temperature_2m_max AS FLOAT64)     AS temperature_2m_max,
  CAST(daily.temperature_2m_min AS FLOAT64)     AS temperature_2m_min,
  CAST(daily.precipitation_sum AS FLOAT64)      AS precipitation_sum,
  CASE
    WHEN JSON_VALUE(data, '$.meta.city_id') IS NULL            THEN 'city_id nulo'
    WHEN daily.date IS NULL                                    THEN 'date nulo'
    WHEN CAST(daily.temperature_2m_max AS FLOAT64) IS NULL     THEN 'temperature_max nulo'
    WHEN CAST(daily.precipitation_sum AS FLOAT64) IS NULL      THEN 'precipitation nulo'
    WHEN CAST(daily.temperature_2m_max AS FLOAT64)
       < CAST(daily.temperature_2m_min AS FLOAT64)             THEN 'temp_max < temp_min'
    WHEN CAST(daily.precipitation_sum AS FLOAT64) < 0          THEN 'precipitacion negativa'
    ELSE 'otro'
  END AS rejection_reason,
  CURRENT_TIMESTAMP() AS quarantined_at
FROM `bronze.raw_weather`,
  UNNEST(JSON_QUERY_ARRAY(data, '$.data.daily')) AS daily
WHERE
  JSON_VALUE(data, '$.meta.city_id') IS NULL
  OR daily.date IS NULL
  OR CAST(daily.temperature_2m_max AS FLOAT64) IS NULL
  OR CAST(daily.precipitation_sum AS FLOAT64) IS NULL
  OR CAST(daily.temperature_2m_max AS FLOAT64) < CAST(daily.temperature_2m_min AS FLOAT64)
  OR CAST(daily.precipitation_sum AS FLOAT64) < 0;


-- ---------------------------------------------------------
-- TABLA 3: silver.cities_dim
-- Dimension estatica de ciudades bolivianas
-- ---------------------------------------------------------
CREATE OR REPLACE TABLE `silver.cities_dim` AS

SELECT * FROM UNNEST([
  STRUCT('santa_cruz' AS city_id, 'Santa Cruz de la Sierra' AS city_name,
         -17.7833 AS latitude, -63.1833 AS longitude, 416 AS elevation_m, 'Santa Cruz' AS department),
  STRUCT('la_paz',     'La Paz',        -16.5000, -68.1500, 3640, 'La Paz'),
  STRUCT('cochabamba', 'Cochabamba',    -17.3895, -66.1568, 2558, 'Cochabamba'),
  STRUCT('sucre',      'Sucre',         -19.0431, -65.2591, 2810, 'Chuquisaca'),
  STRUCT('oruro',      'Oruro',         -17.9833, -67.1500, 3706, 'Oruro'),
  STRUCT('tarija',     'Tarija',        -21.5353, -64.7298, 1866, 'Tarija')
]);
