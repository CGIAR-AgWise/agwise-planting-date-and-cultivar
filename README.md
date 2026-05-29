# AgWISE Planting Date and Cultivar Pipeline

AgWISE pipeline for preparing seasonal climate forecast data, applying daily
bias correction, and generating DSSAT-ready weather and soil inputs for
planting date and cultivar advisory workflows.

The project is designed to be reusable across countries, zones, crops, and
local implementation partners. Country-specific settings are stored in YAML
configuration files, while the forecast and DSSAT processing logic remains in a
shared production codebase.

## Overview

The pipeline connects climate forecast processing with DSSAT crop-model input
preparation.

```text
Use-case YAML config
  -> Forecast configuration
  -> ECMWF forecast and hindcast download
  -> Daily bias correction
  -> DSSAT handoff files
  -> DSSAT weather and soil files
```

The final output is daily climate data in a format suitable for DSSAT crop
model simulations.

Core forecast variables:

```text
PRCP  daily rainfall, mm day-1
TMAX  daily maximum temperature, degC
TMIN  daily minimum temperature, degC
SRAD  daily solar radiation, MJ m-2 day-1
```

## Key Features

- Country-agnostic use-case configuration.
- One-month forecast lead time before crop season start.
- Multi-country and single-country execution modes.
- RStudio-friendly Kenya example workflow.
- Daily bias correction for forecast variables.
- Proper ECMWF de-accumulation and unit conversion for DSSAT.
- Parallel processing support through `n_cores`.
- DSSAT weather and soil file preparation.
- Organized data folders for country data, shared geodata, and use-case files.
- Legacy and unused files separated into archive folders.

## Repository Structure

```text
main/
  Forecast/                  Forecast download, configuration, bias correction,
                             and DSSAT handoff preparation
  DSSAT/                     DSSAT weather and soil file preparation scripts

usecases/
  configs/                   YAML files for country/crop use cases
  run_usecase.R              Generic runner for one YAML use case
  run_multi_country.R        Generic runner for multiple YAML use cases
  create_usecase_config.R    Helper for creating new YAML configs
  *_forecast.R               Country wrapper scripts
  07_kenya_*_rstudio*.R      Step-by-step Kenya RStudio workflow

data/
  countries/                 Country-specific forecast workspaces
  global/                    Shared soil and geospatial inputs
  usecases/                  DSSAT templates and generated crop-model files
  archive/                   Archived legacy, stale, or metadata files

tests/                       Smoke and validation checks
archive/                     Archived legacy scripts and unused code
```

## Data Organization

Country forecast data are stored by ISO3 country code.

```text
data/countries/<ISO3>/
  config/
    <ISO3>_config_agwise.json
  observations/
  forecast/
    raw/
    bias_corrected/
    geo_4cropModel/
    dssat_handoff/
    dssat_weather/
    extremes/
    Onset_DoY/
    logs/
    diagnostics/
    manifests/
```

DSSAT use-case data are stored separately from country-wide climate data.

```text
data/usecases/
  useCase_<Country>_<UseCaseName>/
    <Crop>/
      DSSAT/
      Landing/DSSAT/
      transform/
      result/
      data_curation/
```

Shared soil and geospatial data are stored under:

```text
data/global/
  soil/
  admin_boundaries/
```

Traceability files:

```text
data/COUNTRY_DATA_MANIFEST.csv
data/USECASE_DATA_MANIFEST.csv
```

## Requirements

The full production workflow requires R, Python, Java support for `loadeR.java`,
and access to the Copernicus Climate Data Store API.

### R packages

The forecast workflow uses packages including:

```text
loadeR.java
geodata
jsonlite
ncdf4
loadeR
transformeR
downscaleR
loadeR.2nc
visualizeR
parallel
terra
gridExtra
grid
RColorBrewer
```

The DSSAT workflow also uses standard R data handling and geospatial packages
loaded by the scripts in `main/DSSAT/`.

### Python packages

The ECMWF/CDS download workflow uses packages including:

```text
cdsapi
xarray
pandas
numpy
dask
netCDF4
h5netcdf
rioxarray
requests
tqdm
matplotlib
cartopy
```

The default Python executable in the current use-case configs is:

```text
/opt/anaconda3/envs/WASS2S/bin/python
```

