#!/usr/bin/env Rscript
###############################################################################
# AgWISE production runner: climate forecast -> bias correction -> DSSAT inputs
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
#
# Example:
#   Rscript main/Forecast/run_forecast_to_dssat.R \
#     --country KEN \
#     --season-start-month 10 \
#     --season-year 2025 \
#     --season-length-months 3 \
#     --lead-months 1 \
#     --n-cores 4
###############################################################################

parse_args <- function(args) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
    name <- sub("^--", "", key)
    if (name %in% c("force-download", "skip-dssat", "manual-extent")) {
      out[[name]] <- TRUE
      i <- i + 1L
    } else {
      if (i == length(args)) stop("Missing value for ", key)
      out[[name]] <- args[[i + 1L]]
      i <- i + 2L
    }
  }
  out
}

arg <- function(args, name, default = NULL) {
  value <- args[[name]]
  if (is.null(value)) default else value
}

as_int <- function(x, name) {
  value <- suppressWarnings(as.integer(x))
  if (!is.finite(value) || is.na(value)) stop(name, " must be an integer.")
  value
}

as_vars <- function(x) {
  vars <- trimws(strsplit(x, ",", fixed = TRUE)[[1]])
  vars[nzchar(vars)]
}

cmd <- commandArgs(FALSE)
file_arg <- grep("^--file=", cmd, value = TRUE)
script_dir <- if (length(file_arg)) {
  dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE))
} else {
  normalizePath(".", mustWork = TRUE)
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

country <- toupper(arg(args, "country", "KEN"))
season_start_month <- as_int(arg(args, "season-start-month", "10"), "season-start-month")
season_start_day <- as_int(arg(args, "season-start-day", "1"), "season-start-day")
season_year <- as_int(arg(args, "season-year", format(Sys.Date(), "%Y")), "season-year")
season_length_months <- as_int(arg(args, "season-length-months", "3"), "season-length-months")
lead_months <- as_int(arg(args, "lead-months", "1"), "lead-months")
n_cores <- as_int(arg(args, "n-cores", "1"), "n-cores")
variables <- as_vars(arg(args, "variables", "PRCP,TMAX,TMIN,SRAD"))

base_dir <- normalizePath(arg(args, "base-dir", file.path(script_dir, "..", "..", "data")), mustWork = FALSE)
py_path <- arg(args, "py-path", "/opt/anaconda3/envs/WASS2S/bin/python")
force_download <- isTRUE(args[["force-download"]])
export_dssat <- !isTRUE(args[["skip-dssat"]])
use_manual_extent <- isTRUE(args[["manual-extent"]])
extent_manual <- as.numeric(strsplit(arg(args, "extent", "16,34,8,40"), ",", fixed = TRUE)[[1]])
if (use_manual_extent && length(extent_manual) != 4L) {
  stop("--extent must be four comma-separated values: north,west,south,east")
}

setwd(script_dir)
source(file.path(script_dir, "03_bias_correction_forecast_multiVar.R"))

run_agwise_seasonal_forecast_BC(
  country_code = country,
  init_month_user = season_start_month,
  init_day_user = season_start_day,
  season_length_months = season_length_months,
  forecast_year = season_year,
  forecast_lead_months = lead_months,
  use_manual_extent = use_manual_extent,
  extent_manual = extent_manual,
  base_dir = base_dir,
  main_script_dir = script_dir,
  py_path = py_path,
  variables_to_bc = variables,
  force_download = force_download,
  export_dssat = export_dssat,
  n_cores = n_cores
)
