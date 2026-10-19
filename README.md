# AgWISE Planting Date and Cultivar Pipeline

AgWISE pipeline for preparing seasonal climate forecast data, applying daily
bias correction, and generating DSSAT-ready weather and soil inputs for
planting date and cultivar advisory workflows.

The project is designed to be reusable across countries, zones, crops, and
local implementation partners. Country-specific settings are stored in YAML
configuration files, while the forecast and DSSAT processing logic remains in a
shared production codebase.

**If you're adding or running a country/crop use case, you should only ever
need `usecases/` (see `usecases/README.md`) and, for viewing results,
`README_shiny_dashboard.md`.** The scripts under `main/Forecast/` and
`main/DSSAT/` are the shared engine that YAML configs drive - you shouldn't
need to open or edit them for normal use (see "Creating a New Country or Crop
Use Case" below).

**Just want to see it run?** Follow "Run the Rwanda demo with Docker" below -
it needs Docker, a free Copernicus CDS account and one data download - no
R/Python/DSSAT installation.

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

## Run the Rwanda demo with Docker

The quickest way to see the whole pipeline work. A prebuilt Docker image
contains all the software (R, the Python `agwise-data` CLI, DSSAT-CSM
4.8.1.40, all packages) - nothing to install except Docker.

What the demo does: Rwanda maize, September 2026 seasonal forecast, all 5
provinces (~1,000 sites), one cultivar (890011), a range of planting dates.
The pipeline downloads the forecast, soil and elevation data, bias-corrects
the forecast, runs DSSAT for every site and planting date, ranks the planting
dates and builds an HTML dashboard.

**What is shared vs. what the pipeline downloads.** Bias correction needs
24 years (1993-2016) of historical data. Downloading it takes many hours and
the CHIRPS v3 rainfall it uses can't be downloaded by the pipeline at all, so
it is shared as a ready-made bundle. Everything specific to this run is
downloaded by the pipeline itself:

| Data | How you get it |
|---|---|
| Historical observations 1993-2016 (CHIRPS v3 rainfall, AgERA5 temperature and radiation) | Shared bundle |
| Historical SEAS5 forecasts 1993-2016 (hindcasts) | Shared bundle |
| SEAS5 seasonal forecast, September 2026 | **Downloaded** from Copernicus CDS - **needs your own CDS account** |
| Soil properties (SoilGrids) | **Downloaded**, no account needed |
| Elevation (Copernicus DEM) | **Downloaded**, no account needed |
| Rwanda administrative boundaries | **Downloaded**, no account needed |

### 1. What you need

- **Docker**:
  - Linux: Docker Engine (`docker` command).
  - Windows: Docker Desktop (uses WSL2). Run every command below from a WSL
    (Ubuntu) terminal, not PowerShell.
  - Mac: Docker Desktop, OrbStack or Colima. Colima is free for everyone:
    ```bash
    brew install colima docker
    colima start --vm-type vz --vz-rosetta --cpu 4 --memory 8
    ```
    Docker Desktop is free only for personal use, education and small
    organisations - larger institutions need a paid licence.
- **About 13 GB of free disk space** (image ~9 GB unpacked, data ~1.5 GB once
  downloaded).
- **Give Docker at least 4 CPUs and 8 GB of memory** (tested with 4 CPUs /
  10 GB).
- **An internet connection** for the downloads.
- **A Copernicus Climate Data Store (CDS) account and API key** - see step 2.
  This is required: without it the forecast can't be downloaded and the run
  stops.
- **Access to the image**: a free Docker Hub account (hub.docker.com). Send
  your Docker Hub username to the repository maintainer to be added to the
  private image.
- **The historical data bundle**: `agwise_rwanda_historical_data.tar.gz` and
  its checksum file `agwise_rwanda_historical_data.tar.gz.sha256` (~400 MB),
  shared by the maintainer.

The image is x86-64 (amd64) only, because the DSSAT binary is. On an x86
PC/server it runs natively; on an Apple Silicon Mac it runs under emulation
(Rosetta), which is slower but works.

### 2. Get a CDS account and API key

The SEAS5 seasonal forecast comes from the Copernicus Climate Data Store
(CDS), which is free but requires your own account. Your key is personal -
don't share it, and never put it in the repository or the image.

1. Create an account at https://cds.climate.copernicus.eu (top right,
   "Login - Register").
