-- SP-011 / Gold 01
-- Artifact: sql/gold_daily_risk_index.sql
-- Responsible: Monserrat Barba / Monse
-- Purpose:
--   Build the first Gold business-ready analytical table for the MCI506
--   Weather Risk Intelligence pipeline.
--
-- Business question:
--   What is the daily weather risk index by Bolivian city?
--
-- Source layer:
--   BigQuery Silver tables:
--   `mci506-weather-risk.silver.daily_weather_clean`
--   `mci506-weather-risk.silver.cities_dim`
--
-- Target layer:
--   BigQuery Gold table:
--   `mci506-weather-risk.gold.daily_risk_index_by_city`
--
-- Risk model:
--   composite_risk_score =
--       temp_risk_score   * 0.40
--     + precip_risk_score * 0.35
--     + wind_risk_score   * 0.25
--
-- Risk levels:
--   0-25   = LOW
--   26-50  = MODERATE
--   51-75  = HIGH
--   76-100 = CRITICAL
--
-- Operational note:
--   This SQL file is implementation-only. It must be reviewed by Guillermo
--   before pull request integration and must not be executed directly from this branch.

CREATE SCHEMA IF NOT EXISTS `mci506-weather-risk.gold`;

CREATE OR REPLACE TABLE `mci506-weather-risk.gold.daily_risk_index_by_city` AS
WITH base_weather AS (
    SELECT
        dwc.city_id,
        cd.city_name,
        dwc.date,
        dwc.temperature_2m_max,
        dwc.temperature_2m_min,
        COALESCE(
            dwc.temperature_2m_mean,
            (dwc.temperature_2m_max + dwc.temperature_2m_min) / 2.0
        ) AS temperature_reference_c,
        dwc.precipitation_sum,
        dwc.windspeed_10m_max
    FROM `mci506-weather-risk.silver.daily_weather_clean` AS dwc
    INNER JOIN `mci506-weather-risk.silver.cities_dim` AS cd
        ON dwc.city_id = cd.city_id
),

city_temperature_baseline AS (
    SELECT
        city_id,
        city_name,
        date,
        temperature_2m_max,
        temperature_2m_min,
        temperature_reference_c,
        precipitation_sum,
        windspeed_10m_max,
        AVG(temperature_reference_c) OVER (
            PARTITION BY city_id
        ) AS city_avg_temperature_reference_c,
        STDDEV_POP(temperature_reference_c) OVER (
            PARTITION BY city_id
        ) AS city_std_temperature_reference_c
    FROM base_weather
),

component_scores AS (
    SELECT
        city_id,
        city_name,
        date,

        ROUND(
            LEAST(
                100.0,
                GREATEST(
                    0.0,
                    CASE
                        WHEN city_std_temperature_reference_c IS NULL
                             OR city_std_temperature_reference_c = 0
                        THEN
                            CASE
                                WHEN temperature_2m_max >= 37
                                     OR temperature_2m_min <= 2
                                THEN 100.0
                                WHEN temperature_2m_max >= 34
                                     OR temperature_2m_min <= 5
                                THEN 75.0
                                WHEN temperature_2m_max >= 30
                                     OR temperature_2m_min <= 8
                                THEN 50.0
                                ELSE 10.0
                            END
                        ELSE
                            ABS(
                                temperature_reference_c
                                - city_avg_temperature_reference_c
                            )
                            / city_std_temperature_reference_c
                            * 25.0
                    END
                )
            ),
            2
        ) AS temp_risk_score,

        ROUND(
            LEAST(
                100.0,
                GREATEST(
                    0.0,
                    precipitation_sum / 50.0 * 100.0
                )
            ),
            2
        ) AS precip_risk_score,

        ROUND(
            LEAST(
                100.0,
                GREATEST(
                    0.0,
                    windspeed_10m_max / 60.0 * 100.0
                )
            ),
            2
        ) AS wind_risk_score
    FROM city_temperature_baseline
),

composite_scores AS (
    SELECT
        city_id,
        city_name,
        date,
        temp_risk_score,
        precip_risk_score,
        wind_risk_score,
        ROUND(
              temp_risk_score * 0.40
            + precip_risk_score * 0.35
            + wind_risk_score * 0.25,
            2
        ) AS composite_risk_score
    FROM component_scores
)

SELECT
    city_id,
    city_name,
    date,
    temp_risk_score,
    precip_risk_score,
    wind_risk_score,
    composite_risk_score,
    CASE
        WHEN composite_risk_score <= 25 THEN 'LOW'
        WHEN composite_risk_score <= 50 THEN 'MODERATE'
        WHEN composite_risk_score <= 75 THEN 'HIGH'
        ELSE 'CRITICAL'
    END AS risk_level
FROM composite_scores;