Override this path with `--py-path` if needed.

## Quick Start

Always begin with a dry run. A dry run prints the command that would be
executed and checks the configuration wiring without downloading or processing
forecast data.

```bash
Rscript usecases/run_usecase.R usecases/configs/KEN/maize_example.yml --dry-run
```

Run the Kenya use case:

```bash
Rscript usecases/run_usecase.R usecases/configs/KEN/maize_example.yml
```

Run all configured country use cases:

```bash
Rscript usecases/run_multi_country.R
```

Preview all configured country use cases:

```bash
Rscript usecases/run_multi_country.R --dry-run
```

Run the Kenya wrapper script:

```bash
Rscript usecases/06_kenya_maize_example_forecast.R --dry-run
```

## Kenya RStudio Workflow

The Kenya example includes a step-by-step script for users who prefer running
the workflow from RStudio:

```text
usecases/07_kenya_maize_example_workflow.R
```

This script demonstrates how to:

- Define the country, crop, zone, season, and forecast lead time.
- Set the CDS bounding box in `North, West, South, East` order.
- Read available DSSAT variety options from the template file.
- Select a DSSAT variety.
- Create or update the YAML configuration.
- Run the forecast pipeline.
- Optionally prepare DSSAT weather and soil files.

The script is controlled by:

```r
RUN_MODE <- "dry_run"
RUN_MODE <- "forecast"
RUN_MODE <- "forecast_and_dssat_files"
```

Recommended RStudio workflow:

1. Open `usecases/07_kenya_maize_example_workflow.R`.
2. Keep `RUN_MODE <- "dry_run"` for the first run.
3. Check the printed command, extent, zone, and selected variety.
4. Change to `RUN_MODE <- "forecast"` when CDS credentials and dependencies
   are ready.
5. Change to `RUN_MODE <- "forecast_and_dssat_files"` after DSSAT handoff files
   exist and weather/soil files are needed.

Current Kenya example:

```text
country_code: KEN
country_name: Kenya
use_case_name: Example
crop: Maize
zones: Kisumu
season_start_month: 10
season_start_day: 1
season_year: 2025
season_length_months: 3
lead_months: 1
varietyid: 999993
```

Current DSSAT variety option in the Kenya template:

```text
999993  SHORT_KENYA
```

## Active Use Cases

Current YAML configurations:

```text
usecases/configs/KEN/maize_example.yml
usecases/configs/RWA/maize_rab.yml
usecases/configs/ETH/maize_national.yml
usecases/configs/GHA/maize_national.yml
usecases/configs/MWI/maize_national.yml
```

Current wrapper scripts:

```text
usecases/01_rwanda_maize_forecast.R
usecases/02_ethiopia_maize_forecast.R
usecases/03_ghana_maize_forecast.R
usecases/04_malawi_maize_forecast.R
usecases/05_multi_country_maize_forecast.R
usecases/06_kenya_maize_example_forecast.R
usecases/07_kenya_maize_example_workflow.R
```

The wrapper scripts call the same YAML-driven runner. They are provided for
convenience and for country teams that prefer one script per scenario.

## YAML Configuration

A YAML config is the source of truth for each use case.

Example:

```yaml
name: Kenya maize example seasonal forecast to DSSAT
country_code: KEN
country_name: Kenya
use_case_name: Example
crop: Maize
zones:
  - Kisumu
season_start_month: 10
season_start_day: 1
season_year: 2025
season_length_months: 3
lead_months: 1
n_cores: 4
variables:
  - PRCP
  - TMAX
  - TMIN
  - SRAD
manual_extent: true
extent:
  - 5.57
  - 33.40
  - -5.23
  - 42.43
skip_dssat: false
create_dssat_weather_files: false
varietyid: 999993
```

Field guide:

```text
name                         Human-readable use-case name
country_code                 ISO3 country code
country_name                 Country name used in DSSAT folder names
use_case_name                Local partner or scenario name
crop                         Crop folder name
zones                        Zone names to process
season_start_month           Crop season start month
season_start_day             Crop season start day
season_year                  Crop season year
season_length_months         Number of crop-season months
lead_months                  Forecast lead time before season start
n_cores                      CPU cores for bias correction
variables                    Variables to bias-correct and export
manual_extent                TRUE when using a manual CDS bounding box
extent                       North, West, South, East
skip_dssat                   TRUE to skip DSSAT handoff preparation
create_dssat_weather_files   TRUE to create WTH/SOL files after handoff
varietyid                    DSSAT cultivar/variety code
```

