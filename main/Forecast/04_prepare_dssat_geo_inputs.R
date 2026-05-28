#!/usr/bin/env Rscript
###############################################################################
# Script: 04_prepare_dssat_geo_inputs.R
# Purpose: Prepare AgWISE forecast point-data RDS files for readGeo_CM_zone.R.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
#
# This is the bridge between the climate forecast pipeline and the existing
# DSSAT formatter. It samples daily bias-corrected forecast NetCDF files at the
# crop-model/soil points and writes the RDS files expected by readGeo_CM_zone.R:
#
#   Rainfall_Season_1_PointData_AOI.RDS
#   temperatureMax_Season_1_PointData_AOI.RDS
#   temperatureMin_Season_1_PointData_AOI.RDS
#   solarRadiation_Season_1_PointData_AOI.RDS
#   SoilDEM_PointData_AOI_profile.RDS
#
# Default output:
#   data/countries/<ISO3>/forecast/dssat_handoff/
###############################################################################

suppressPackageStartupMessages({
  library(jsonlite)
  library(terra)
})

parse_args <- function(args) {
  out <- list()
  i <- 1
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--")) {
      stop("Unexpected argument: ", key)
    }
    name <- sub("^--", "", key)
    if (name %in% c("overwrite", "allow-invalid")) {
      out[[name]] <- TRUE
      i <- i + 1
    } else {
      if (i == length(args)) stop("Missing value for ", key)
      out[[name]] <- args[[i + 1]]
      i <- i + 2
    }
  }
  out
}

get_arg <- function(args, name, default = NULL) {
  value <- args[[name]]
  if (is.null(value)) default else value
}

normalize_points <- function(df) {
  if ("lon" %in% names(df) && !"longitude" %in% names(df)) names(df)[names(df) == "lon"] <- "longitude"
  if ("lat" %in% names(df) && !"latitude" %in% names(df)) names(df)[names(df) == "lat"] <- "latitude"
  if (!all(c("longitude", "latitude") %in% names(df))) {
    stop("Soil/crop-model points must contain lon/lat or longitude/latitude columns")
  }
  if (!"NAME_1" %in% names(df)) df$NAME_1 <- "Forecast"
  if (!"NAME_2" %in% names(df)) df$NAME_2 <- "Forecast"
  df
}

drop_incomplete_soil <- function(soil, zone) {
  complete <- complete.cases(soil)
  if (!all(complete)) {
    message("Dropping ", sum(!complete), " incomplete soil point(s) for zone ", zone)
    soil <- soil[complete, , drop = FALSE]
  }
  if (nrow(soil) < 1) {
    stop("No complete soil points remain for zone ", zone)
  }
  soil
}

load_country_config <- function(config_path) {
  cfg_all <- read_json(config_path, simplifyVector = TRUE)
  if (length(cfg_all) < 1) stop("Invalid config: ", config_path)
  country_code <- names(cfg_all)[1]
  list(country_code = country_code, cfg = cfg_all[[country_code]])
}

forecast_path <- function(cfg, model_id, forecast_year, var_code) {
  file.path(
    cfg$dir_bc_fcst,
    sprintf("%s_daily_%s_forecast_BC_%s.nc", var_code, model_id, forecast_year)
  )
}

read_forecast_raster <- function(path, var_code, allow_invalid = FALSE) {
  if (!file.exists(path)) stop("Missing bias-corrected forecast: ", path)
  r <- rast(path)
  dates <- as.Date(time(r))
  if (any(is.na(dates))) stop("Forecast has missing/invalid time coordinate: ", path)

  limits <- list(
    PRCP = c(0, 500),
    TMAX = c(-50, 70),
    TMIN = c(-60, 60),
    SRAD = c(0, 40)
  )
  lim <- limits[[var_code]]
  stats <- terra::global(r, fun = range, na.rm = TRUE)
  found_min <- min(stats[, 1], na.rm = TRUE)
  found_max <- max(stats[, 2], na.rm = TRUE)
  if (!allow_invalid && (found_min < lim[1] || found_max > lim[2])) {
    stop(sprintf(
      "%s range %.3f to %.3f is outside expected %.1f to %.1f. Regenerate/fix forecasts before DSSAT handoff.",
      var_code, found_min, found_max, lim[1], lim[2]
    ))
  }

  list(raster = r, dates = dates)
}

