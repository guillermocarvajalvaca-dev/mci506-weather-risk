-- SP-013 - Gold 3: Extreme weather events catalog
-- Project: MCI506 Weather Risk Intelligence Pipeline
-- Owner: Monserrat Barba / Monse
-- BigQuery Standard SQL
-- Target: gold.extreme_events_catalog
-- Source: silver.daily_weather_clean

CREATE OR REPLACE TABLE `mci506-weather-risk.gold.extreme_events_catalog` AS
WITH valid_daily_weather AS (
    SELECT
        city_id,
        city_name,
        date,
        EXTRACT(YEAR FROM date) AS year,
        EXTRACT(MONTH FROM date) AS month,
        CAST(temperature_2m_max AS FLOAT64) AS temperature_2m_max,
        CAST(temperature_2m_min AS FLOAT64) AS temperature_2m_min,
        CAST(precipitation_sum AS FLOAT64) AS precipitation_sum,
        CAST(windspeed_10m_max AS FLOAT64) AS windspeed_10m_max,
        CAST(weathercode AS INT64) AS weathercode
    FROM `mci506-weather-risk.silver.daily_weather_clean`
    WHERE city_id IS NOT NULL
      AND city_name IS NOT NULL
      AND date IS NOT NULL
      AND temperature_2m_max IS NOT NULL
      AND temperature_2m_min IS NOT NULL
      AND precipitation_sum IS NOT NULL
      AND windspeed_10m_max IS NOT NULL
      AND weathercode IS NOT NULL
      AND temperature_2m_max >= temperature_2m_min
      AND precipitation_sum >= 0
      AND windspeed_10m_max >= 0
),

events AS (
    SELECT
        city_id, city_name, date,
        'HEAT_WAVE' AS event_type,
        CASE
            WHEN temperature_2m_max >= 42 THEN 'EXTREME'
            WHEN temperature_2m_max >= 40 THEN 'SEVERE'
            ELSE 'MODERATE'
        END AS event_severity,
        temperature_2m_max AS observed_value,
        37.0 AS threshold_value,
        ROUND(SAFE_DIVIDE(temperature_2m_max - 37.0, 37.0) * 100, 2) AS exceedance_pct,
        year, month
    FROM valid_daily_weather
    WHERE temperature_2m_max > 37

    UNION ALL

    SELECT
        city_id, city_name, date,
        'FROST' AS event_type,
        CASE
            WHEN temperature_2m_min <= -5 THEN 'EXTREME'
            WHEN temperature_2m_min <= 0 THEN 'SEVERE'
            ELSE 'MODERATE'
        END AS event_severity,
        temperature_2m_min AS observed_value,
        2.0 AS threshold_value,
        ROUND(SAFE_DIVIDE(2.0 - temperature_2m_min, 2.0) * 100, 2) AS exceedance_pct,
        year, month
    FROM valid_daily_weather
    WHERE temperature_2m_min < 2

    UNION ALL

    SELECT
        city_id, city_name, date,
        'HEAVY_RAIN' AS event_type,
        CASE
            WHEN precipitation_sum >= 100 THEN 'EXTREME'
            WHEN precipitation_sum >= 75 THEN 'SEVERE'
            ELSE 'MODERATE'
        END AS event_severity,
        precipitation_sum AS observed_value,
        50.0 AS threshold_value,
        ROUND(SAFE_DIVIDE(precipitation_sum - 50.0, 50.0) * 100, 2) AS exceedance_pct,
        year, month
    FROM valid_daily_weather
    WHERE precipitation_sum > 50

    UNION ALL

    SELECT
        city_id, city_name, date,
        'HIGH_WIND' AS event_type,
        CASE
            WHEN windspeed_10m_max >= 90 THEN 'EXTREME'
            WHEN windspeed_10m_max >= 75 THEN 'SEVERE'
            ELSE 'MODERATE'
        END AS event_severity,
        windspeed_10m_max AS observed_value,
        60.0 AS threshold_value,
        ROUND(SAFE_DIVIDE(windspeed_10m_max - 60.0, 60.0) * 100, 2) AS exceedance_pct,
        year, month
    FROM valid_daily_weather
    WHERE windspeed_10m_max > 60

    UNION ALL

    SELECT
        city_id, city_name, date,
        'STORM' AS event_type,
        CASE
            WHEN weathercode >= 99 THEN 'EXTREME'
            WHEN weathercode >= 96 THEN 'SEVERE'
            ELSE 'MODERATE'
        END AS event_severity,
        CAST(weathercode AS FLOAT64) AS observed_value,
        95.0 AS threshold_value,
        ROUND(SAFE_DIVIDE(CAST(weathercode AS FLOAT64) - 95.0, 95.0) * 100, 2) AS exceedance_pct,
        year, month
    FROM valid_daily_weather
    WHERE weathercode >= 95
)

SELECT
    city_id,
    city_name,
    date,
    event_type,
    event_severity,
    observed_value,
    threshold_value,
    exceedance_pct,
    year,
    month,
    CURRENT_TIMESTAMP() AS generated_at
FROM events
ORDER BY
    date,
    city_name,
    event_type;