## Creating a New Country or Crop Use Case

Create a new YAML config with:

```bash
Rscript usecases/create_usecase_config.R \
  --country KEN \
  --country-name Kenya \
  --use-case Example \
  --crop Maize \
  --zones Kisumu \
  --season-start-month 10 \
  --season-start-day 1 \
  --season-year 2025 \
  --season-length-months 3 \
  --lead-months 1 \
  --n-cores 4 \
  --extent 5.57,33.40,-5.23,42.43 \
  --varietyid 999993
```

Then prepare the required folders:

```text
data/countries/<ISO3>/
data/usecases/useCase_<Country>_<UseCaseName>/<Crop>/DSSAT/
```

Minimum adaptation checklist:

1. Choose country ISO3, country name, use-case name, crop, and zones.
2. Prepare or verify country observations under `data/countries/<ISO3>/`.
3. Add DSSAT templates under the matching `data/usecases/` folder.
4. Add local cultivar rows to the DSSAT template CSV.
5. Confirm the CDS extent uses `North, West, South, East`.
6. Start with `--dry-run`.
7. Run the forecast and bias correction.
8. Inspect forecast logs and output folders.
9. Confirm DSSAT handoff RDS files were created.
10. Run DSSAT formatting if WTH and SOL files are needed.

## One-Month Forecast Lead Time

The user provides the crop season start date. The pipeline derives the forecast
initialization date by subtracting `lead_months`.

Example:

```text
season_start_month: 10
season_start_day: 1
season_year: 2025
lead_months: 1
```

This means:

```text
Crop season starts:       2025-10-01
Forecast initialization:  2025-09-01
```

If the crop season starts in January, the forecast initialization rolls back
into the previous calendar year.

## Forecast and Bias Correction

The main forecast runner is:

```text
main/Forecast/run_forecast_to_dssat.R
```

It calls the forecast setup, download, bias-correction, and DSSAT handoff
scripts.

Lower-level forecast command example:

```bash
Rscript main/Forecast/run_forecast_to_dssat.R \
  --country KEN \
  --season-start-month 10 \
  --season-start-day 1 \
  --season-year 2025 \
  --season-length-months 3 \
  --lead-months 1 \
  --n-cores 4 \
  --variables PRCP,TMAX,TMIN,SRAD \
  --manual-extent \
  --extent 5.57,33.40,-5.23,42.43
```

Bias-corrected NetCDF outputs are written to:

```text
data/countries/<ISO3>/forecast/bias_corrected/
```

DSSAT handoff outputs are written to:

```text
data/countries/<ISO3>/forecast/dssat_handoff/
```

## DSSAT Handoff and Formatting

The forecast bridge writes handoff files such as:

```text
Rainfall_Season_1_PointData_AOI.RDS
temperatureMax_Season_1_PointData_AOI.RDS
temperatureMin_Season_1_PointData_AOI.RDS
solarRadiation_Season_1_PointData_AOI.RDS
SoilDEM_PointData_AOI_profile.RDS
manifest.csv
```

The DSSAT formatting script is:

```text
main/DSSAT/readGeo_CM_zone.R
```

To create DSSAT WTH and SOL files after the handoff exists, set this in the
YAML config:

```yaml
create_dssat_weather_files: true
```

or run:

```bash
Rscript usecases/run_usecase.R usecases/configs/KEN/maize_example.yml --format-zones
```

Generated DSSAT files are written under the matching use-case folder in:

```text
data/usecases/useCase_<Country>_<UseCaseName>/<Crop>/
```

## Expected DSSAT Weather Variables

DSSAT weather files should contain daily rows with crop-model-ready units.

```text
DATE  daily date
SRAD  solar radiation, MJ m-2 day-1
TMAX  maximum temperature, degC
TMIN  minimum temperature, degC
RAIN  rainfall, mm day-1
```

Forecast periods can cross calendar years. Outputs should use the available
forecast dates and should not be truncated at December 31.

## Parallel Processing

Set CPU cores in YAML:

```yaml
n_cores: 4
```

or override from the command line:

