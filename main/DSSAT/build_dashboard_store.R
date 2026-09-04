#!/usr/bin/env Rscript
###############################################################################
# Script: build_dashboard_store.R
# Purpose: Consolidate every per-country/crop DSSAT dashboard extract already
#          produced by the existing pipeline (get_pdate_cultivar_recommendation
#          .R's build_crop_dashboard(), which writes
#          "<Crop>_<Country>_dashboard_data.RDS" next to each crop's results)
#          into ONE partitioned local Parquet dataset that dashboard_app/
#          queries directly.
#
#          Why Parquet instead of just reading the RDS files in the app: the
#          old crosstalk-based HTML dashboards had to embed every row for
#          every linked widget in the browser (Zambia Maize: 231k rows -> a
#          152 MB HTML that freezes on open). Parquet + arrow lets the Shiny
#          app push filtering (country/crop/rank/cultivar) down to a
#          columnar scan and pull only the small matching subset into R/the
#          browser, no matter how many countries/crops accumulate in the
#          store over time. Partitioned by country/crop/usecase (Hive-style
#          subfolders) so the app can prune to one partition's files instead
#          of scanning everything, and so distinct runs of the same
#          country+crop (e.g. Rwanda's several seasonal usecases) don't get
#          silently merged into one indistinguishable bucket.
#
#          Re-run any time a usecase's dashboard data changes; this always
#          rebuilds the whole store from scratch (source RDS files are small
#          and cheap to re-scan) rather than updating partitions in place.
#
#          Every successful run also repackages the laptop bundle (see
#          package_dashboard_app_for_laptop.R) from the store just built, so
#          the two never drift apart - pass --skip-bundle to build only the
#          store (e.g. while iterating on the store itself, before caring
#          about the laptop artifact).
#
# Usage:
#   Rscript main/DSSAT/build_dashboard_store.R [--include-test] [--usecases <name1,name2,...>] [--skip-bundle]
#
#   --include-test  Also ingest usecase directories with "test" in their name
#                    (skipped by default - they're dev-only stub runs, not
#                    real per-country results, and some share a country+crop
#                    with a "_full" run under an un-suffixed filename that
#                    would otherwise collide with it).
#
#   --usecases      Comma-separated list of usecase DIRECTORY BASENAMES (as
#                    they appear under data/usecases/, e.g.
#                    useCase_Nigeria_full,useCase_Kenya_full - not bare
#                    suffixes, since e.g. "full" alone is ambiguous across
#                    countries) to restrict ingestion to exactly those
#                    usecases. Lets an old/incomplete/pre-merge usecase
#                    (e.g. Nigeria's four leadtime-split usecases once
#                    merge_usecases.R has combined them into
#                    useCase_Nigeria_full) be excluded from the dashboard
#                    without deleting it from disk. When given, this is an
#                    explicit allowlist and bypasses --include-test's
#                    name-based filtering entirely. Omit to ingest every
#                    usecase found (current default behavior).
#
#   --skip-bundle   Don't repackage the laptop bundle after building the
#                    store (it's regenerated automatically otherwise).
###############################################################################

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

cmd <- commandArgs(FALSE)
file_arg <- grep("^--file=", cmd, value = TRUE)
script_dir <- if (length(file_arg)) {
  dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE))
} else {
  normalizePath(".", mustWork = TRUE)
}
repo_root <- normalizePath(file.path(script_dir, "..", ".."), mustWork = TRUE)

cli_args <- commandArgs(trailingOnly = TRUE)
include_test <- "--include-test" %in% cli_args

usecases_flag_idx <- which(cli_args == "--usecases")
usecases_filter <- if (length(usecases_flag_idx) == 1L && usecases_flag_idx < length(cli_args)) {
  trimws(strsplit(cli_args[[usecases_flag_idx + 1L]], ",")[[1]])
} else {
  NULL
}

usecases_dir <- file.path(repo_root, "data", "usecases")
# data/usecases/results/ is this repo's existing spot for cross-country
# shareable output (per-country/crop dashboard HTML and PNGs are already
# hand-collected there) - the consolidated store belongs alongside those,
# not in a new top-level data/ folder of its own.
store_dir <- file.path(repo_root, "data", "usecases", "results", "dashboard_store")

### Derive crop/country/usecase for one dashboard_data.RDS path from its
### location (.../usecases/<usecase_dir>/<Crop>/result/DSSAT/AOI/<file>) and,
### where possible, from the "<Crop>_<Country>_dashboard_data.RDS" naming
### build_crop_dashboard() already produces (see get_pdate_cultivar_recommend
### ation.R) - falling back to parsing the usecase directory name (handling
# both "useCase_<Country>_<variant>" and "results_<ISO3>_<variant>" spellings
# seen across this repo's usecases) when a file was written before that
# country-suffixed naming existed.
resolve_metadata <- function(file_path) {
  crop_dir <- dirname(dirname(dirname(dirname(file_path))))
  crop <- basename(crop_dir)
  usecase_dir <- basename(dirname(crop_dir))

  fname_stem <- sub("_dashboard_data\\.RDS$", "", basename(file_path))
  prefix <- paste0(crop, "_")
  country <- if (startsWith(fname_stem, prefix) && nchar(fname_stem) > nchar(prefix)) {
    gsub("_", " ", substring(fname_stem, nchar(prefix) + 1L))
  } else {
    token <- sub("^(useCase_|results_)", "", usecase_dir)
    first_tok <- strsplit(token, "_")[[1]][1]
    if (grepl("^[A-Z]{3}$", first_tok)) {
      nm <- suppressWarnings(countrycode::countrycode(first_tok, "iso3c", "country.name"))
      if (!is.na(nm)) first_tok <- nm
    }
    first_tok
  }

  list(crop = crop, country = country, usecase = usecase_dir)
}