2. Accept the dataset licence: open
   https://cds.climate.copernicus.eu/datasets/seasonal-original-single-levels?tab=download,
   scroll to **Terms of use** and click **Accept**. Downloads fail with a
   "required licences not accepted" error until you do this.
3. Copy your **Personal Access Token** from your profile page
   (https://cds.climate.copernicus.eu/profile) - this is your API key.

You'll put the key in a small `cds.env` file in step 4.

### 3. Get the image

```bash
docker login -u <your-docker-hub-username>
docker pull --platform linux/amd64 acarmonacabrero/agwise-planting-date-and-cultivar:rwanda-demo-v1
```

`docker login` asks for a password - use a Docker Hub **personal access
token** (Account settings -> Personal access tokens, "Read" access is enough)
rather than your account password. `--platform linux/amd64` is required on
Apple Silicon Macs and harmless elsewhere. The download is ~2.2 GB.

### 4. Set up a demo folder

Create a folder for the demo (any name and location), put the two downloaded
bundle files in it, and work from there:

```bash
mkdir -p ~/agwise_demo
cd ~/agwise_demo
```

Check the download is complete and unpack it:

```bash
shasum -a 256 -c agwise_rwanda_historical_data.tar.gz.sha256
tar -xzf agwise_rwanda_historical_data.tar.gz
mkdir -p results
```

`shasum` should print `agwise_rwanda_historical_data.tar.gz: OK` (on Linux
you can use `sha256sum -c` instead).

Now create a file called `cds.env` in the same folder with these two lines,
replacing the second value with your Personal Access Token from step 2:

```text
CDSAPI_URL=https://cds.climate.copernicus.eu/api
CDSAPI_KEY=your-personal-access-token
```

(No quotes, no spaces around `=`.) You should now have:

```text
agwise_demo/
├── agwise_data/
│   └── Processed/        data cache: historical data from the bundle; the
│                         pipeline adds its downloads here
├── results/              empty - the pipeline writes its outputs here
├── cds.env               your CDS key (keep it private)
├── agwise_rwanda_historical_data.tar.gz
└── agwise_rwanda_historical_data.tar.gz.sha256
```

### 5. Run the demo

From inside the demo folder:

```bash
docker run --rm --platform linux/amd64 \
  --env-file cds.env \
  -v "$(pwd)/agwise_data/Processed:/mnt/agwise_data_root" \
  -v "$(pwd)/results:/workspace/Data" \
  acarmonacabrero/agwise-planting-date-and-cultivar:rwanda-demo-v1 \
  2>&1 | tee demo_run.log
```

What this does:

- `--rm` deletes the container when it finishes (your data and results are
  kept, see below).
- `--env-file cds.env` gives the pipeline your CDS key for this run only - it
  is not stored in the image or the container.
- The first `-v` connects your `agwise_data/Processed` folder to the
  pipeline's data cache: it reads the historical data from there and saves
  everything it downloads there too.
- The second `-v` connects your `results` folder to the pipeline's output
  folder. **Anything the pipeline writes anywhere else disappears when the
  container ends** - these two mounts are what keep the data and results.
- With no config given, the image runs the demo config
  `usecases/configs/RWA/maize_demo.yml`.
- `| tee demo_run.log` shows the progress on screen and also saves it to
  `demo_run.log`.

How long it takes: about **1 hour** in total on a recent Mac. The downloads
come first (~30 minutes in our test: four CDS forecast requests, plus soil and
elevation); CDS queues requests on its servers, so this part can be faster or
much slower depending on how busy CDS is - the pipeline just waits. The DSSAT
simulations then take about 25 minutes. It finishes with a line like:

```text
=== Pipeline finished at ..., exit code 0, elapsed 3513s ===
```

Lots of `STOP 99` lines and planting-date `WARNING`s during the run are
normal. So is a summary like `239 expected, 200 finished, 39 skipped` for a
province: DSSAT rejects a few sites' inputs, and those sites are skipped.

Running it again is much faster: everything downloaded is kept in
`agwise_data/Processed` and reused.

### 6. Look at the results

Everything is in
`results/usecases/useCase_Rwanda_demo/Maize/result/DSSAT/AOI/`:

| File | What it is |
|---|---|
| `Maize_Rwanda_dashboard.html` | Interactive dashboard - open it in a web browser |
| `Maize_2026_top_5_HWAH_combination_recommendation.csv` | Best 5 planting dates per site, with simulated yield (HWAH, kg/ha) |
| `Maize_2026_top_5_HWAH_combination_recommendation.nc` | The same, as a NetCDF grid |
| `Maize_2026_treatment_summary.csv` | Yield statistics per planting date across all sites |
| `Maize_2026_yield_by_pdate_cultivar.png` | Map of the yield of the top 3 planting dates |
| `Maize_2026_planting_date_gradients.png` | Map of the top 3 planting dates |

The DSSAT input and output files for every site are under
`results/usecases/useCase_Rwanda_demo/Maize/transform/DSSAT/`.

To run the demo again from scratch, delete and recreate `results/` first
(`rm -rf results && mkdir results`), so files from the previous run don't mix
in.

### If something goes wrong

- **The run stops with a CDS error mentioning licences or authentication**:
  check step 2 (licence accepted, token copied correctly into `cds.env`).
- **The run stops while downloading** (network error, timeout): run the same
  command again - whatever was already downloaded is kept and reused.

### Going further

- **Look inside the container** (opens a shell; type `exit` to leave). The
  code is in `/workspace`, DSSAT in `/opt/DSSAT`:
  ```bash
  docker run --rm -it --platform linux/amd64 --entrypoint bash \
    acarmonacabrero/agwise-planting-date-and-cultivar:rwanda-demo-v1
  ```
- **Run with your own code changes**: add
  `-v "/path/to/this/repo/main:/workspace/main"` to the run command, and the
  container uses your copy of `main/` instead of the one inside the image.
- **Other countries or seasons**: the historical bundle only covers Rwanda
  (1993-2016, September forecasts). Other configs also need their own
  historical data, which this demo doesn't include.
- **Rebuilding the image**: see the comments at the top of `Dockerfile`. A
  rebuild also needs the sibling `data_sourcing` repository's image and the
  DSSAT-CSM binaries, neither of which is in this repository.

## New to running R scripts from a terminal?

Everything in this README is run from a **terminal** (a command-line window),
not by clicking "Run" in RStudio's script editor. If you're an RStudio user
and haven't done this before:

1. In RStudio, open the **Terminal** tab (next to the Console tab), or open
   any terminal application and `cd` into this repository's folder.
2. Every gray code block below starting with `Rscript ...` is a single
   command you type (or copy-paste) into that terminal and press Enter.
   `Rscript` is R's own command-line tool for running a `.R` file outside of
   RStudio - it's the same R engine, just started from the terminal instead
   of by clicking a "Run" button.
3. Words starting with `--` (e.g. `--dry-run`, `--n-cores 4`) are called
   **flags** or **options** - they're extra instructions you can add after
   the script name to change how it behaves. You can copy a command exactly
   as shown, or drop/add flags as needed.
4. A **YAML file** (`.yml`) is a plain-text settings file - every use case's
   country, crop, zones, season dates, etc. live in one, and you can open and
   edit it in any text editor (including RStudio). You don't need to touch
   any `.R` script to change a country's settings, only its YAML file.

If a command below fails with something like `command not found`, it usually
means the terminal isn't in the repository folder yet - `cd` into it first.

## Quick Start

Always begin with a dry run. A dry run prints the command that would be
executed and checks the configuration wiring **without** downloading or
processing forecast data - it's a safe way to check your settings are wired
up correctly before committing to a run that can take hours.

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
create_dssat_weather_files: true
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
