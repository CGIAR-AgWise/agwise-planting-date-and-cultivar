# AgWISE Planting Date and Cultivar Pipeline

AgWISE pipeline that recommends **planting dates and cultivars** from a
seasonal climate forecast. For every site on a grid covering a country's
zones, it simulates crop yield with the DSSAT crop model across a range of
planting dates and cultivars, driven by a bias-corrected SEAS5 seasonal
forecast, then ranks the options and produces maps, tables and a dashboard.

Each country/crop/season is a **use case**, described by one YAML file under
`usecases/configs/`. You run a use case; you don't edit code.

**Just want to see it run?** Follow "Run the Rwanda demo with Docker" below -
it needs Docker, a free Copernicus CDS account and one data download - no
R/Python/DSSAT installation.

## How the pipeline works

```text
usecases/configs/<ISO3>/<use_case>.yml
  -> usecases/run_usecase.R                  reads the YAML
  -> main/DSSAT/run_dssat_pipeline.R
       1. agwise-data CLI (data_sourcing)    site grid per zone; SEAS5 forecast
                                             download (CDS); bias correction
                                             against 1993-2016 observations;
                                             soil (SoilGrids) and elevation;
                                             writes DSSAT weather + soil files
       2. import + onset planting dates      per site: up to 8 planting dates
                                             around the forecast onset of rains
       3. DSSAT experiment files (FILEX)     planting dates x cultivars
       4. DSSAT-CSM 4.8 runs                 one per site
       5. merge, rank, export                top planting date/cultivar per
                                             site: CSV, NetCDF, maps, dashboard
```

Weather, forecast and soil data all come from the **`agwise-data` CLI**, the
Python package in the sibling `data_sourcing` repository. This repository
calls it as a command-line program (`main/DSSAT/run_datasourcing_export.R`)
and does everything DSSAT-related itself.

Key points:

- **Forecast initialization** = season start minus `lead_months` (e.g. season
  starting 1 October with `lead_months: 1` uses the September forecast).
- **Lead-0 spin-up**: with `lead_months: 0` the forecast starts on the
  planting-season start date, so the previous month's forecast is prepended
  to each site's weather as a spin-up period (taken from an existing export,
  or generated - which also needs that month's hindcasts).
- **Bias correction** uses 1993-2016 as calibration period: SEAS5 hindcasts
  vs. CHIRPS v3 rainfall and AgERA5 temperature/radiation.
- **Sites** are a regular grid (default 5 km) over each zone; all zones of a
  use case share one forecast domain, so it is downloaded once.
- Steps are **resumable**: downloaded data are cached and existing
  experiment files are reused, so re-running an interrupted use case picks up
  where it stopped.

> **Legacy code:** `main/Forecast/` is the previous, R-based forecast workflow
> (ECMWF download, bias correction and DSSAT handoff in R). It is no longer
> used by current use cases and is kept only for the older configs that still
> point to it. Its documentation is in `main/Forecast/LEGACY_PIPELINE.md`.

## Run the Rwanda demo with Docker

The quickest way to see the whole pipeline work. A prebuilt Docker image
contains all the software (R, the Python `agwise-data` CLI, DSSAT-CSM
4.8.1.40, all packages) - nothing to install except Docker.

What the demo does: Rwanda maize, season starting 1 October 2026, using the
September 2026 seasonal forecast (`lead_months: 1`), all 5
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
docker pull --platform linux/amd64 acarmonacabrero/agwise-planting-date-and-cultivar:rwanda-demo-v3
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
  acarmonacabrero/agwise-planting-date-and-cultivar:rwanda-demo-v3 \
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
=== Pipeline finished at ..., exit code 0, elapsed 3674s ===
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
- **On an Apple Silicon Mac, a site is occasionally skipped with a `core`
  file in its folder**: DSSAT crashed under x86 emulation. It's harmless -
  that site is left out of the results - and doesn't happen on x86 machines.

### Going further

