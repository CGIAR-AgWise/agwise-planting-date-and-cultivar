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
- Reproducible Mozambique Chókwè maize workflow.
- Daily bias correction for forecast variables.
- Proper ECMWF de-accumulation and unit conversion for DSSAT.
- Parallel processing support through `n_cores`.
- DSSAT weather and soil file preparation.
- Organized data folders for country data, shared geodata, and use-case files.
- Reusable country/use-case templates are kept alongside the primary Chókwè
  workflow; scenario-only artifacts have been removed.

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
  *_forecast.R               Optional country-specific wrapper scripts

data/
  countries/                 Country-specific forecast workspaces
  global_geodata/            Shared geospatial landing data
  usecases/                  DSSAT templates and generated crop-model files

tests/                       Smoke and validation checks
integration/                 IWMI adapter, synthetic rainfall, and advisory
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
data/global_geodata/
  Landing/
  soil/
  admin_boundaries/
```

Traceability files:

```text
data/COUNTRY_DATA_MANIFEST.csv
data/USECASE_DATA_MANIFEST.csv
```

## Requirements

The full production workflow requires Conda, R, Python, Java support for
`loadeR.java`, access to the Copernicus Climate Data Store API, and a local
DSSAT installation for crop simulations.

All Conda, Python, and CRAN R dependencies are declared in
[`environment.yml`](./environment.yml). Do not install the package lists
manually from this README. The climate4R packages that are hosted on GitHub
are installed separately by [`install_pkgs.R`](./install_pkgs.R) after the
environment is activated.

Create and activate the environment:

```bash
conda env create -f environment.yml
conda activate agwise-integration
```

If the environment already exists, update it after changes to
`environment.yml`:

```bash
conda env update -f environment.yml --prune
conda activate agwise-integration
```

Install the GitHub climate4R packages once from the activated environment:

```bash
Rscript install_pkgs.R
```

The environment file also includes the Python packages used by the forecast,
synthetic-rainfall, IWMI, and advisory tooling. The runner uses the Python
executable supplied with `--py-path`. For a local Conda environment on Windows,
use:

```text
C:\Users\<user>\miniforge3\envs\agwise-integration\python.exe
```

On Linux or macOS, use the active environment's Python executable. Always
override this path with `--py-path` when the default `python` command is not
the intended environment.

### Windows requirements

For the Windows workflow, ensure both `Rscript.exe` and the Conda Python
executable are available. The use-case runner launches the child forecast with
the same R installation that launched `run_usecase.R`, so the command works
even when `Rscript` is not globally available on `PATH`.

The DSSAT executable defaults to:

```text
C:\DSSAT48\DSCSM048.EXE
```

Set `DSSAT_CSM` if DSSAT is installed elsewhere:

```bash
export DSSAT_CSM='C:/DSSAT48/DSCSM048.EXE'
```

## Quick Start: Mozambique Chókwè

Always begin with a dry run. A dry run prints the command that would be
executed and checks the configuration wiring without downloading or processing
forecast data.

After environment setup, verify the tools from the activated environment:

```bash
python --version
Rscript --version
make help
```

```bash
Rscript usecases/run_usecase.R \
  usecases/configs/MOZ/maize_chokwe.yml \
  --dry-run
```

Run the Mozambique Chókwè use case:

```bash
Rscript usecases/run_usecase.R \
  usecases/configs/MOZ/maize_chokwe.yml \
  --n-cores 1
```

For a local Windows run with copied forecast inputs, reuse existing files and
provide the Conda Python executable:

```bash
Rscript usecases/run_usecase.R \
  usecases/configs/MOZ/maize_chokwe.yml \
  --n-cores 1 \
  --py-path "$CONDA_PREFIX/python.exe" \
  --skip-download
```

If you are validating only forecast and bias correction, add
`--skip-dssat`. Remove that flag for the complete forecast-to-DSSAT handoff.

Prepare DSSAT weather and soil files from an existing forecast handoff:

```bash
Rscript -e 'source("usecases/00_usecase_helpers.R"); root <- normalizePath("."); cfg <- read_usecase_yaml("usecases/configs/MOZ/maize_chokwe.yml"); format_dssat_zones(cfg, cli=list("format-zones"=TRUE, "n-cores"="1"), repo_root=root)'
```

Generate the advisory from the DSSAT treatment summary:

```bash
make advisory FORCE=1
```

The `make setup` target only prints the setup commands; it does not create the
environment or install packages automatically. The complete setup sequence is:

```bash
conda env create -f environment.yml
conda activate agwise-integration
Rscript install_pkgs.R
make dry-run
```

The main Makefile targets are `setup`, `dry-run`, `iwmi-rainfall`, `forecast`,
`advisory`, `workflow`, `status`, `invalidate`, and `clean-python-cache`.
The primary Chókwè workflow is:

```bash
make workflow \
  LOCATION=Chokwe \
  CROP=Maize \
  SEASON_START=2025-11-01 \
  SEASON_END=2026-02-28 \
  AGWISE_N_CORES=2
