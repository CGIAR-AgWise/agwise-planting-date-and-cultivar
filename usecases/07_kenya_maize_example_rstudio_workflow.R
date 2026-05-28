###############################################################################
# Script: 07_kenya_maize_example_rstudio_workflow.R
# Purpose:
#   RStudio-friendly end-to-end Kenya maize example workflow. The script shows
#   how a local user can inspect DSSAT variety options, create/update the YAML
#   use-case configuration, run the forecast-to-DSSAT handoff, and optionally
#   format DSSAT weather/soil files.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

# ---------------------------------------------------------------------------
# How to use this script in RStudio
# ---------------------------------------------------------------------------
# 1. Open this file in RStudio.
# 2. Review and edit the "User settings" block below.
# 3. Start with RUN_MODE <- "dry_run" to confirm paths and commands.
# 4. Change RUN_MODE <- "forecast" when you are ready to download/process data.
# 5. Change RUN_MODE <- "forecast_and_dssat_files" only after the forecast
#    handoff RDS files exist and you want DSSAT WTH/SOL files.
#
# Local adaptation notes:
# - Change country_code, country_name, use_case_name, crop, zones, and extent.
# - Put DSSAT template files under:
#     data/usecases/useCase_<Country>_<UseCaseName>/<Crop>/DSSAT/
# - Put soil/point files under:
#     data/countries/<ISO3>/forecast/geo_4cropModel/<Zone>/
# - Keep the season start as the crop season start. The forecast initialization
#   month is derived automatically from lead_months.

# ---------------------------------------------------------------------------
# 0. Locate the project and load shared helpers
# ---------------------------------------------------------------------------
script_dir <- if (file.exists("usecases/00_usecase_helpers.R")) {
  normalizePath("usecases", mustWork = TRUE)
} else if (requireNamespace("rstudioapi", quietly = TRUE) &&
           rstudioapi::isAvailable() &&
           nzchar(rstudioapi::getActiveDocumentContext()$path)) {
  dirname(normalizePath(rstudioapi::getActiveDocumentContext()$path, mustWork = TRUE))
} else {
  stop("Open this script from the project root or from RStudio so the usecases folder can be found.")
}

source(file.path(script_dir, "00_usecase_helpers.R"))
repo_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)

# ---------------------------------------------------------------------------
# 1. User settings
# ---------------------------------------------------------------------------
# RUN_MODE controls how far the script goes:
# - "dry_run": print commands only; no downloads or processing.
# - "forecast": create/update YAML and run forecast download, bias correction,
#   and DSSAT handoff RDS preparation.
# - "forecast_and_dssat_files": do everything in "forecast", then call the
#   DSSAT formatter to create weather/soil files for the configured zone(s).
RUN_MODE <- "dry_run"

# Set this to TRUE only when you want to force fresh downloads from CDS.
FORCE_DOWNLOAD <- FALSE

# Number of CPU cores for bias correction. Start conservatively on laptops.
N_CORES <- 4

# Python executable used by the ECMWF/AgWISE downloader.
PY_PATH <- "/opt/anaconda3/envs/WASS2S/bin/python"

# Kenya example season settings.
country_code <- "KEN"
country_name <- "Kenya"
use_case_name <- "Example"
crop <- "Maize"
zones <- c("Kisumu")

season_start_month <- 10
season_start_day <- 1
season_year <- 2025
season_length_months <- 3
lead_months <- 1

# CDS expects [North, West, South, East]. Values are already aligned to 0.01.
extent <- c(5.57, 33.40, -5.23, 42.43)

# ---------------------------------------------------------------------------
# 2. Inspect available DSSAT variety options
# ---------------------------------------------------------------------------
# The variety/cultivar options are read from the DSSAT template CSV. For a new
# locality, update the template CSV with locally relevant INGENO/CNAME rows.
variety_options <- read_dssat_variety_options(
  repo_root = repo_root,
  country = country_name,
  use_case_name = use_case_name,
  crop = crop
)

message("\nAvailable DSSAT variety options for this use case:")
print(variety_options)

# Pick a variety. NULL means use the first option in the template.
SELECTED_VARIETY_ID <- NULL
if (is.null(SELECTED_VARIETY_ID)) {
  SELECTED_VARIETY_ID <- variety_options$varietyid[[1]]
}
message("Selected variety ID: ", SELECTED_VARIETY_ID)

# ---------------------------------------------------------------------------
# 3. Create or update the YAML use-case configuration
# ---------------------------------------------------------------------------
# The YAML file is the stable record of the use case. The production runner
# reads this file, so a colleague can repeat the same run without editing code.
kenya_usecase <- list(
  name = "Kenya maize example seasonal forecast to DSSAT",
  country_code = country_code,
  country_name = country_name,
  use_case_name = use_case_name,
  crop = crop,
  zones = zones,
  season_start_month = season_start_month,
  season_start_day = season_start_day,
  season_year = season_year,
  season_length_months = season_length_months,
  lead_months = lead_months,
  n_cores = N_CORES,
  variables = c("PRCP", "TMAX", "TMIN", "SRAD"),
  manual_extent = TRUE,
  extent = extent,
  skip_dssat = FALSE,
  create_dssat_weather_files = identical(RUN_MODE, "forecast_and_dssat_files"),
  varietyid = SELECTED_VARIETY_ID
)

config_path <- file.path(repo_root, "usecases", "configs", country_code, "maize_example.yml")
message("\nWriting Kenya YAML config:")
message(write_usecase_yaml(kenya_usecase, config_path))

# Read the YAML back in. This confirms the pipeline uses the same file a
# command-line run would use.
kenya_usecase <- read_usecase_yaml(config_path)

# ---------------------------------------------------------------------------
# 4. Run or preview the forecast pipeline
# ---------------------------------------------------------------------------
cli <- list(
  "n-cores" = as.character(N_CORES),
  "py-path" = PY_PATH
)
if (identical(RUN_MODE, "dry_run")) cli[["dry-run"]] <- TRUE
if (isTRUE(FORCE_DOWNLOAD)) cli[["force-download"]] <- TRUE

message("\nForecast pipeline step:")
run_forecast_usecase(kenya_usecase, cli = cli, repo_root = repo_root)

# ---------------------------------------------------------------------------
# 5. Optional DSSAT weather/soil formatting
# ---------------------------------------------------------------------------
# The forecast run creates daily DSSAT handoff RDS files under:
#   data/countries/KEN/forecast/dssat_handoff/
#
# The formatting step below converts those RDS files plus DSSAT templates into
# DSSAT weather/soil files. It should be run only after the forecast handoff
# files exist.
if (identical(RUN_MODE, "forecast_and_dssat_files")) {
  message("\nDSSAT weather/soil formatting step:")
  kenya_usecase$create_dssat_weather_files <- TRUE
  format_dssat_zones(
    kenya_usecase,
    cli = list("format-zones" = TRUE),
    repo_root = repo_root
  )
}

message("\nKenya RStudio workflow finished with RUN_MODE = ", RUN_MODE)