```bash
Rscript usecases/run_usecase.R usecases/configs/KEN/maize_example.yml --n-cores 8
```

Suggested starting points:

```text
Laptop or small VM:      2 to 4 cores
Workstation:             4 to 8 cores
Large server/HPC node:   8 or more cores after memory testing
```

## Quality Control Checklist

After running the pipeline, confirm:

- Country config exists under `data/countries/<ISO3>/config/`.
- Raw forecast and hindcast files exist under `forecast/raw/`.
- Bias-corrected files exist under `forecast/bias_corrected/`.
- DSSAT handoff RDS files exist under `forecast/dssat_handoff/`.
- `manifest.csv` lists the expected zones.
- RAIN values are daily totals, not cumulative totals.
- TMAX is generally greater than or equal to TMIN.
- WTH files contain daily rows for the expected forecast horizon.
- Forecast dates are not cut off at the end of one calendar year.
- Soil profiles are present and aligned with forecast points.
- Outputs are under `data/countries/` or `data/usecases/`, not old folders.

## Validation Commands

Parse active R scripts:

```bash
Rscript -e 'files <- c(list.files("usecases", pattern="[.]R$", full.names=TRUE), list.files("main/Forecast", pattern="[.]R$", full.names=TRUE), list.files("main/DSSAT", pattern="[.]R$", full.names=TRUE), "data/usecases/useCase_Kenya_Example/Maize/DSSAT/config.R"); for (f in files) { parse(f); cat("parse ok:", f, "\n") }'
```

Compile Python scripts:

```bash
python3 -m py_compile \
  main/Forecast/AgWise_download.py \
  main/Forecast/02_run_agwise_multi_country.py \
  main/Forecast/config_read.py
```

Run Kenya dry-run:

```bash
Rscript usecases/06_kenya_maize_example_forecast.R --dry-run
```

Run multi-country dry-run:

```bash
Rscript usecases/05_multi_country_maize_forecast.R --dry-run
```

Check for old hard-coded active paths:

```bash
rg -n "Data/useCase_|data/useCase_|/Data/|/home/jovyan|Global_GeoData|geo_4cropModel_forecast|daily_model_data|Observation/|Scripts/generic" \
  main/Forecast main/DSSAT usecases data -g '!data/archive/**'
```

No output means the active production path is clean.

## Troubleshooting

### CDS coordinate error

If CDS reports that a coordinate must be a multiple of `0.01`, round or expand
the bounding box to two decimal places.

Use this order:

```text
North, West, South, East
```

Example:

```text
5.57,33.40,-5.23,42.43
```

### Rainfall is cumulative

Rainfall should be a daily total. If it grows every day like a cumulative
curve, raw ECMWF total precipitation was not de-accumulated.

Check:

```text
RAIN = (current cumulative TP - previous cumulative TP) * 1,000
```

### DSSAT files are missing

Check:

- `data/countries/<ISO3>/forecast/dssat_handoff/` exists.
- Expected RDS files are present.
- The zone name in YAML matches the handoff manifest.
- `create_dssat_weather_files: true` is set or `--format-zones` is used.
- DSSAT templates exist under `data/usecases/`.

### Wrong cultivar or variety

Check the DSSAT template CSV under:

```text
data/usecases/useCase_<Country>_<UseCaseName>/<Crop>/DSSAT/
```

The pipeline reads cultivar options from `INGENO` and the variety/name column.
Set the selected cultivar with `varietyid` in the YAML config.


## Documentation

Additional documentation:

```text
data/README.md
usecases/README.md
main/Forecast/README.md
```

Important production scripts:

```text
main/Forecast/run_forecast_to_dssat.R
main/Forecast/00_config_function.R
main/Forecast/02_run_agwise_multi_country.py
main/Forecast/03_bias_correction_forecast_multiVar.R
main/Forecast/04_prepare_dssat_geo_inputs.R
main/Forecast/AgWise_download.py
main/DSSAT/readGeo_CM_zone.R
main/DSSAT/helpers_readGeo_CM_zone.R
usecases/00_usecase_helpers.R
```

## Author

```text
Author: Jemal S. Ahmed
Email: jemal.ahmed@cgiar.org
Institution: Alliance of Bioversity International and CIAT (CGIAR)
Date: 2026-05-29
```
