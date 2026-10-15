#!/usr/bin/env Rscript
# Summarise DSSAT results for the grid cells around one location, using
# the same location registry as the Python integration scripts.
#
# Usage:
#   Rscript integration/local_summary.R --location Chokwe --results-dir <dir>
#   Rscript integration/local_summary.R --lat -24.500676 --lon 33.001806 --results-dir <dir>
#
# Options (all --key value, in any order):
#   --results-dir DIR      Directory holding ISRIC_*_AOI_season_1[_cropmask].RDS (required)
#   --location NAME        Location name to look up in --locations-file
#   --lat LAT              Latitude, used instead of or to override --location
#   --lon LON              Longitude, used instead of or to override --location
#   --radius-km KM         Search radius in kilometres (default: 15)
#   --cropmask yes|no      Prefer the crop-masked results file if present (default: yes)
#   --locations-file PATH  JSON location registry (default: integration/locations.json)
#   --output PATH          Output CSV path (default: derived from location and radius)

suppressPackageStartupMessages({
  library(dplyr)
})

# ---- argument parsing -------------------------------------------------

parse_args <- function(args) {
  opts <- list(
    `results-dir` = NULL, location = NULL, lat = NULL, lon = NULL,
    `radius-km` = "15", cropmask = "yes",
    `locations-file` = file.path("integration", "locations.json"),
    output = NULL
  )
  i <- 1
  while (i <= length(args)) {
    key <- sub("^--", "", args[i])
    if (!(key %in% names(opts))) {
      stop("Unknown option: --", key)
    }
    if (i == length(args)) {
      stop("Option --", key, " needs a value")
    }
    opts[[key]] <- args[i + 1]
    i <- i + 2
  }
  opts
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0 || "--help" %in% args || "-h" %in% args) {
  cat(
    "Usage: Rscript integration/local_summary.R --location Chokwe --results-dir <dir> [options]\n",
    "   or: Rscript integration/local_summary.R --lat -24.5 --lon 33.0 --results-dir <dir> [options]\n\n",
    "Options:\n",
    "  --results-dir DIR      Directory with ISRIC_*_AOI_season_1[_cropmask].RDS (required)\n",
    "  --location NAME        Look up coordinates in --locations-file\n",
    "  --lat LAT --lon LON    Coordinates, instead of or to override --location\n",
    "  --radius-km KM         Search radius in km (default 15)\n",
    "  --cropmask yes|no      Prefer the crop-masked file if present (default yes)\n",
    "  --locations-file PATH  JSON registry (default integration/locations.json)\n",
    "  --output PATH          Output CSV path (default auto-generated)\n",
    sep = ""
  )
  quit(status = 0)
}
opts <- parse_args(args)

if (is.null(opts[["results-dir"]])) {
  stop("--results-dir is required")
}
if (!dir.exists(opts[["results-dir"]])) {
  stop("--results-dir does not exist: ", opts[["results-dir"]])
}

# ---- resolve location ---------------------------------------------------

resolve_location <- function(opts) {
  lat <- opts$lat
  lon <- opts$lon
  name <- opts$location

  if (!is.null(name) && (is.null(lat) || is.null(lon))) {
    if (!file.exists(opts[["locations-file"]])) {
      stop(
        "--location was given but the locations file was not found: ",
        opts[["locations-file"]], ". Provide --lat and --lon instead."
      )
    }
    if (!requireNamespace("jsonlite", quietly = TRUE)) {
      stop(
        "--location requires the jsonlite package. Install it with: ",
        "install.packages('jsonlite'), or provide --lat and --lon instead."
      )
    }
    registry <- jsonlite::fromJSON(opts[["locations-file"]])
    key <- tolower(name)
    if (!(key %in% names(registry))) {
      stop(
        "Location '", name, "' is not registered. Available: ",
        paste(sort(names(registry)), collapse = ", ")
      )
    }
    record <- registry[[key]]
    if (is.null(lat)) lat <- record$latitude
    if (is.null(lon)) lon <- record$longitude
  }

  if (is.null(lat) || is.null(lon)) {
    stop("Provide --location (with --locations-file present) or both --lat and --lon.")
  }
  list(
    name = if (!is.null(name)) name else paste0(lat, "_", lon),
    lat = as.numeric(lat),
    lon = as.numeric(lon)
  )
}

location <- resolve_location(opts)
radius_km <- as.numeric(opts[["radius-km"]])
prefer_cropmask <- tolower(opts$cropmask) %in% c("yes", "true", "1")

