# AgWISE Forecast To DSSAT Pipeline

This is the production path for preparing daily, bias-corrected climate
forecast data for DSSAT.

The runner is country-agnostic: provide an ISO3 country code, season start
month/year, forecast lead time, and core count. The pipeline then:

1. Builds a country configuration and folders.
2. Downloads or reuses observations, hindcasts, and forecasts.
3. Applies daily bias correction for `PRCP`, `TMAX`, `TMIN`, and `SRAD`.
4. Writes daily NetCDF files with the full forecast lead-time range.
5. Prepares DSSAT-ready RDS files for `main/DSSAT/readGeo_CM_zone.R`.

## One-Month Lead Time

The user-facing month is the season start month. The model initialization month
is derived from it.

Example:

```bash
season_start = October 2025
lead_months  = 1
forecast initialization = September 1, 2025
```

For a January 2026 season, the same rule gives a December 1, 2025 forecast
initialization.

The generated JSON keeps both concepts explicit:

```json
"forecast_year": 2025,
"season_start_month": 10,
"forecast_lead_months": 1,
"forecast_init_year": 2025,
"forecast_init_month": 9,
"forecast_init_day": 1
```

## Production Command

```bash
Rscript main/Forecast/run_forecast_to_dssat.R \
  --country KEN \
  --season-start-month 10 \
  --season-year 2025 \
  --season-length-months 3 \
  --lead-months 1 \
  --n-cores 4
```

Useful options:

```bash
--variables PRCP,TMAX,TMIN,SRAD
--force-download
--skip-dssat
--base-dir /path/to/data
--py-path /path/to/python
--manual-extent --extent north,west,south,east
```

## Production Folder Structure

```bash
data/
  countries/
    <ISO3>/
      config/
        <ISO3>_config_agwise.json
      observations/
    forecast/
      raw/
      bias_corrected/
      geo_4cropModel/
      dssat_handoff/
      logs/
      diagnostics/
      manifests/

main/
  Forecast/
    run_forecast_to_dssat.R
    00_config_function.R
    02_run_agwise_multi_country.py
    03_bias_correction_forecast_multiVar.R
    04_prepare_dssat_geo_inputs.R
    AgWise_download.py
  DSSAT/
    common_helpers.R
    helpers_readGeo_CM_zone.R
    readGeo_CM_zone.R
```

Archived legacy and exploratory scripts are kept under `archive/`.

## DSSAT Handoff

After bias correction, the forecast bridge writes:

```bash
Rainfall_Season_1_PointData_AOI.RDS
temperatureMax_Season_1_PointData_AOI.RDS
temperatureMin_Season_1_PointData_AOI.RDS
solarRadiation_Season_1_PointData_AOI.RDS
SoilDEM_PointData_AOI_profile.RDS
manifest.csv
```

Units are DSSAT-ready:

```bash
RAIN = mm day-1
TMAX = degC
TMIN = degC
SRAD = MJ m-2 day-1
```

`04_prepare_dssat_geo_inputs.R` writes to `forecast/dssat_handoff/`, validates physical ranges, skips soil-point
folders outside the forecast grid, drops incomplete soil profiles, and keeps
the manifest aligned with points that can actually produce DSSAT files.

## Contact

Jemal S. Ahmed  
Alliance of Bioversity International & CIAT  
jemal.ahmed@cgiar.org
