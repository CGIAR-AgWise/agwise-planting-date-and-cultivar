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

usage <- function() {
  paste(
    "Usage:",
    "Rscript usecases/create_usecase_config.R \\",
    "  --country <ISO3> --country-name <Country> --use-case <Name> --crop <Crop> \\",
    "  --zones <Zone1,Zone2> --season-start-month <1-12> --season-year <YYYY> \\",
    "  --season-length-months <N> --extent <North,West,South,East>",
    "",
    "Optional:",
    "  --season-start-day <1-31> --lead-months <N> --n-cores <N>",
    "  --variables PRCP,TMAX,TMIN,SRAD --varietyid <DSSAT cultivar>",
    "  --output <config.yml> --wrapper-output <script.R>",
    "  --overwrite --no-wrapper --no-folders --create-dssat-weather-files",
    sep = "\n"
  )
}

split_csv <- function(x) {
  if (is.null(x) || !nzchar(x)) return(character())
  trimws(strsplit(x, ",", fixed = TRUE)[[1]])
}

slugify <- function(x) {
  x <- tolower(trimws(x))
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  x
}

r_string <- function(x) {
  paste0('"', gsub('"', '\\"', gsub("\\\\", "\\\\\\\\", x)), '"')
}

required_arg <- function(cli, name) {
  value <- cli[[name]]
  if (is.null(value) || !nzchar(value)) stop("Missing required argument: --", name, "\n\n", usage())
  value
}

integer_arg <- function(cli, name, default = NULL, min_value = NULL, max_value = NULL) {
  raw <- cli[[name]] %||% default
  value <- suppressWarnings(as.integer(raw))
  if (!is.finite(value) || is.na(value)) stop("--", name, " must be an integer.")
  if (!is.null(min_value) && value < min_value) stop("--", name, " must be >= ", min_value)
  if (!is.null(max_value) && value > max_value) stop("--", name, " must be <= ", max_value)
  value
}

normalize_cds_extent <- function(extent) {
  if (!length(extent)) return(numeric())
  if (length(extent) != 4L || any(is.na(extent))) {
    stop("--extent must contain four comma-separated numbers: North,West,South,East")
  }
  # Expand outward to the nearest 0.01 degree so CDS sub-region extraction accepts it.
  normalized <- c(
    ceiling(extent[[1]] * 100) / 100,
    floor(extent[[2]] * 100) / 100,
    floor(extent[[3]] * 100) / 100,
    ceiling(extent[[4]] * 100) / 100
  )
  if (!(normalized[[1]] > normalized[[3]] && normalized[[2]] < normalized[[4]])) {
    stop("--extent must be ordered as North,West,South,East")
  }
  if (any(abs(normalized - extent) > 1e-10)) {
    message(
      "Adjusted extent outward to CDS 0.01-degree grid: ",
      paste(normalized, collapse = ",")
    )
  }
  normalized
}