### Find every "<usecase>/<Crop>/result/DSSAT/AOI/*_dashboard_data.RDS" file
### WITHOUT any recursive directory walk - each usecase/crop also has a
### transform/ subtree with one folder per simulated grid point per variety
### (tens of thousands of small DSSAT I/O files per country), so
### list.files(..., recursive = TRUE) over the whole usecases_dir has to walk
### that entire per-point tree just to find a handful of small dashboard
### files 3 fixed path segments below each usecase dir. Listing only the
### known-shape path directly (usecase dirs -> their crop subdirs -> that
### crop's own result/DSSAT/AOI/) never touches transform/ at all.
if (!is.null(usecases_filter)) {
  usecase_dirs <- file.path(usecases_dir, usecases_filter)
  not_found <- usecases_filter[!dir.exists(usecase_dirs)]
  if (length(not_found) > 0) {
    stop(
      "--usecases named director(ies) not found under ", usecases_dir, ":\n  ",
      paste(not_found, collapse = "\n  "))
  }
  message("--usecases given - restricting to: ", paste(usecases_filter, collapse = ", "))
} else {
  usecase_dirs <- list.dirs(usecases_dir, recursive = FALSE, full.names = TRUE)
}
all_files <- character(0)
for (usecase_dir in usecase_dirs) {
  crop_dirs <- list.dirs(usecase_dir, recursive = FALSE, full.names = TRUE)
  for (crop_dir in crop_dirs) {
    aoi_dir <- file.path(crop_dir, "result", "DSSAT", "AOI")
    if (!dir.exists(aoi_dir)) next
    all_files <- c(all_files, list.files(
      aoi_dir, pattern = "_dashboard_data\\.RDS$", full.names = TRUE))
  }
}

if (is.null(usecases_filter) && !include_test) {
  all_files <- all_files[!grepl("test", all_files, ignore.case = TRUE)]
}

if (length(all_files) == 0) {
  stop("No *_dashboard_data.RDS files found under ", usecases_dir)
}

message("Found ", length(all_files), " dashboard data file(s) to ingest.")

standard_cols <- c(
  "XLAT", "LONG", "zone", "Cultivar", "TRNO", "PDAT", "HWAH", "CWAM", "WUE",
  "maturity_failed", "Date_Rank", "Combination_Rank", "in_crop_mask", "row_key")

seen_keys <- character(0)
chunks <- vector("list", length(all_files))

for (i in seq_along(all_files)) {
  f <- all_files[[i]]
  meta <- resolve_metadata(f)
  key <- paste(meta$country, meta$crop, meta$usecase, sep = " / ")
  if (key %in% seen_keys) {
    stop(
      "Duplicate (country, crop, usecase) combination while ingesting ", f,
      " - already saw ", key, " from another file. Resolve which one is ",
      "current before re-running.")
  }
  seen_keys <- c(seen_keys, key)

  dat <- readRDS(f)
  missing_cols <- setdiff(standard_cols, names(dat))
  if (length(missing_cols) > 0) {
    warning("Skipping ", f, " - missing expected column(s): ", paste(missing_cols, collapse = ", "))
    next
  }

  dat <- dat[, standard_cols]
  dat$PDAT <- as.Date(dat$PDAT)
  dat$country <- meta$country
  dat$crop <- meta$crop
  dat$usecase <- meta$usecase
  message(sprintf(
    "  %-30s %-10s %-24s %7d rows (%d grid points)", meta$country, meta$crop,
    meta$usecase, nrow(dat), nrow(unique(dat[, c("XLAT", "LONG")]))))
  chunks[[i]] <- dat
}

combined <- dplyr::bind_rows(chunks)
message(
  "\nTotal: ", nrow(combined), " rows across ", length(unique(combined$country)),
  " countries and ", nrow(unique(combined[, c("country", "crop")])), " country-crop combinations.")

if (dir.exists(store_dir)) unlink(store_dir, recursive = TRUE)
dir.create(store_dir, recursive = TRUE)

arrow::write_dataset(
  combined, path = store_dir, format = "parquet",
  partitioning = c("country", "crop", "usecase"))

message("\nDashboard store written to: ", store_dir)
message("Run the app with: shiny::runApp('main/DSSAT/dashboard_app')")

### Repackage the laptop bundle from the store just built, so the bundle
### zip a colleague downloads is never left pointing at a stale store - runs
### as a fresh Rscript subprocess (not sourced) so it resolves its own
### repo_root/script_dir independently, exactly as it would run standalone.
if ("--skip-bundle" %in% cli_args) {
  message("\n--skip-bundle given - not repackaging the laptop bundle.")
} else {
  message("\nRepackaging laptop bundle...")
  bundle_script <- file.path(script_dir, "package_dashboard_app_for_laptop.R")
  status <- system2("Rscript", shQuote(bundle_script))
  if (!identical(status, 0L)) {
    warning(
      "package_dashboard_app_for_laptop.R exited with status ", status,
      " - the dashboard store was built successfully, but the laptop ",
      "bundle may now be stale or missing. Re-run it directly: Rscript ",
      bundle_script)
  }
}
