# Bolivia Weather Risk Intelligence Pipeline

![Python](https://img.shields.io/badge/Python-3.x-blue)
![Google Cloud](https://img.shields.io/badge/Google%20Cloud-BigQuery%20%7C%20GCS%20%7C%20Data%20Transfer-blue)
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-Orchestration-blue)
![Looker Studio](https://img.shields.io/badge/Looker%20Studio-Dashboard-blue)
![Status](https://img.shields.io/badge/Delivery%20Readiness-Passed-brightgreen)

## 1. Project Overview

Bolivia Weather Risk Intelligence Pipeline is a cloud-based data engineering project developed for the MCI506 course. The solution extracts daily weather data for selected Bolivian cities, stores raw data in Google Cloud Storage, transforms the data through BigQuery Silver and Gold layers, automates refresh operations, and exposes business-ready insights through a Looker Studio dashboard.

The project focuses on weather-risk intelligence for Bolivia, including daily composite risk scoring, monthly climate comparison, and detection of extreme weather events.

## 2. Final Dashboard

The final Looker Studio dashboard is available at:

https://datastudio.google.com/reporting/c8183766-99d4-49be-8563-b696bcc6fb69/page/p_v77wvd1d4d

Dashboard pages:

- Overview: executive summary of weather risk indicators.
- Riesgo Diario: daily risk by city, risk distribution, and temporal evolution.
- Comparativo Climatico: monthly climate comparison by city.
- Eventos Extremos: catalog and distribution of extreme weather events.

## 3. Business Questions

The pipeline supports the following analytical questions:

1. Which Bolivian cities show the highest daily composite weather risk?
2. How do risk patterns evolve over time across cities?
3. How do temperature, precipitation, and wind indicators compare by month and city?
4. Which extreme weather events are detected, where do they occur, and how severe are they?
5. How can automated cloud workflows keep the analytical layer updated for reporting?

## 4. Architecture

The project follows a cloud data engineering architecture aligned with a Bronze, Silver, and Gold analytical model.

<pre>
Open-Meteo API
     |
     v
Python extraction scripts
     |
     v
Google Cloud Storage / Bronze raw storage
     |
     v
BigQuery Silver layer
     |
     v
BigQuery Gold analytical tables
     |
     v
Looker Studio dashboard
</pre>

### Bronze Layer

The Bronze layer stores raw weather payloads extracted from the Open-Meteo API. This layer preserves source-level data for traceability and reproducibility.

### Silver Layer

The Silver layer standardizes and validates weather observations. It creates typed, deduplicated, and quality-controlled tables used by downstream analytics.

Main Silver artifacts:

- silver.raw_weather_json
- silver.cities_dim
- silver.weathercode_dim
- silver.daily_weather_clean
- silver.quarantine_log

### Gold Layer

The Gold layer contains business-ready analytical tables optimized for dashboard consumption.

Main Gold tables:

- gold.daily_risk_index_by_city
- gold.climate_comparative_by_month
- gold.extreme_events_catalog

## 5. Google Cloud Resources

Primary Google Cloud project:

<pre>
mci506-weather-risk
</pre>

Primary BigQuery datasets:

<pre>
silver
gold
</pre>

Native BigQuery Scheduled Query:

<pre>
Display name: MCI506 Silver to Gold Daily Automation
Data source: scheduled_query
State: SUCCEEDED
Location: US
Resource: projects/376530260467/locations/us/transferConfigs/6a4689e5-0000-2e10-a91f-2405887abda0
</pre>

The Scheduled Query automates the Silver-to-Gold refresh path using the validated SQL candidate generated during the final delivery readiness process.

## 6. Automation

The project includes two automation mechanisms.

### GitHub Actions Workflow

Workflow file:

<pre>
.github/workflows/pipeline.yml
</pre>

The workflow includes:

- workflow_dispatch for manual controlled execution.
- schedule / cron for scheduled orchestration.
- Google Cloud authentication through the repository secret GCP_SA_KEY.
- Python extraction and load scripts.
- BigQuery SQL execution for Silver and Gold transformations.

### Native BigQuery Scheduled Query

The native Scheduled Query was created from the validated Silver-to-Gold SQL candidate and confirmed through BigQuery transfer configuration evidence.

This satisfies the cloud-native Scheduled Query requirement for the Silver-to-Gold analytical refresh process.

## 7. Repository Structure

<pre>
.github/
  workflows/
    pipeline.yml

scripts/
  extract.py
  load.py
  utils.py

sql/
  silver_transform.sql
  gold_daily_risk_index.sql
  gold_climate_comparative.sql
  gold_extreme_events.sql

outputs/
  quality_gates/
    github_actions_post_merge_develop_validation_report.md
    scheduled_query_silver_gold_candidate_validation_report.md
    scheduled_query_silver_gold_final_validation_r2_report.md
    final_delivery_readiness_audit_report.md
    final_documentation_gap_audit_report.md

requirements.txt
.env.example
README.md
</pre>

## 8. Core Pipeline Components

### Python Scripts

- scripts/extract.py: extracts weather data from the Open-Meteo API.
- scripts/load.py: loads or stages weather data for cloud processing.
- scripts/utils.py: contains shared utility logic used by the pipeline.

### SQL Transformations

- sql/silver_transform.sql: builds the Silver analytical layer from raw weather JSON.
- sql/gold_daily_risk_index.sql: builds the daily city-level composite risk index.
- sql/gold_climate_comparative.sql: builds monthly comparative climate metrics.
- sql/gold_extreme_events.sql: builds the extreme weather event catalog.

## 9. Risk Model

The daily risk model combines temperature, precipitation, and wind components.

<pre>
composite_risk_score =
    temp_risk_score   * 0.40
  + precip_risk_score * 0.35
  + wind_risk_score   * 0.25
</pre>

Risk levels:

<pre>
0-25    LOW
26-50   MODERATE
51-75   HIGH
76-100  CRITICAL
</pre>

## 10. Data Quality Controls

The Silver layer applies basic data quality controls before records are accepted into analytical tables.

Controls include:

- Required city and date fields.
- Required temperature and precipitation fields.
- Temperature maximum greater than or equal to temperature minimum.
- Non-negative precipitation.
- Non-negative wind speed.
- Quarantine logging for rejected records.

## 11. Final Validation Evidence

The following quality gates were executed and validated during final delivery readiness:

- GitHub Actions workflow creation and merge into develop.
- GitHub Secret GCP_SA_KEY validation by name.
- Service account key hygiene validation.
- Native BigQuery Scheduled Query creation through Google Cloud Console UI.
- Native Scheduled Query validation through bq transfer_config evidence.
- BigQuery Silver and Gold dataset validation.
- Gold table existence validation.
- Looker Studio dashboard URL validation.
- Final delivery readiness audit.

Key validated reports:

<pre>
outputs/quality_gates/github_actions_post_merge_develop_validation_report.md
outputs/quality_gates/scheduled_query_silver_gold_candidate_validation_report.md
outputs/quality_gates/scheduled_query_silver_gold_final_validation_r2_report.md
outputs/quality_gates/final_delivery_readiness_audit_report.md
</pre>

## 12. Collaboration and GitHub Flow

The project follows a controlled GitHub Flow:

<pre>
feature branch -> pull request -> develop -> final validation -> release/main
</pre>

Relevant integration evidence:

- GitHub Actions workflow PR: #10
- PR state: MERGED
- Integration branch: develop
- Latest validated develop HEAD: 85c66ff

Team responsibilities:

- Guillermo Carvajal: project lead, repository governance, GCP orchestration, GitHub Actions, final validation, delivery readiness.
- Monserrat Barba / Monse: Gold analytical tables and Looker Studio dashboard development.
- Andres / AndrÃ©s: collaborative review and project contribution support.

## 13. Environment Variables

The repository includes an .env.example file for environment configuration. Sensitive values must not be committed to the repository.

Expected configuration categories include:

<pre>
GCP project configuration
Cloud Storage / bucket configuration
BigQuery dataset configuration
Service account authentication configuration
</pre>

GitHub Actions uses GCP_SA_KEY as a GitHub repository secret. The secret value is not stored in the repository.

## 14. Security and Delivery Notes

Security controls applied during delivery readiness:

- No service account JSON key was committed.
- No private key literal was found in pipeline.yml.
- GitHub Secret GCP_SA_KEY was validated by name only.
- Local key residual checks were performed during the GitHub Actions readiness process.
- Final audit confirmed no manual SQL execution, no manual transfer run, no workflow dispatch, and no unintended GCP mutation during validation gates.

## 15. How to Review the Project

A reviewer should validate the project through:

1. GitHub repository structure and pull request history.
2. .github/workflows/pipeline.yml.
3. SQL files in the sql/ directory.
4. Python scripts in the scripts/ directory.
5. BigQuery datasets silver and gold.
6. Gold tables:
   - gold.daily_risk_index_by_city
   - gold.climate_comparative_by_month
   - gold.extreme_events_catalog
7. Native BigQuery Scheduled Query:
   - MCI506 Silver to Gold Daily Automation
8. Looker Studio dashboard:
   - https://datastudio.google.com/reporting/c8183766-99d4-49be-8563-b696bcc6fb69/page/p_v77wvd1d4d

## 16. Current Delivery Status

As of the final readiness audit:

<pre>
Repository develop readiness: PASSED
GitHub Actions readiness: PASSED
GitHub Secret GCP_SA_KEY: PASSED
BigQuery Silver dataset: PASSED
BigQuery Gold dataset and tables: PASSED
Native Scheduled Query: PASSED
Looker Studio dashboard URL: PASSED
Final delivery readiness audit: PASSED
</pre>

The project is ready for final documentation validation, repository delivery checklist, and controlled release workflow.

## 17. Instructor Rubric Alignment: Seven Required README Questions

This section answers the seven required README questions from the instructor rubric in a direct review format.

### 17.1 What data is extracted?

The pipeline extracts daily weather observations for selected Bolivian cities. The core variables include date, city, maximum temperature, minimum temperature, mean temperature, precipitation, wind speed, weather code, evapotranspiration, year, month, season, extraction timestamp, and loading timestamp.

The analytical domain is weather risk intelligence for Bolivia. The final Gold layer transforms these variables into business-ready indicators for daily risk, monthly climate comparison, and extreme event monitoring.

### 17.2 From where is the data extracted?

The data is extracted from the public Open-Meteo API. The API is used as an external weather data source and does not require API keys, tokens, user registration, or paid credentials for this academic use case.

### 17.3 Where is the data stored?

The pipeline stores and processes the data across Google Cloud resources:

- Bronze layer: raw weather data in Google Cloud Storage.
- Silver layer: typed, cleaned, and deduplicated BigQuery tables.
- Gold layer: business-ready BigQuery analytical tables.

The main BigQuery datasets are:

- silver
- gold

The main Gold tables are:

- gold.daily_risk_index_by_city
- gold.climate_comparative_by_month
- gold.extreme_events_catalog

### 17.4 When does the pipeline run?

The pipeline has two automated execution mechanisms:

- GitHub Actions includes workflow_dispatch and scheduled cron orchestration.
- A native BigQuery Scheduled Query named MCI506 Silver to Gold Daily Automation refreshes the Silver-to-Gold analytical path automatically.

The native Scheduled Query is registered in BigQuery Data Transfer as a scheduled_query resource in location US and was validated with state SUCCEEDED.

### 17.5 How does the pipeline work?

The pipeline follows a Medallion-style data engineering flow:

<pre>
Open-Meteo API
  -> Python extract.py
  -> Python load.py
  -> Google Cloud Storage Bronze raw storage
  -> BigQuery external/raw structures
  -> BigQuery Silver clean typed tables
  -> BigQuery Gold analytical tables
  -> Looker Studio dashboard
</pre>

The operational flow is:

1. Python extraction retrieves weather records from Open-Meteo.
2. Loading logic stages raw weather payloads in Google Cloud Storage and BigQuery.
3. Silver SQL standardizes data types, validates records, deduplicates observations, and separates rejected records into quarantine logic.
4. Gold SQL builds analytical tables for daily risk, monthly comparison, and extreme event detection.
5. Looker Studio consumes Gold tables for dashboard visualizations.
6. GitHub Actions and BigQuery Scheduled Query provide automation evidence.

### 17.6 What is the data quality?

The Silver layer applies data quality controls before records are accepted into analytical tables. The controls include:

- Required city identifier.
- Required date.
- Required temperature and precipitation fields.
- temperature_2m_max greater than or equal to temperature_2m_min.
- precipitation_sum greater than or equal to zero.
- windspeed_10m_max greater than or equal to zero.
- quarantine logging for rejected rows.

The Gold layer applies additional analytical validity rules, including risk score ranges, valid risk levels, non-negative variability metrics, and threshold-based extreme event identification.

### 17.7 What should be done if the pipeline fails?

If the pipeline fails, the recovery process is:

1. Check the GitHub Actions run logs for extract, load, authentication, and BigQuery errors.
2. Verify that the GitHub Secret GCP_SA_KEY exists and has not expired or been removed.
3. Confirm that the service account has access to Google Cloud Storage and BigQuery.
4. Validate that the Bronze files exist in Google Cloud Storage.
5. Validate that the Silver and Gold datasets exist in BigQuery.
6. Re-run the failed step manually only after identifying the failing layer.
7. Check BigQuery job history and Scheduled Query transfer history for SQL failures.
8. Inspect Silver quarantine outputs if records were rejected by data quality checks.
9. If Looker Studio fails, verify that the three Gold tables still exist and that dashboard data sources are connected.
10. Escalate to the project lead if credentials, IAM, or cloud resource access is the root cause.

## 18. Architecture Diagram

The architecture required by the Manual is documented below.

<pre>
+------------------+
| Open-Meteo API   |
+------------------+
          |
          v
+----------------------------+
| Python extraction scripts  |
| scripts/extract.py         |
| scripts/load.py            |
| scripts/utils.py           |
+----------------------------+
          |
          v
+----------------------------+
| Google Cloud Storage       |
| Bronze raw weather data    |
+----------------------------+
          |
          v
+----------------------------+
| BigQuery Silver Layer      |
| raw_weather_json           |
| cities_dim                 |
| weathercode_dim            |
| daily_weather_clean        |
| quarantine_log             |
+----------------------------+
          |
          v
+----------------------------+
| BigQuery Gold Layer        |
| daily_risk_index_by_city   |
| climate_comparative_by_month |
| extreme_events_catalog     |
+----------------------------+
          |
          v
+----------------------------+
| Looker Studio Dashboard    |
| Overview                   |
| Riesgo Diario              |
| Comparativo Climatico      |
| Eventos Extremos           |
+----------------------------+

Automation controls:
GitHub Actions -> extract/load/SQL orchestration
BigQuery Scheduled Query -> Silver-to-Gold refresh
</pre>

## 19. Final Review Checklist Before Submission

Before final submission, the reviewer should confirm:

- GitHub repository is available to the instructor.
- GitHub user auzaluis has the required repository access.
- GCP access for luis.auza@gmail.com is configured according to the instructor requirement.
- Looker Studio dashboard is shared with the instructor.
- README.md renders correctly on GitHub.
- No service account JSON key is committed.
- No private key literal is committed.
- No local machine path is committed.
- GitHub Actions workflow exists and references GCP_SA_KEY.
- Native BigQuery Scheduled Query exists and shows successful transfer configuration evidence.
- Gold tables exist and feed the Looker Studio dashboard.
- Team collaboration is visible through commits, pull requests, or review evidence.