```

The dry run uses the configured `SEASON_YEAR`, `AGWISE_N_CORES`, and `PY_PATH`
values, but does not download data or run bias correction:

```bash
make dry-run \
  SEASON_YEAR=2025 \
  AGWISE_N_CORES=1 \
  PY_PATH="$CONDA_PREFIX/python.exe"
```

The Makefile variables used by the primary workflow are:

```text
USECASE_CONFIG   usecases/configs/MOZ/maize_chokwe.yml
LOCATION         Chokwe
CROP             Maize
SEASON_START     2025-11-01
SEASON_END       2026-02-28
SEASON_YEAR      2025
AGWISE_N_CORES   2
PY_PATH          Python executable passed to the R forecast runner
SKIP_DOWNLOAD    1 to reuse local forecast inputs
FORCE            1 to refresh completed checkpoints
```

`make iwmi-rainfall` writes the synthetic series to
`integration/synthetic_rainfall/output/chokwe_2025_26_target_year_rainfall.csv`
by default. `IWMI_RAINFALL_OUTPUT` can override that destination. This target
does not enable the override by itself; pass the generated file as
`IWMI_PRCP_CSV` to `make forecast` or `make workflow`.

Use `FORCE=1` to refresh completed checkpoints. If forecast inputs already
exist locally, use:

```bash
make forecast \
  SKIP_DOWNLOAD=1 \
  PY_PATH="$CONDA_PREFIX/python.exe"
```

To inspect whether the forecast and advisory checkpoints are current:

```bash
make status
```

To force both stages to run again:

```bash
make workflow FORCE=1
```

The Makefile uses POSIX shell syntax. Git Bash, WSL, or another POSIX-compatible
shell is recommended on Windows. Advisory output filenames are generated with
Python, not the Unix `tr` utility, so the Makefile works with the Windows
environment used by this repository as long as `PYTHON` is available.

To select a custom advisory summary or output path:

```bash
make advisory \
  DSSAT_SUMMARY=path/to/Maize_2025_treatment_summary.csv \
  ADVISORY_OUTPUT=integration/examples/custom_advisory.json \
  LOCATION=Chokwe CROP=Maize
```

To run the opt-in synthetic IWMI rainfall experiment:

```bash
make iwmi-rainfall \
  IWMI_RAINFALL_OUTPUT=integration/synthetic_rainfall/output/chokwe_2025_26_target_year_rainfall.csv

make workflow FORCE=1 \
  IWMI_PRCP_CSV=integration/synthetic_rainfall/output/chokwe_2025_26_target_year_rainfall.csv \
  LOCATION=Chokwe CROP=Maize \
  SEASON_START=2025-11-01 SEASON_END=2026-02-28 \
  SEASON_YEAR=2025 AGWISE_N_CORES=2
```

The override changes only `PRCP`/DSSAT `RAIN` on dates covered by the CSV.
AgWise `PRCP` is retained outside that date range, while `TMAX`, `TMIN`, and
`SRAD` continue to come from AgWise.

## Mozambique Chókwè Workflow

The primary integration case is maize in Chókwè, Mozambique. It uses a
November 2025 to February 2026 season, a one-month forecast lead, and the
manual Chókwè extent:

```text
usecases/configs/MOZ/maize_chokwe.yml
```

The configuration defines:

```text
country_code: MOZ
country_name: Mozambique
use_case_name: Chókwè
crop: Maize
zones: Chókwè
season_start_month: 11
season_start_day: 1
season_year: 2025
season_length_months: 4
lead_months: 1
varietyid: 900111
manual_extent: true
extent: -23.5, 32.5, -25.5, 33.5
```

The workflow can optionally replace DSSAT rainfall with the synthetic IWMI
rainfall experiment. This changes only rainfall on dates covered by the
override CSV; AgWise temperature and solar-radiation inputs remain in use:

```text
integration/synthetic_rainfall/output/
  chokwe_2025_26_target_year_rainfall.csv
```

Synthetic rainfall generation defaults to
`target-year-fallback`: exact IWMI year/month totals are used when available,
and calendar-month climatology fills only missing months. Use
`IWMI_MONTHLY_MODE=target-year` to require complete target-year monthly
coverage, or `IWMI_MONTHLY_MODE=climatology` to use historical calendar-month
means only. The generator writes a JSON metadata sidecar next to the rainfall
CSV.

## Active Use Cases

Current YAML configurations:

```text
usecases/configs/MOZ/maize_chokwe.yml
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