sample_variable <- function(r, dates, points, variable_prefix, common_dates) {
  keep <- match(common_dates, dates)
  if (any(is.na(keep))) stop("Internal date matching error for ", variable_prefix)
  rr <- r[[keep]]
  values <- terra::extract(rr, points[, c("longitude", "latitude")], ID = FALSE)
  names(values) <- paste0(variable_prefix, "_", format(common_dates, "%Y-%m-%d"))
  missing <- !is.finite(as.matrix(values))
  if (any(missing)) {
    stop(sprintf(
      "%s sampling produced %s missing/non-finite value(s). Check point locations against the forecast grid/mask before DSSAT handoff.",
      variable_prefix, sum(missing)
    ))
  }
  values
}

write_variable_rds <- function(path, meta, values, overwrite) {
  if (file.exists(path) && !isTRUE(overwrite)) {
    stop("Output exists; use --overwrite to replace: ", path)
  }
  saveRDS(cbind(meta, values), path)
}

validate_points_in_extent <- function(points, r, zone) {
  e <- terra::ext(r)
  outside <- points_outside_extent(points, r)
  if (any(outside)) {
    stop(sprintf(
      "Zone %s has %s point(s) outside the forecast grid extent lon %.3f..%.3f, lat %.3f..%.3f. Point lon range %.3f..%.3f, lat range %.3f..%.3f.",
      zone,
      sum(outside),
      e$xmin, e$xmax, e$ymin, e$ymax,
      min(points$longitude, na.rm = TRUE), max(points$longitude, na.rm = TRUE),
      min(points$latitude, na.rm = TRUE), max(points$latitude, na.rm = TRUE)
    ))
  }
}

points_outside_extent <- function(points, r) {
  e <- terra::ext(r)
  points$longitude < e$xmin | points$longitude > e$xmax |
    points$latitude < e$ymin | points$latitude > e$ymax
}

filter_soil_files_to_forecast_extent <- function(soil_files, r, source_label) {
  valid <- character()
  for (soil_file in soil_files) {
    zone <- basename(dirname(soil_file))
    soil <- normalize_points(readRDS(soil_file))
    soil <- drop_incomplete_soil(soil, zone)
    points <- unique(soil[, c("longitude", "latitude", "NAME_1", "NAME_2")])
    outside <- points_outside_extent(points, r)
    if (all(outside)) {
      message("Skipping soil zone outside forecast grid: ", zone, " (", source_label, ")")
      next
    }
    if (any(outside)) {
      validate_points_in_extent(points, r, zone)
    }
    valid <- c(valid, soil_file)
  }
  unique(valid)
}

fix_temperature_order <- function(zone_values, zone) {
  tmax <- as.matrix(zone_values$TMAX)
  tmin <- as.matrix(zone_values$TMIN)
  bad <- tmax < tmin
  if (any(bad)) {
    message("  -> Zone ", zone, ": swapping ", sum(bad), " daily TMAX/TMIN pair(s) where TMAX < TMIN")
    zone_values$TMAX[,] <- ifelse(bad, tmin, tmax)
    zone_values$TMIN[,] <- ifelse(bad, tmax, tmin)
  }
  zone_values
}