write_wrapper_script <- function(path, config_rel, script_name, overwrite) {
  if (file.exists(path) && !isTRUE(overwrite)) {
    stop("Wrapper script already exists; use --overwrite to replace: ", path)
  }
  wrapper <- c(
    "#!/usr/bin/env Rscript",
    "###############################################################################",
    paste0("# Script: ", script_name),
    "# Purpose: Run an AgWISE YAML-configured forecast-to-DSSAT use case.",
    "#",
    "# Author: Jemal S. Ahmed",
    "# Email: jemal.ahmed@cgiar.org",
    "# Institution: Alliance of Bioversity International and CIAT (CGIAR)",
    paste0("# Date: ", Sys.Date()),
    "###############################################################################",
    "",
    "file_arg <- grep(\"^--file=\", commandArgs(FALSE), value = TRUE)",
    "script_file <- if (length(file_arg)) normalizePath(sub(\"^--file=\", \"\", file_arg[[1]]), mustWork = TRUE) else NA_character_",
    "candidate_dirs <- unique(c(if (!is.na(script_file)) dirname(script_file), normalizePath(\"usecases\", mustWork = FALSE)))",
    "script_dir <- candidate_dirs[file.exists(file.path(candidate_dirs, \"00_usecase_helpers.R\"))][1]",
    "if (is.na(script_dir)) stop(\"Could not locate usecases/00_usecase_helpers.R. Run this wrapper from the project root or place it in usecases/.\")",
    "Sys.setenv(AGWISE_USECASES_DIR = script_dir)",
    "source(file.path(script_dir, \"00_usecase_helpers.R\"))",
    "",
    paste0("run_usecase_config(", r_string(config_rel), ")")
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(wrapper, path)
  Sys.chmod(path, mode = "0755")
  normalizePath(path, mustWork = FALSE)
}

wrapper_config_reference <- function(repo_root, out_path) {
  usecases_dir <- normalizePath(file.path(repo_root, "usecases"), mustWork = TRUE)
  out_norm <- normalizePath(out_path, mustWork = FALSE)
  usecases_prefix <- paste0(usecases_dir, .Platform$file.sep)
  if (startsWith(out_norm, usecases_prefix)) {
    sub(paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", usecases_prefix)), "", out_norm)
  } else {
    out_norm
  }
}

create_usecase_folders <- function(repo_root, country_code, country_name, use_case_name, crop) {
  country_root <- file.path(repo_root, "data", "countries", country_code)
  usecase_root <- file.path(
    repo_root, "data", "usecases",
    paste0("useCase_", country_name, "_", use_case_name),
    crop
  )
  folders <- c(
    file.path(country_root, "config"),
    file.path(country_root, "observations"),
    file.path(country_root, "forecast", c(
      "raw", "bias_corrected", "diagnostics", "downloads", "dssat_handoff",
      "dssat_weather", "geo_4cropModel", "logs", "manifests"
    )),
    file.path(usecase_root, "DSSAT")
  )
  invisible(lapply(folders, dir.create, recursive = TRUE, showWarnings = FALSE))
  folders
}

cli <- parse_usecase_args()
required <- c("country", "country-name", "use-case", "crop", "season-start-month", "season-year")
missing <- required[!required %in% names(cli)]
if (length(missing)) stop("Missing required arguments: ", paste(missing, collapse = ", "), "\n\n", usage())

repo_root <- usecase_repo_root()
country_code <- toupper(required_arg(cli, "country"))
if (!grepl("^[A-Z]{3}$", country_code)) stop("--country must be a three-letter ISO3 code, for example KEN or RWA.")
country_name <- required_arg(cli, "country-name")
crop <- required_arg(cli, "crop")
use_case_name <- required_arg(cli, "use-case")
config_name <- cli[["config-name"]] %||% paste(slugify(crop), slugify(use_case_name), sep = "_")
out_path <- cli[["output"]] %||% file.path(
  repo_root, "usecases", "configs", country_code,
  paste0(config_name, ".yml"))
out_path <- normalizePath(out_path, mustWork = FALSE)
overwrite <- isTRUE(cli[["overwrite"]])
if (file.exists(out_path) && !overwrite) {
  stop("Config already exists; use --overwrite to replace: ", out_path)
}

zones <- split_csv(cli[["zones"]])
variables <- split_csv(cli[["variables"]])
if (!length(variables)) variables <- c("PRCP", "TMAX", "TMIN", "SRAD")
variables <- toupper(variables)
supported_variables <- c("PRCP", "TMAX", "TMIN", "SRAD")
if (!all(variables %in% supported_variables)) {
  stop("Unsupported --variables value. Supported variables are: ", paste(supported_variables, collapse = ","))
}
extent_raw <- if (!is.null(cli[["extent"]])) as.numeric(split_csv(cli[["extent"]])) else numeric()
extent <- normalize_cds_extent(extent_raw)
if (!length(extent)) {
  message("No manual extent supplied. The forecast runner will derive the country extent from GADM.")
}

season_start_month <- integer_arg(cli, "season-start-month", min_value = 1, max_value = 12)
season_start_day <- integer_arg(cli, "season-start-day", default = 1, min_value = 1, max_value = 31)
season_year <- integer_arg(cli, "season-year", min_value = 1900)
season_length_months <- integer_arg(cli, "season-length-months", default = 4, min_value = 1, max_value = 12)
lead_months <- integer_arg(cli, "lead-months", default = 1, min_value = 0, max_value = 12)
n_cores <- integer_arg(cli, "n-cores", default = 4, min_value = 1)
if (n_cores < 4) message("Note: production use cases should normally use --n-cores 4 or higher.")

usecase <- list(
  name = cli[["name"]] %||% paste(country_name, crop, "seasonal forecast to DSSAT"),
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
  n_cores = n_cores,
  variables = variables,
  manual_extent = length(extent) == 4,
  extent = extent,
  skip_dssat = isTRUE(cli[["skip-dssat"]]),
  create_dssat_weather_files = isTRUE(cli[["create-dssat-weather-files"]]),
  varietyid = cli[["varietyid"]] %||% "999993"
)

message("Wrote: ", write_usecase_yaml(usecase, out_path))

if (!isTRUE(cli[["no-folders"]])) {
  folders <- create_usecase_folders(repo_root, country_code, country_name, use_case_name, crop)
  message("Prepared folder scaffold:")
  message(paste(" -", folders, collapse = "\n"))
}

if (!isTRUE(cli[["no-wrapper"]])) {
  config_rel <- wrapper_config_reference(repo_root, out_path)
  wrapper_name <- paste(slugify(country_name), slugify(crop), slugify(use_case_name), "forecast", sep = "_")
  wrapper_name <- paste0(wrapper_name, ".R")
  wrapper_path <- cli[["wrapper-output"]] %||% file.path(repo_root, "usecases", wrapper_name)
  wrapper_path <- normalizePath(wrapper_path, mustWork = FALSE)
  message("Wrote wrapper: ", write_wrapper_script(wrapper_path, config_rel, basename(wrapper_path), overwrite))
}

message("\nNext checks:")
message("  Rscript usecases/run_usecase.R ", out_path, " --dry-run --n-cores ", n_cores)
message("  Rscript usecases/run_usecase.R ", out_path, " --n-cores ", n_cores)
