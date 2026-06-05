-- ============================================================
-- MODULE:  gold_daily_risk_index.sql
-- PURPOSE: Score de riesgo climatico diario por ciudad (0-100)
--          Silver -> Gold
-- AUTHOR:  Montserrat Barba
-- VERSION: 1.0
-- ============================================================

CREATE OR REPLACE TABLE `gold.daily_risk_index_by_city` AS

WITH risk_components AS (
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

    -- Componente de riesgo por temperatura (40%)
    CASE
      WHEN w.temperature_2m_max > 37 THEN 100
      WHEN w.temperature_2m_max > 33 THEN 70
      WHEN w.temperature_2m_min < 2  THEN 80
      WHEN w.temperature_2m_min < 5  THEN 50
      ELSE 20
    END AS temp_risk,

    -- Componente de riesgo por precipitacion (35%)
    CASE
      WHEN w.precipitation_sum > 50 THEN 100
      WHEN w.precipitation_sum > 20 THEN 60
      WHEN w.precipitation_sum > 10 THEN 35
      ELSE 10
    END AS precip_risk,

    -- Componente de riesgo por viento (25%)
    CASE
      WHEN w.windspeed_10m_max > 60 THEN 100
      WHEN w.windspeed_10m_max > 40 THEN 60
      WHEN w.windspeed_10m_max > 25 THEN 35
      ELSE 10
    END AS wind_risk

  FROM `silver.daily_weather_clean` w
  LEFT JOIN `silver.cities_dim` c ON w.city_id = c.city_id
),

scored AS (
  SELECT
    *,
    ROUND(
      temp_risk * 0.40 +
      precip_risk * 0.35 +
      wind_risk * 0.25,
    2) AS composite_risk_score
  FROM risk_components
)

SELECT
  city_id,
  city_name,
  department,
  elevation_m,
  date,
  temperature_2m_max,
  temperature_2m_min,
  precipitation_sum,
  windspeed_10m_max,
  weathercode,
  temp_risk,
  precip_risk,
  wind_risk,
  composite_risk_score,

  -- Nivel de riesgo legible
  CASE
    WHEN composite_risk_score <= 25 THEN 'LOW'
    WHEN composite_risk_score <= 50 THEN 'MODERATE'
    WHEN composite_risk_score <= 75 THEN 'HIGH'
    ELSE 'CRITICAL'
  END AS risk_level

FROM scored
ORDER BY date DESC, composite_risk_score DESC;