Mozambique Chókwè example:

```yaml
name: Mozambique Maize seasonal forecast to DSSAT
country_code: MOZ
country_name: Mozambique
use_case_name: Chókwè
crop: Maize
zones:
  - Chókwè
season_start_month: 11
season_start_day: 1
season_year: 2025
season_length_months: 4
lead_months: 1
n_cores: 1
variables:
  - PRCP
  - TMAX
  - TMIN
  - SRAD
manual_extent: true
extent:
  - -23.5
  - 32.5
  - -25.5
  - 33.5
skip_dssat: false
create_dssat_weather_files: false
varietyid: 900111
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

New countries are added from `usecases/` only. Do not edit scripts in
`main/Forecast/` or `main/DSSAT/`; those are shared production engines.

Create a new YAML config, folder scaffold, and optional wrapper script with:

```bash
Rscript usecases/create_usecase_config.R \
  --country TZA \
  --country-name Tanzania \
  --use-case National \
  --crop Maize \
  --zones Arusha,Dodoma \
  --season-start-month 11 \
  --season-start-day 1 \
  --season-year 2026 \
  --season-length-months 4 \
  --lead-months 1 \
  --n-cores 4 \
  --extent -1.234,29.123,-11.222,40.987 \
  --varietyid 999993
```

The creator validates the config, expands the CDS bounding box outward to the
nearest `0.01` degree, writes:

```text
usecases/configs/<ISO3>/<crop_usecase>.yml
usecases/<country>_<crop>_<usecase>_forecast.R
```

and prepares the folder scaffold:

```text
data/countries/<ISO3>/
data/usecases/useCase_<Country>_<UseCaseName>/<Crop>/DSSAT/
```

Run the generated use case without editing main scripts:

```bash
Rscript usecases/run_usecase.R usecases/configs/TZA/maize_national.yml --dry-run --n-cores 4
Rscript usecases/run_usecase.R usecases/configs/TZA/maize_national.yml --n-cores 4
```

or use the generated wrapper:

```bash
Rscript usecases/tanzania_maize_national_forecast.R --dry-run --n-cores 4
```

Minimum adaptation checklist:

1. Choose country ISO3, country name, use-case name, crop, and zones.
2. Create the YAML with `usecases/create_usecase_config.R`.
3. Confirm the CDS extent uses `North, West, South, East`.
4. Start with `--dry-run`.
5. Run the forecast and bias correction.
6. Inspect forecast logs and output folders.
7. Confirm DSSAT handoff RDS files were created.
8. Add DSSAT templates under `data/usecases/.../DSSAT/` before enabling WTH/SOL formatting.
9. Add local cultivar rows to the DSSAT template CSV.
10. Set `create_dssat_weather_files: true` or use `--format-zones` when WTH and SOL files are needed.

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
  --country MOZ \
  --season-start-month 11 \
  --season-start-day 1 \
  --season-year 2025 \
  --season-length-months 4 \
  --lead-months 1 \
  --n-cores 1 \
  --variables PRCP,TMAX,TMIN,SRAD \
  --manual-extent \
  --extent -23.5,32.5,-25.5,33.5
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
Rscript usecases/run_usecase.R usecases/configs/MOZ/maize_chokwe.yml --format-zones
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
Rscript -e 'files <- c(list.files("usecases", pattern="[.]R$", full.names=TRUE), list.files("main/Forecast", pattern="[.]R$", full.names=TRUE), list.files("main/DSSAT", pattern="[.]R$", full.names=TRUE)); for (f in files) { parse(f); cat("parse ok:", f, "\n") }'
```

Compile Python scripts:

```bash
python3 -m py_compile \
  main/Forecast/AgWise_download.py \
  main/Forecast/02_run_agwise_multi_country.py \
  main/Forecast/config_read.py
```

Run the Mozambique dry-run:

```bash
Rscript usecases/run_usecase.R \
  usecases/configs/MOZ/maize_chokwe.yml \
  --dry-run
```

Run multi-country dry-run:

```bash
Rscript usecases/05_multi_country_maize_forecast.R --dry-run
```

Check for old hard-coded active paths:

```bash
rg -n "Data/useCase_|data/useCase_|/Data/|/home/jovyan|Global_GeoData|geo_4cropModel_forecast|daily_model_data|Observation/|Scripts/generic" \
  main/Forecast main/DSSAT usecases data
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

Chókwè example:

```text
-23.5,32.5,-25.5,33.5
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
integration/README.md
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
