# AgWISE Data Folder

This folder is organized for the production forecast-to-DSSAT workflow.

## Top-Level Layout

```bash
data/
  global/                     # Shared global soil and geospatial inputs
  countries/<ISO3>/           # Country-specific forecast workspace
  usecases/                   # Use-case-specific templates and model inputs
  archive/                    # Legacy, duplicate, stale, or metadata artifacts
  COUNTRY_DATA_MANIFEST.csv   # Country traceability table
  USECASE_DATA_MANIFEST.csv   # Use-case template/data traceability table
```

## Country Folder Convention

Each country folder should follow this pattern:

```bash
data/countries/<ISO3>/
  config/
    <ISO3>_config_agwise.json # Country run configuration
  observations/               # Daily observed reference data
  forecast/
    raw/                      # Raw hindcast and forecast NetCDF files
    bias_corrected/           # Daily bias-corrected NetCDF files
    geo_4cropModel/           # Soil/crop-model point inputs
    dssat_handoff/            # DSSAT-ready forecast RDS outputs
    dssat_weather/            # Optional direct DSSAT weather exports
    extremes/                 # Forecast agroclimate extremes
    Onset_DoY/                # Forecast rainfall onset products
    logs/                     # Runtime logs
    diagnostics/              # Verification/skill outputs
    manifests/                # Output manifests
```

## Use-Case Folder Convention

Use-case data belongs under `data/usecases/`, not directly under `data/`:

```bash
data/usecases/
  useCase_<Country>_<Name>/
    <Crop>/
      DSSAT/                  # DSSAT template files
      Landing/DSSAT/          # Optional alternate DSSAT template layout
      transform/              # Generated DSSAT-ready run folders
      result/                 # Generated DSSAT simulation outputs
      data_curation/          # Use-case point and curation inputs
```

Use-case folders are tracked in `USECASE_DATA_MANIFEST.csv`.

The manifest currently tracks active or scaffolded country workspaces for
Kenya, Rwanda, Ethiopia, Ghana, Malawi, and Zambia. A `usecase_scaffold` status
means the folder is prepared and the matching `usecases/*.R` script will create
the config and generated outputs on first run.

## Traceability Rules

- Active data must match the active `config/<ISO3>_config_agwise.json`.
- Forecast initialization is explicit in the config:
  `season_start_month`, `forecast_lead_months`, `forecast_init_year`,
  `forecast_init_month`, and `forecast_init_day`.
- Data produced before the one-month lead-time convention is archived under
  `data/archive/legacy_20260528/`.
- `geo_4cropModel/` is input point data. `dssat_handoff/` is generated
  DSSAT-ready forecast data.
- Do not manually edit generated NetCDF/RDS outputs; rerun the production runner.

## Production Runner

Use the root use-case scripts or the production runner:

```bash
Rscript usecases/01_rwanda_maize_forecast.R
Rscript main/Forecast/run_forecast_to_dssat.R --country KEN --season-start-month 10 --season-year 2025 --lead-months 1 --n-cores 4
```

## Archive

`data/archive/` is intentionally kept inside `data/` so old inputs and outputs
remain traceable without cluttering active country folders.