# ---- find the results file ----------------------------------------------

find_results_file <- function(results_dir, prefer_cropmask) {
  cropmask_files <- Sys.glob(file.path(results_dir, "ISRIC_*_AOI_season_1_cropmask.RDS"))
  plain_files <- Sys.glob(file.path(results_dir, "ISRIC_*_AOI_season_1.RDS"))

  if (prefer_cropmask && length(cropmask_files) > 0) {
    if (length(cropmask_files) > 1) {
      message("Multiple crop-masked files found, using the first: ", cropmask_files[1])
    }
    return(list(path = cropmask_files[1], masked = TRUE))
  }
  if (length(plain_files) > 0) {
    if (prefer_cropmask) {
      message("No crop-masked file found; falling back to the unmasked results.")
    }
    if (length(plain_files) > 1) {
      message("Multiple results files found, using the first: ", plain_files[1])
    }
    return(list(path = plain_files[1], masked = FALSE))
  }
  stop("No ISRIC_*_AOI_season_1[.RDS|_cropmask.RDS] file found in ", results_dir)
}

found <- find_results_file(opts[["results-dir"]], prefer_cropmask)
message(
  "Using ", if (found$masked) "crop-masked" else "unmasked", " results file: ", found$path
)

# ---- default output path -------------------------------------------------

if (is.null(opts$output)) {
  safe_name <- gsub("[^A-Za-z0-9_-]", "_", location$name)
  suffix <- if (found$masked) "cropmask" else "nomask"
  opts$output <- file.path(
    "integration", "examples",
    sprintf("%s_local_summary_%gkm_%s.csv", tolower(safe_name), radius_km, suffix)
  )
}
if (!dir.exists(dirname(opts$output))) {
  dir.create(dirname(opts$output), recursive = TRUE)
}

# ---- summarise --------------------------------------------------------

haversine_km <- function(lat1, lon1, lat2, lon2) {
  rad <- pi / 180
  a <- sin((lat2 - lat1) * rad / 2)^2 +
    cos(lat1 * rad) * cos(lat2 * rad) * sin((lon2 - lon1) * rad / 2)^2
  2 * 6371 * asin(sqrt(a))
}

df <- readRDS(found$path)
df$dist_km <- haversine_km(location$lat, location$lon, df$XLAT, df$LONG)
local <- df[df$dist_km <= radius_km, ]
if (nrow(local) == 0) {
  stop("No grid cells within ", radius_km, " km of ", location$name, ".")
}

n_cells <- nrow(distinct(local, XLAT, LONG))
message(
  n_cells, " grid cells within ", radius_km, " km of ", location$name,
  " (nearest: ", round(min(local$dist_km), 1), " km)"
)
if (n_cells < 5) {
  message("Warning: fewer than 5 cells, so the percentiles are rough.")
}

local$pdate <- as.Date(local$PDAT)

summary_df <- local %>%
  group_by(Cultivar, TRNO) %>%
  summarise(
    PDAT = as.character(min(pdate)),
    pdat_span_days = as.numeric(max(pdate) - min(pdate)),
    n_simulations = n(),
    maturity_failure_rate_pct = sum(is.na(MDAT)) / n() * 100,
    across(
      c(HWAH, CWAM),
      list(
        mean = ~ mean(.x, na.rm = TRUE),
        median = ~ median(.x, na.rm = TRUE),
        sd = ~ sd(.x, na.rm = TRUE),
        cv_pct = ~ sd(.x, na.rm = TRUE) / mean(.x, na.rm = TRUE) * 100,
        p10 = ~ quantile(.x, 0.10, na.rm = TRUE, names = FALSE),
        p90 = ~ quantile(.x, 0.90, na.rm = TRUE, names = FALSE)
      ),
      .names = "{.col}_{.fn}"
    ),
    .groups = "drop"
  ) %>%
  arrange(desc(HWAH_median))

if (any(summary_df$pdat_span_days > 0)) {
  message(
    "Warning: some groups span more than one calendar day; the merge across ",
    "shifted planting dates may need review."
  )
}

write.csv(summary_df, opts$output, row.names = FALSE)
print(as.data.frame(summary_df[, c("PDAT", "pdat_span_days", "n_simulations",
                                   "HWAH_median", "HWAH_p10", "HWAH_p90")]))
message("Wrote ", opts$output)