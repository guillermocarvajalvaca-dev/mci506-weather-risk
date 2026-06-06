-- ============================================================
-- MODULE:  gold_extreme_events.sql
-- PURPOSE: Catalogo de eventos meteorologicos extremos
--          en Bolivia - Silver -> Gold
-- AUTHOR:  Montserrat Barba
-- VERSION: 1.0
-- ============================================================

CREATE OR REPLACE TABLE `gold.extreme_events_catalog` AS

WITH events AS (
  SELECT
    w.city_id,
    c.city_name,
    c.department,
    c.elevation_m,
    w.date,
    w.temperature_2m_max,
    w.temperature_2m_min,
    w.precipitation_sum,
    w.windspeed_10m_max,
    w.weathercode,

    -- Clasificacion del evento extremo
    CASE
      WHEN w.temperature_2m_max > 37  THEN 'HEAT_WAVE'
      WHEN w.temperature_2m_min < 2   THEN 'FROST'
      WHEN w.precipitation_sum > 50   THEN 'HEAVY_RAIN'
      WHEN w.windspeed_10m_max > 60   THEN 'HIGH_WIND'
      WHEN w.weathercode >= 95        THEN 'STORM'
      ELSE NULL
    END AS event_type,

    -- Valor observado segun tipo de evento
    CASE
      WHEN w.temperature_2m_max > 37  THEN w.temperature_2m_max
      WHEN w.temperature_2m_min < 2   THEN w.temperature_2m_min
      WHEN w.precipitation_sum > 50   THEN w.precipitation_sum
      WHEN w.windspeed_10m_max > 60   THEN w.windspeed_10m_max
      WHEN w.weathercode >= 95        THEN CAST(w.weathercode AS FLOAT64)
      ELSE NULL
    END AS observed_value,

    -- Umbral de referencia
    CASE
      WHEN w.temperature_2m_max > 37  THEN 37.0
      WHEN w.temperature_2m_min < 2   THEN 2.0
      WHEN w.precipitation_sum > 50   THEN 50.0
      WHEN w.windspeed_10m_max > 60   THEN 60.0
      WHEN w.weathercode >= 95        THEN 95.0
      ELSE NULL
    END AS threshold_value,

    -- Unidad de medida
    CASE
      WHEN w.temperature_2m_max > 37  THEN 'C'
      WHEN w.temperature_2m_min < 2   THEN 'C'
      WHEN w.precipitation_sum > 50   THEN 'mm'
      WHEN w.windspeed_10m_max > 60   THEN 'km/h'
      WHEN w.weathercode >= 95        THEN 'WMO_code'
      ELSE NULL
    END AS unit

  FROM `silver.daily_weather_clean` w
  LEFT JOIN `silver.cities_dim` c ON w.city_id = c.city_id
),

with_exceedance AS (
  SELECT
    *,
    -- Porcentaje de excedencia sobre el umbral
    ROUND(
      ABS(observed_value - threshold_value) / threshold_value * 100
    , 2) AS exceedance_pct
  FROM events
  WHERE event_type IS NOT NULL
),

with_severity AS (
  SELECT
    *,
    -- Severidad del evento
    CASE
      WHEN exceedance_pct < 25 THEN 'MODERATE'
      WHEN exceedance_pct < 50 THEN 'SEVERE'
      ELSE 'EXTREME'
    END AS event_severity
  FROM with_exceedance
)

SELECT
  city_id,
  city_name,
  department,
  elevation_m,
  date,
  event_type,
  event_severity,
  observed_value,
  threshold_value,
  unit,
  exceedance_pct,
  temperature_2m_max,
  temperature_2m_min,
  precipitation_sum,
  windspeed_10m_max,
  weathercode
FROM with_severity
ORDER BY date DESC, exceedance_pct DESC;
