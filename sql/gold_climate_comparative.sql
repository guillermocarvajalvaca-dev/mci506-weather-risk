-- SP-012 - Gold 2: Climate comparative by month
-- Project: MCI506 Weather Risk Intelligence Pipeline
-- Owner: Monserrat Barba / Monse
-- BigQuery Standard SQL
--
-- Purpose:
-- Build a business-ready monthly climate comparison table by city.
-- The output is calendar-complete: 6 cities x 12 months.
-- Months without available observations keep weather metrics as NULL
-- and are explicitly marked as NO_OBSERVATIONS.
--
-- Source layer:
--   silver.daily_weather_clean
--   silver.cities_dim
--
-- Target layer:
--   gold.climate_comparative_by_month
--
-- Quality expectations:
--   - One row per city and month number.
--   - avg_temp_max >= avg_temp_min for observed months.
--   - climate_variability_index >= 0 for observed months.
--   - No synthetic weather values are imputed.

CREATE OR REPLACE TABLE `mci506-weather-risk.gold.climate_comparative_by_month` AS
WITH month_calendar AS (
    SELECT
        month_number,
        CASE month_number
            WHEN 1 THEN 'Enero'
            WHEN 2 THEN 'Febrero'
            WHEN 3 THEN 'Marzo'
            WHEN 4 THEN 'Abril'
            WHEN 5 THEN 'Mayo'
            WHEN 6 THEN 'Junio'
            WHEN 7 THEN 'Julio'
            WHEN 8 THEN 'Agosto'
            WHEN 9 THEN 'Septiembre'
            WHEN 10 THEN 'Octubre'
            WHEN 11 THEN 'Noviembre'
            WHEN 12 THEN 'Diciembre'
        END AS month_name,
        CASE
            WHEN month_number IN (12, 1, 2) THEN 'Verano'
            WHEN month_number IN (3, 4, 5) THEN 'Otono'
            WHEN month_number IN (6, 7, 8) THEN 'Invierno'
            WHEN month_number IN (9, 10, 11) THEN 'Primavera'
        END AS season
    FROM UNNEST(GENERATE_ARRAY(1, 12)) AS month_number
),

cities AS (
    SELECT
        city_id,
        city_name
    FROM `mci506-weather-risk.silver.cities_dim`
),

valid_daily_weather AS (
    SELECT
        city_id,
        date,
        EXTRACT(MONTH FROM date) AS month_number,
        CAST(temperature_2m_max AS FLOAT64) AS temperature_2m_max,
        CAST(temperature_2m_min AS FLOAT64) AS temperature_2m_min,
        CAST(precipitation_sum AS FLOAT64) AS precipitation_sum,
        CAST(windspeed_10m_max AS FLOAT64) AS windspeed_10m_max
    FROM `mci506-weather-risk.silver.daily_weather_clean`
    WHERE city_id IS NOT NULL
      AND date IS NOT NULL
      AND temperature_2m_max IS NOT NULL
      AND temperature_2m_min IS NOT NULL
      AND precipitation_sum IS NOT NULL
      AND windspeed_10m_max IS NOT NULL
      AND temperature_2m_max >= temperature_2m_min
      AND precipitation_sum >= 0
      AND windspeed_10m_max >= 0
),

monthly_aggregation AS (
    SELECT
        c.city_id,
        c.city_name,
        mc.month_number,
        mc.month_name,
        mc.season,
        COUNT(vdw.date) AS observed_days,
        ROUND(AVG(vdw.temperature_2m_max), 2) AS avg_temp_max,
        ROUND(AVG(vdw.temperature_2m_min), 2) AS avg_temp_min,
        ROUND(AVG(vdw.precipitation_sum), 2) AS avg_precipitation,
        ROUND(AVG(vdw.windspeed_10m_max), 2) AS avg_windspeed,
        ROUND(
            STDDEV_POP(
                (vdw.temperature_2m_max + vdw.temperature_2m_min) / 2
            ),
            2
        ) AS climate_variability_index
    FROM cities AS c
    CROSS JOIN month_calendar AS mc
    LEFT JOIN valid_daily_weather AS vdw
        ON c.city_id = vdw.city_id
       AND mc.month_number = vdw.month_number
    GROUP BY
        c.city_id,
        c.city_name,
        mc.month_number,
        mc.month_name,
        mc.season
)

SELECT
    city_id,
    city_name,
    month_number,
    month_name,
    season,
    avg_temp_max,
    avg_temp_min,
    avg_precipitation,
    avg_windspeed,
    climate_variability_index,
    observed_days,
    CASE
        WHEN observed_days = 0 THEN 'NO_OBSERVATIONS'
        WHEN observed_days < 15 THEN 'PARTIAL_MONTH'
        ELSE 'OBSERVED'
    END AS data_completeness_status,
    CURRENT_TIMESTAMP() AS generated_at
FROM monthly_aggregation;
