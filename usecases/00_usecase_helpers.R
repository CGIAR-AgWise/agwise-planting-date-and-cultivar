#!/usr/bin/env Rscript
###############################################################################
# Script: 00_usecase_helpers.R
# Purpose: Shared helpers for AgWISE use-case YAML configs and runner scripts.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

usecase_script_dir <- function() {
  env_dir <- Sys.getenv("AGWISE_USECASES_DIR", unset = NA_character_)
  if (!is.na(env_dir) && file.exists(file.path(env_dir, "00_usecase_helpers.R"))) {
    return(normalizePath(env_dir, mustWork = TRUE))
  }
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg)) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE)))
  }
  normalizePath("usecases", mustWork = FALSE)
}

usecase_repo_root <- function() {
  normalizePath(file.path(usecase_script_dir(), ".."), mustWork = TRUE)
}

agwise_tmp_dir <- function() {
  tmp_dir <- Sys.getenv("AGWISE_TMPDIR", unset = "/Volumes/T7/tmp")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  normalizePath(tmp_dir, mustWork = FALSE)
}

parse_usecase_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--")) {
      out[[".positionals"]] <- c(out[[".positionals"]], key)
      i <- i + 1L
      next
    }
    name <- sub("^--", "", key)
    if (name %in% c(
      "dry-run", "force-download", "skip-dssat", "format-zones",
      "overwrite", "no-wrapper", "no-folders", "create-dssat-weather-files"
    )) {
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

strip_yaml_comment <- function(line) {
  sub("[[:space:]]+#.*$", "", line)
}

parse_yaml_scalar <- function(value) {
  value <- trimws(value)
  if (!nzchar(value)) return("")
  if (grepl('^".*"$', value) || grepl("^'.*'$", value)) {
    return(substr(value, 2, nchar(value) - 1))
  }
  lower <- tolower(value)
  if (lower %in% c("true", "false")) return(identical(lower, "true"))
  if (lower %in% c("null", "na")) return(NULL)
  numeric_value <- suppressWarnings(as.numeric(value))
  if (!is.na(numeric_value) && grepl("^-?[0-9]+([.][0-9]+)?$", value)) {
    return(numeric_value)
  }
  value
}

read_usecase_yaml <- function(path) {
  path <- normalizePath(path, mustWork = TRUE)
  lines <- readLines(path, warn = FALSE)
  out <- list()
  current_key <- NULL

  for (line in lines) {
    line <- strip_yaml_comment(line)
    if (!nzchar(trimws(line))) next

    if (grepl("^[[:space:]]+-[[:space:]]+", line)) {
      if (is.null(current_key)) stop("YAML list item without a key in: ", path)
      value <- sub("^[[:space:]]+-[[:space:]]+", "", line)
      out[[current_key]] <- c(out[[current_key]], list(parse_yaml_scalar(value)))
      next
    }

    if (!grepl("^[A-Za-z0-9_]+:", line)) {
      stop("Unsupported YAML line in ", path, ": ", line)
    }

    key <- sub(":.*$", "", line)
    value <- sub("^[A-Za-z0-9_]+:[[:space:]]*", "", line)
    current_key <- key
    if (nzchar(trimws(value))) {
      out[[key]] <- parse_yaml_scalar(value)
      current_key <- NULL
    } else {
      out[[key]] <- list()
    }
  }

  for (key in names(out)) {
    if (is.list(out[[key]])) out[[key]] <- unlist(out[[key]], use.names = FALSE)
  }
  out
}

usecase_config_file <- function(path, repo_root = usecase_repo_root()) {
  candidates <- c(
    path,
    file.path(repo_root, path),
    file.path(repo_root, "usecases", path)
  )
  found <- candidates[file.exists(candidates)][1]
  if (is.na(found)) stop("Use-case config not found: ", path)
  normalizePath(found, mustWork = TRUE)
}

as_cli_vars <- function(x) {
  paste(x, collapse = ",")
}

yaml_value <- function(x) {
  if (is.logical(x)) return(tolower(as.character(x)))
  if (is.numeric(x)) return(as.character(x))
  if (is.na(x) || is.null(x)) return("null")
  if (grepl("[:,#]|^[[:space:]]|[[:space:]]$", x)) return(shQuote(x, type = "sh"))
  x
}

write_usecase_yaml <- function(usecase, path) {
  lines <- character()
  for (key in names(usecase)) {
    value <- usecase[[key]]
    if (length(value) == 0) {
      lines <- c(lines, paste0(key, ":"))
      next
    }
    if (length(value) > 1) {
      lines <- c(lines, paste0(key, ":"))
      lines <- c(lines, paste0("  - ", vapply(value, yaml_value, character(1))))
    } else {
      lines <- c(lines, paste0(key, ": ", yaml_value(value)))
    }
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path)
  normalizePath(path, mustWork = FALSE)
}

dssat_template_dir <- function(repo_root, country, use_case_name, crop) {
  candidates <- c(
    file.path(repo_root, "data", "usecases", paste0("useCase_", country, "_", use_case_name), crop, "DSSAT"),
    file.path(repo_root, "data", "usecases", paste0("useCase_", country, "_", use_case_name), crop, "Landing", "DSSAT")
  )
  found <- candidates[dir.exists(candidates)][1]
  if (is.na(found)) {
    stop(
      "Could not find DSSAT template folder. Expected one of:\n",
      paste(candidates, collapse = "\n")
    )
  }
  normalizePath(found, mustWork = TRUE)
}

read_dssat_variety_options <- function(repo_root, country, use_case_name, crop,
                                       template_file = "planting_date_rec_template.csv") {
  template_dir <- dssat_template_dir(repo_root, country, use_case_name, crop)
  template_path <- file.path(template_dir, template_file)
  if (!file.exists(template_path)) {
    stop("Missing DSSAT template CSV used to list variety options: ", template_path)
  }
  template <- read.csv(template_path, stringsAsFactors = FALSE)
  if (!"INGENO" %in% names(template)) {
    stop("Template CSV must include an INGENO cultivar/variety column: ", template_path)
  }
  name_col <- intersect(c("CNAME", "VARIETY", "Variety", "variety"), names(template))[1]
  if (is.na(name_col)) {
    template$CNAME <- NA_character_
    name_col <- "CNAME"
  }
  options <- unique(template[, c("INGENO", name_col), drop = FALSE])
  names(options) <- c("varietyid", "variety_name")
  options[order(options$varietyid), , drop = FALSE]
}

forecast_init_from_usecase <- function(usecase) {
  lead_months <- as.integer(usecase$lead_months %||% 1)
  season_year <- as.integer(usecase$season_year)
  season_month <- as.integer(usecase$season_start_month)
  total_months <- season_year * 12 + (season_month - 1L) - lead_months
  list(
    year = total_months %/% 12,
    month = (total_months %% 12) + 1L
  )
}

usecase_runner_args <- function(usecase, cli, repo_root) {
  args <- c(
    file.path(repo_root, "main", "Forecast", "run_forecast_to_dssat.R"),
    "--country", usecase$country_code,
    "--season-start-month", as.character(usecase$season_start_month),
    "--season-start-day", as.character(usecase$season_start_day %||% 1),
    "--season-year", as.character(cli[["season-year"]] %||% usecase$season_year),
    "--season-length-months", as.character(usecase$season_length_months),
    "--lead-months", as.character(usecase$lead_months %||% 1),
    "--n-cores", as.character(cli[["n-cores"]] %||% usecase$n_cores %||% 1),
    "--variables", as_cli_vars(usecase$variables %||% c("PRCP", "TMAX", "TMIN", "SRAD")),
    "--base-dir", cli[["base-dir"]] %||% file.path(repo_root, "data"),
    "--py-path", cli[["py-path"]] %||% usecase$py_path %||% "/home/jovyan/.conda-envs/agwise_fcst/bin/python"
  )

  if (isTRUE(usecase$manual_extent)) {
    args <- c(args, "--manual-extent", "--extent", as_cli_vars(usecase$extent))
  }
  if (isTRUE(usecase$skip_dssat) || isTRUE(cli[["skip-dssat"]])) {
    args <- c(args, "--skip-dssat")
  }
  if (isTRUE(usecase$force_download) || isTRUE(cli[["force-download"]])) {
    args <- c(args, "--force-download")
  }
  args
}

run_forecast_usecase <- function(usecase, cli = parse_usecase_args(), repo_root = usecase_repo_root()) {
  if (is.null(usecase$country_code)) stop("usecase$country_code is required.")
  args <- usecase_runner_args(usecase, cli, repo_root)

  message("Use case: ", usecase$name %||% usecase$country_code)
  message("Country: ", usecase$country_code)
  message("Zones: ", paste(usecase$zones %||% "auto/from forecast points", collapse = ", "))
  message("Command: Rscript ", paste(shQuote(args), collapse = " "))

  if (isTRUE(cli[["dry-run"]])) return(invisible(args))

  tmp_dir <- agwise_tmp_dir()
  status <- system2("Rscript", args = args, env = paste0("TMPDIR=", tmp_dir))
  if (!identical(as.integer(status), 0L)) {
    stop("Forecast use case failed with exit status ", status, ": ", usecase$name %||% usecase$country_code)
  }
  invisible(status)
}

format_dssat_zones <- function(usecase, cli = parse_usecase_args(), repo_root = usecase_repo_root()) {
  if (!isTRUE(usecase$create_dssat_weather_files) && !isTRUE(cli[["format-zones"]])) {
    return(invisible(NULL))
  }
  if (isTRUE(cli[["dry-run"]])) {
    zones <- usecase$zones %||% "auto/from forecast manifest"
    message("Dry run: would format DSSAT weather/soil files for zone(s): ", paste(zones, collapse = ", "))
    return(invisible(zones))
  }

  dssat_env <- new.env(parent = globalenv())
  dssat_env$project_root <- repo_root
  sys.source(file.path(repo_root, "main", "DSSAT", "readGeo_CM_zone.R"), envir = dssat_env)

  forecast_path <- file.path(
    repo_root, "data", "countries", usecase$country_code,
    "forecast", "dssat_handoff")
  zones <- usecase$zones
  if (is.null(zones)) {
    manifest <- file.path(forecast_path, "manifest.csv")
    if (!file.exists(manifest)) stop("Missing manifest for zone formatting: ", manifest)
    zones <- read.csv(manifest)$zone
  }

  init <- forecast_init_from_usecase(usecase)
  old_n_cores <- Sys.getenv("AGWISE_N_CORES", unset = NA_character_)
  requested_n_cores <- cli[["n-cores"]] %||% usecase$n_cores %||% 1
  Sys.setenv(AGWISE_N_CORES = as.character(requested_n_cores))
  on.exit({
    if (is.na(old_n_cores)) {
      Sys.unsetenv("AGWISE_N_CORES")
    } else {
      Sys.setenv(AGWISE_N_CORES = old_n_cores)
    }
  }, add = TRUE)

  for (zone in zones) {
    message("Formatting DSSAT weather/soil files for zone: ", zone)
    dssat_env$readGeo_CM_zone(
      country = usecase$country_name,
      useCaseName = usecase$use_case_name,
      Crop = usecase$crop,
      project_root = repo_root,
      AOI = TRUE,
      season = usecase$season %||% 1,
      zone = zone,
      level2 = usecase$level2 %||% NA,
      varietyid = usecase$varietyid %||% "999993",
      pathIn_zone = TRUE,
      Depth = usecase$soil_depths %||% c(5, 15, 30, 60, 100, 200),
      Forecast = TRUE,
      fc_month = init$month,
      fc_year = init$year,
      forecast_pathIn = forecast_path
    )
  }
  if (requireNamespace("future", quietly = TRUE)) future::plan(future::sequential)
  invisible(zones)
}

run_usecase <- function(usecase) {
  cli <- parse_usecase_args()
  run_forecast_usecase(usecase, cli = cli)
  format_dssat_zones(usecase, cli = cli)
  invisible(usecase)
}

run_usecase_config <- function(config_path) {
  cli <- parse_usecase_args()
  repo_root <- usecase_repo_root()
  config_path <- usecase_config_file(config_path, repo_root)
  usecase <- read_usecase_yaml(config_path)
  run_forecast_usecase(usecase, cli = cli, repo_root = repo_root)
  format_dssat_zones(usecase, cli = cli, repo_root = repo_root)
  invisible(usecase)
}