- **Look inside the container** (opens a shell; type `exit` to leave). The
  code is in `/workspace`, DSSAT in `/opt/DSSAT`:
  ```bash
  docker run --rm -it --platform linux/amd64 --entrypoint bash \
    acarmonacabrero/agwise-planting-date-and-cultivar:rwanda-demo-v3
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

## Repository structure

```text
usecases/
  configs/<ISO3>/*.yml      One YAML file per use case (the only thing you edit)
  run_usecase.R             Runs one use case: Rscript usecases/run_usecase.R <yml>
  00_usecase_helpers.R      YAML reading and dispatch used by the runner

main/
  DSSAT/                    The pipeline: data_sourcing export, FILEX creation,
                            DSSAT runs, merging, ranking, plots, dashboards
  Kvuno/                    Convert results to the Kvuno upload format
  azure_blob/               Stage/upload the data cache to Azure Blob (CGLabs)
  RS/                       Remote-sensing helpers (crop type, phenology)
  Forecast/                 LEGACY R forecast workflow (see LEGACY_PIPELINE.md)

Landing/
  DSSAT/                    DSSAT cultivar/ecotype/species files and FILEX
                            templates, including project-specific cultivars
  crop_masks/               Crop masks used to filter results

Dockerfile                  Image with R, agwise-data, DSSAT (see demo below)
docker-entrypoint.sh        Container entrypoint
```

Use cases write everything under `data/usecases/useCase_<Country>_<use_case_name>/<Crop>/`
(or `Data/...`, inside the Docker image):

```text
transform/DSSAT/AOI/<varietyid>/<zone>/EXTE####/   DSSAT inputs/outputs per site
result/DSSAT/AOI/                                  final results (see demo step 6)
dssat.expfile.log, dssat.exec.log                  per-site progress/skip logs
```

## Use cases

Current use cases (all on the `agwise-data` path):

```text
KEN  maize_sep_init
MOZ  maize_oct_init, soybean_oct_init
MWI  maize_oct_init, soybean_oct_init
NGA  maize_full_mar, maize_full_apr, maize_full_jun, maize_full_jul
RWA  maize_sep_init, maize_sep_init_fert, maize_demo
ZMB  maize_oct_init, soybean_oct_init
```

`RWA/maize_demo` is the Docker demo; `RWA/maize_sep_init_fert` shows the
fertilizer options. Configs without `skip_weather_soil_creation: true` (ETH,
GHA and the RWA `*_august_init` ones) still use the legacy forecast workflow.

### YAML configuration

Example (`usecases/configs/ZMB/maize_oct_init.yml`, zones shortened):

```yaml
name: Zambia maize (October 2026 forecast init, lead_months=0, via agwise-datasourcing)
country_code: ZMB
country_name: Zambia
use_case_name: oct_init
crop: Maize
zones:
  - Central
  - Copperbelt
  - Lusaka
season_start_month: 10
season_start_day: 1
season_year: 2026
season_length_months: 3
lead_months: 0
varietyids:
  - 900111
  - 900112
  - 900113
skip_weather_soil_creation: true
generate_dssat_via_datasourcing: true
resolution_km: 10
build_dashboard: true
```

Fields:

```text
name                              Human-readable description
country_code / country_name       ISO3 code / name (name is used to find admin
                                  boundaries and in output folder names)
use_case_name                     Short scenario name, used in folder names
crop                              Maize, Soybean, Potato, Wheat or Cassava
zones                             Admin level-1 units to simulate
season_start_month/_day           Start of the planting season
season_year                       Year of the season
season_length_months              Not used by the current path (legacy only)
lead_months                       Forecast initialization = season start - this
varietyids                        DSSAT cultivar IDs (from Landing/DSSAT/*.CUL)
skip_weather_soil_creation        true = use agwise-data (current path);
                                  absent/false = legacy main/Forecast path
generate_dssat_via_datasourcing   true = run agwise-data to create the DSSAT
                                  weather/soil files if not already present
build_dashboard                   true = render the HTML dashboard at the end
```

Optional fields (defaults in `main/DSSAT/run_dssat_pipeline.R`,
`load_dssat_defaults()`):

```text
resolution_km          Site grid spacing, km (default 5; 10 = ~4x fewer sites)
reuse_existing_filex   Reuse existing experiment files on re-runs (default true;
                       set false after a newer forecast is released)
use_crop_mask          Restrict results to cropland (default false)
dssat_model            DSSAT model code when it differs from the cultivar
                       file prefix (e.g. CSCER for Wheat)
```

Fertilizer (at most one mode on; see `RWA/maize_sep_init_fert.yml`):

```text
simple_fertilizer       Use the FILEX template's own preset fertilizer
fert_grid_search        NPK rate factorial: fert_N_rates, fert_P_rates,
                        fert_K_rates, fert_application_dap (days after planting)
fert_factorial_preset   Run every treatment in fert_treatments_file (CSV)
crop_price              Optional; ranks treatments by net return
soil_p_raster           Soil P raster added to the FILEX when a fertilizer mode
                        is on (default: CGLabs path - not in the Docker image)
```

The YAML reader in this repo is minimal: use only `key: value` lines,
`  - item` lists as above and full-line `# comments`.

To add a use case, copy a current config (e.g. `ZMB/maize_oct_init.yml`), change
the country, zones, season and cultivars, and run it. New cultivars must exist
in the cultivar file under `Landing/DSSAT/` (e.g. `MZCER048.CUL`).
(`usecases/create_usecase_config.R` generates legacy-style configs and should
not be used for new use cases.)

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
3. Words starting with `--` (e.g. `--dry-run`) are called
   **flags** or **options** - they're extra instructions you can add after
   the script name to change how it behaves. You can copy a command exactly
   as shown, or drop/add flags as needed.
4. A **YAML file** (`.yml`) is a plain-text settings file - every use case's
   country, crop, zones, season dates, etc. live in one, and you can open and
   edit it in any text editor (including RStudio). You don't need to touch
   any `.R` script to change a country's settings, only its YAML file.

If a command below fails with something like `command not found`, it usually
means the terminal isn't in the repository folder yet - `cd` into it first.

## Running without Docker

The Docker image (see the demo above) is the easiest way to get a working
environment. To run directly on a server or laptop instead you need:

- **R** (4.5) with the packages in `main/DSSAT/00_load_packages.R` (DSSAT,
  tidyverse, terra, sf, future/furrr, geodata, ... plus rmarkdown, plotly,
  leaflet, DT for the dashboard).
- **DSSAT-CSM 4.8.1.40** installed at `/opt/DSSAT/v4.8.1.40/` (path set in
  `main/DSSAT/dssat_exec.R`), with the project cultivars from
  `Landing/DSSAT/*.CUL/.ECO/.SPE` appended to its `Genotype/` files (the
  `Dockerfile` shows how).
- **The `agwise-data` CLI** from the `data_sourcing` repository, installed in
  its own Python environment.
- **A CDS API key** for the forecast download (`~/.cdsapirc`, or the
  `CDSAPI_URL`/`CDSAPI_KEY` environment variables).

Environment variables (defaults point to the CGLabs installation):

```text
AGWISE_DATA_BIN            Path to the agwise-data executable
AGWISE_DATA_REPO_DIR       data_sourcing repository (for its R helpers)
AGWISE_DATA_PRODUCTS_DIR   Where agwise-data writes the DSSAT exports
AGWISE_DATA_ROOT           agwise-data cache root (downloads, harmonized data)
AGWISE_LOCAL_ROOT          Local raw-data tree (CGLabs Landing), if available
AGWISE_RAINFALL_SOURCE     chirps_v3 (needs local/cached data) or chirps
AGWISE_N_CORES             Max parallel workers for DSSAT steps
AGWISE_MEM_LIMIT_GB        Memory available, if it can't be detected
AGWISE_TMPDIR              Scratch folder for temporary files
```

Run a use case (check the configuration first with `--dry-run`):

```bash
Rscript usecases/run_usecase.R usecases/configs/RWA/maize_demo.yml --dry-run
Rscript usecases/run_usecase.R usecases/configs/RWA/maize_demo.yml
```

## Results and dashboards

- **Per use case**: `result/DSSAT/AOI/` holds the ranked recommendations
  (CSV and NetCDF), per-planting-date statistics, maps and a self-contained
  HTML dashboard (`build_dashboard: true`). The table in the demo's step 6
  describes each file.
- **All use cases together**: a Shiny app that browses the results of many
  countries/crops at once - see `README_shiny_dashboard.md`.
- **Kvuno upload**: `main/Kvuno/prepare_kvuno_upload.R` converts a result
  file to the Kvuno (kvuno.agwise.org) upload format;
  `merge_kvuno_uploads_by_crop.R` combines countries per crop.

## Troubleshooting

- **A province shows sites "skipped"** in the `DSSAT-run summary`: DSSAT
  rejected those sites' inputs (see `ERROR.OUT`/`WARNING.OUT` in the site's
  `EXTE####` folder and `dssat.exec.log`). A few per province is normal.
- **CDS errors** (licence, authentication): accept the SEAS5 dataset licence
  on the CDS website and check the API key.
- **Wrong or missing cultivar**: the `varietyids` must exist in
  `Landing/DSSAT/<model>048.CUL` and in the DSSAT `Genotype/` files.
- **A run was interrupted**: re-run the same command; downloads and finished
  experiment files are reused.

## Author

```text
Author: Jemal S. Ahmed
Email: jemal.ahmed@cgiar.org
Institution: Alliance of Bioversity International and CIAT (CGIAR)
Date: 2026-05-29
```