main <- function() {
  args <- parse_args(commandArgs(trailingOnly = TRUE))
  config_path <- get_arg(args, "config")
  if (is.null(config_path)) stop("Usage: 04_prepare_dssat_geo_inputs.R --config <config.json> [--overwrite]")

  loaded <- load_country_config(config_path)
  cfg <- loaded$cfg
  model_id <- get_arg(args, "model-id", "ecmwf51")
  season <- as.integer(get_arg(args, "season", "1"))
  forecast_year <- as.integer(get_arg(args, "forecast-year", cfg$forecast_year))
  allow_invalid <- isTRUE(args[["allow-invalid"]])
  overwrite <- isTRUE(args[["overwrite"]])

  soil_dir <- get_arg(
    args, "soil-dir",
    if (!is.null(cfg$dir_geo_cropmodel)) {
      cfg$dir_geo_cropmodel
    } else {
      file.path(cfg$dir_s2s, "forecast", "geo_4cropModel")
    }
  )
  output_dir <- get_arg(
    args, "output-dir",
    if (!is.null(cfg$dir_dssat_handoff)) {
      cfg$dir_dssat_handoff
    } else {
      file.path(cfg$dir_s2s, "forecast", "dssat_handoff")
    }
  )

  specs <- list(
    PRCP = list(prefix = "Rainfall", file = sprintf("Rainfall_Season_%s_PointData_AOI.RDS", season)),
    TMAX = list(prefix = "temperatureMax", file = sprintf("temperatureMax_Season_%s_PointData_AOI.RDS", season)),
    TMIN = list(prefix = "temperatureMin", file = sprintf("temperatureMin_Season_%s_PointData_AOI.RDS", season)),
    SRAD = list(prefix = "solarRadiation", file = sprintf("solarRadiation_Season_%s_PointData_AOI.RDS", season))
  )

  forecasts <- lapply(names(specs), function(var_code) {
    read_forecast_raster(
      forecast_path(cfg, model_id, forecast_year, var_code),
      var_code,
      allow_invalid = allow_invalid
    )
  })
  names(forecasts) <- names(specs)

  common_dates <- Reduce(intersect, lapply(forecasts, `[[`, "dates"))
  common_dates <- sort(as.Date(common_dates, origin = "1970-01-01"))
  if (length(common_dates) < 1) stop("No common forecast dates across PRCP/TMAX/TMIN/SRAD")

  soil_files <- list.files(soil_dir, pattern = "^SoilDEM_PointData_AOI_profile\\.RDS$", recursive = TRUE, full.names = TRUE)
  if (length(soil_files) < 1) stop("No SoilDEM_PointData_AOI_profile.RDS files found under: ", soil_dir)
  soil_files <- filter_soil_files_to_forecast_extent(soil_files, forecasts$PRCP$raster, soil_dir)
  if (length(soil_files) < 1) {
    fallback_soil_root <- file.path(cfg$dir_s2s, "forecast")
    message(
      "No soil point files in the configured folder overlap the forecast grid. ",
      "Searching for forecast-overlapping soil points under: ", fallback_soil_root
    )
    fallback_files <- list.files(
      fallback_soil_root,
      pattern = "^SoilDEM_PointData_AOI_profile\\.RDS$",
      recursive = TRUE,
      full.names = TRUE
    )
    output_dir_norm <- normalizePath(output_dir, mustWork = FALSE)
    output_dir_child_prefix <- paste0(output_dir_norm, .Platform$file.sep)
    fallback_files_norm <- normalizePath(fallback_files, mustWork = FALSE)
    fallback_files <- fallback_files[
      !(fallback_files_norm == output_dir_norm | startsWith(fallback_files_norm, output_dir_child_prefix))
    ]
    soil_files <- filter_soil_files_to_forecast_extent(
      fallback_files, forecasts$PRCP$raster, fallback_soil_root
    )
  }
  if (length(soil_files) < 1) {
    stop(
      "No soil point files overlap the forecast grid. Check --soil-dir or regenerate ",
      "geo_4cropModel inputs for this country/domain."
    )
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  manifest <- data.frame()

  for (soil_file in soil_files) {
    zone <- basename(dirname(soil_file))
    out_zone <- file.path(output_dir, zone)
    dir.create(out_zone, recursive = TRUE, showWarnings = FALSE)

    soil <- normalize_points(readRDS(soil_file))
    soil <- drop_incomplete_soil(soil, zone)
    points <- unique(soil[, c("longitude", "latitude", "NAME_1", "NAME_2")])
    validate_points_in_extent(points, forecasts$PRCP$raster, zone)
    points$startingDate <- min(common_dates)
    points$endDate <- max(common_dates)
    meta <- points[, c("longitude", "latitude", "startingDate", "endDate", "NAME_1", "NAME_2")]
    meta$ID <- seq_len(nrow(meta))
    meta <- meta[, c("longitude", "latitude", "startingDate", "endDate", "ID", "NAME_1", "NAME_2")]

    zone_values <- list()
    for (var_code in names(specs)) {
      zone_values[[var_code]] <- sample_variable(
        forecasts[[var_code]]$raster,
        forecasts[[var_code]]$dates,
        points,
        specs[[var_code]]$prefix,
        common_dates
      )
    }
    zone_values <- fix_temperature_order(zone_values, zone)

    for (var_code in names(specs)) {
      out_file <- file.path(out_zone, specs[[var_code]]$file)
      write_variable_rds(out_file, meta, zone_values[[var_code]], overwrite)
    }

    soil_out <- file.path(out_zone, "SoilDEM_PointData_AOI_profile.RDS")
    if (file.exists(soil_out) && !overwrite) stop("Output exists; use --overwrite to replace: ", soil_out)
    saveRDS(soil, soil_out)

    manifest <- rbind(
      manifest,
      data.frame(
        zone = zone,
        points = nrow(points),
        start_date = min(common_dates),
        end_date = max(common_dates),
        output_dir = out_zone,
        stringsAsFactors = FALSE
      )
    )
  }

  write.csv(manifest, file.path(output_dir, "manifest.csv"), row.names = FALSE)
  message(
    "Prepared DSSAT geo RDS inputs for readGeo_CM_zone.R: ",
    nrow(manifest), " zone(s), ", sum(manifest$points), " point(s), ",
    length(common_dates), " daily timesteps. Output: ", output_dir
  )
}

main()
