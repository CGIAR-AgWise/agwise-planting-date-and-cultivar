#!/usr/bin/env Rscript
###############################################################################
# Script: create_usecase_config.R
# Purpose: Create an AgWISE use-case YAML config from command-line arguments.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE)) else "usecases"
source(file.path(script_dir, "00_usecase_helpers.R"))

cli <- parse_usecase_args()
required <- c("country", "country-name", "use-case", "crop", "season-start-month", "season-year")
missing <- required[!required %in% names(cli)]
if (length(missing)) stop("Missing required arguments: ", paste(missing, collapse = ", "))

country_code <- toupper(cli[["country"]])
crop <- cli[["crop"]]
use_case_name <- cli[["use-case"]]
config_name <- tolower(paste(crop, use_case_name, sep = "_"))
config_name <- gsub("[^a-z0-9_]+", "_", config_name)
out_path <- cli[["output"]] %||% file.path(
  usecase_repo_root(), "usecases", "configs", country_code,
  paste0(config_name, ".yml"))

zones <- if (!is.null(cli[["zones"]])) trimws(strsplit(cli[["zones"]], ",", fixed = TRUE)[[1]]) else character()
variables <- if (!is.null(cli[["variables"]])) trimws(strsplit(cli[["variables"]], ",", fixed = TRUE)[[1]]) else c("PRCP", "TMAX", "TMIN", "SRAD")
extent <- if (!is.null(cli[["extent"]])) as.numeric(strsplit(cli[["extent"]], ",", fixed = TRUE)[[1]]) else numeric()

usecase <- list(
  name = paste(cli[["country-name"]], crop, "seasonal forecast to DSSAT"),
  country_code = country_code,
  country_name = cli[["country-name"]],
  use_case_name = use_case_name,
  crop = crop,
  zones = zones,
  season_start_month = as.integer(cli[["season-start-month"]]),
  season_start_day = as.integer(cli[["season-start-day"]] %||% 1),
  season_year = as.integer(cli[["season-year"]]),
  season_length_months = as.integer(cli[["season-length-months"]] %||% 4),
  lead_months = as.integer(cli[["lead-months"]] %||% 1),
  n_cores = as.integer(cli[["n-cores"]] %||% 4),
  variables = variables,
  manual_extent = length(extent) == 4,
  extent = extent,
  skip_dssat = FALSE,
  create_dssat_weather_files = FALSE,
  varietyid = cli[["varietyid"]] %||% "999993"
)

message("Wrote: ", write_usecase_yaml(usecase, out_path))
