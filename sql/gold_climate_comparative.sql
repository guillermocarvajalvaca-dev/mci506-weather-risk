-- ============================================================
-- MODULE:  gold_climate_comparative.sql
-- PURPOSE: Comparativo climatico historico entre ciudades
--          por mes y estacion - Silver -> Gold
-- AUTHOR:  Montserrat Barba
-- VERSION: 1.0
-- ============================================================

CREATE OR REPLACE TABLE `gold.climate_comparative_by_month` AS

WITH monthly_stats AS (
  SELECT
    w.city_id,
    c.city_name,
    c.department,
    c.elevation_m,
    EXTRACT(MONTH FROM w.date)        AS month_number,
    FORMAT_DATE('%B', w.date)         AS month_name,

    -- Temperaturas promedio
    ROUND(AVG(w.temperature_2m_max), 2)  AS avg_temp_max,
    ROUND(AVG(w.temperature_2m_min), 2)  AS avg_temp_min,
    ROUND(AVG(w.temperature_2m_mean), 2) AS avg_temp_mean,

    -- Precipitacion promedio
    ROUND(AVG(w.precipitation_sum), 2)   AS avg_precipitation,
    ROUND(MAX(w.precipitation_sum), 2)   AS max_precipitation,

    -- Viento promedio
    ROUND(AVG(w.windspeed_10m_max), 2)   AS avg_windspeed,
    ROUND(MAX(w.windspeed_10m_max), 2)   AS max_windspeed,

    -- Variabilidad climatica (desviacion estandar)
    ROUND(STDDEV(w.temperature_2m_mean), 2) AS climate_variability_index,

    -- Conteo de registros
    COUNT(*) AS record_count

  FROM `silver.daily_weather_clean` w
  LEFT JOIN `silver.cities_dim` c ON w.city_id = c.city_id
  GROUP BY
    w.city_id, c.city_name, c.department, c.elevation_m,
    month_number, month_name
),

with_season AS (
  SELECT
    *,
    -- Estaciones para Bolivia (hemisferio sur)
    CASE
      WHEN month_number IN (12, 1, 2)  THEN 'VERANO'
      WHEN month_number IN (3, 4, 5)   THEN 'OTONO'
      WHEN month_number IN (6, 7, 8)   THEN 'INVIERNO'
      WHEN month_number IN (9, 10, 11) THEN 'PRIMAVERA'
    END AS season
  FROM monthly_stats
)

SELECT
  city_id,
  city_name,
  department,
  elevation_m,
  month_number,
  month_name,
  season,
  avg_temp_max,
  avg_temp_min,
  avg_temp_mean,
  avg_precipitation,
  max_precipitation,
  avg_windspeed,
  max_windspeed,
  climate_variability_index,
  record_count
FROM with_season
ORDER BY city_id, month_number;
