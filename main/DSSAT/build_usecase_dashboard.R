#!/usr/bin/env Rscript
###############################################################################
# Script: build_usecase_dashboard.R
# Purpose: Build a self-contained, shareable HTML dashboard per crop for a
#          usecase (e.g. useCase_Rwanda_rab). One HTML per crop, not one
#          combined file - crosstalk's filter widgets can't force a
#          non-empty single selection (clearing a "Crop" dropdown would
#          always fall back to showing every crop at once), so separate
#          per-crop files are the reliable way to make crops mutually
#          exclusive alternatives. This also keeps each file's payload to
#          just its own crop instead of every crop combined.
#          Standalone - run manually after some crops have finished; not
#          wired into run_dssat_pipeline.R.
#
# Example:
#   Rscript main/DSSAT/build_usecase_dashboard.R \
#     --usecase-dir data/usecases/useCase_Rwanda_rab \
#     --country-name Rwanda
###############################################################################

parse_args <- function(args) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
    name <- sub("^--", "", key)
    if (i == length(args)) stop("Missing value for ", key)
    out[[name]] <- args[[i + 1L]]
    i <- i + 2L
  }
  out
}

arg <- function(args, name, default = NULL) {
  value <- args[[name]]
  if (is.null(value)) default else value
}

cmd <- commandArgs(FALSE)
file_arg <- grep("^--file=", cmd, value = TRUE)
script_dir <- if (length(file_arg)) {
  dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE))
} else {
  normalizePath(".", mustWork = TRUE)
}
repo_root <- normalizePath(file.path(script_dir, "..", ".."), mustWork = TRUE)

args <- parse_args(commandArgs(trailingOnly = TRUE))

usecase_dir <- arg(args, "usecase-dir")
country_name <- arg(args, "country-name")
if (is.null(usecase_dir) || is.null(country_name)) {
  stop(
    "Usage: Rscript build_usecase_dashboard.R --usecase-dir <path> ",
    "--country-name <Country>"
  )
}
usecase_dir <- normalizePath(usecase_dir, mustWork = TRUE)

source(file.path(repo_root, "main/DSSAT/00_load_packages.R"))
source(file.path(repo_root, "main/DSSAT/common_helpers.R"))
source(file.path(repo_root, "main/DSSAT/get_pdate_cultivar_recommendation.R"))
suppressPackageStartupMessages(library(dplyr))

crop_mask_dir <- file.path(repo_root, "Landing", "crop_masks")

### Discover crops with finished DSSAT results (any dir ending in
### <Crop>/result/DSSAT/AOI under the usecase folder)
discover_crops <- function(usecase_dir) {
  all_dirs <- list.dirs(usecase_dir, recursive = TRUE, full.names = TRUE)
  aoi_dirs <- all_dirs[grepl("/result/DSSAT/AOI$", all_dirs)]
  crop_names <- vapply(aoi_dirs, function(d) basename(dirname(dirname(dirname(d)))), character(1))
  setNames(aoi_dirs, crop_names)
}

crop_dirs <- discover_crops(usecase_dir)
if (length(crop_dirs) == 0) {
  stop("No crops with result/DSSAT/AOI outputs found under: ", usecase_dir)
}
message("Found crops: ", paste(names(crop_dirs), collapse = ", "))

### Locate the raw merged RDS's base filename (the one merge_DSSAT_output()
### and export_cropmask_full_results() share), excluding the derived files.
find_base_filename <- function(result_dir, crop) {
  candidates <- list.files(result_dir, pattern = "_AOI_season_[0-9]+\\.RDS$")
  candidates <- candidates[!grepl("_cropmask\\.RDS$", candidates)]
  if (length(candidates) == 0) {
    stop("No raw merged RDS found for crop '", crop, "' in ", result_dir)
  }
  sub("\\.RDS$", "", candidates[[1]])
}

### For each crop: load (or build) its dashboard extract, then render its own
### dashboard HTML directly into that crop's result folder, alongside its
### other Step 5 outputs.
for (crop in names(crop_dirs)) {
  result_dir <- crop_dirs[[crop]]
  extract_path <- file.path(result_dir, paste0(crop, "_dashboard_extract.RDS"))

  if (file.exists(extract_path)) {
    message("Loading cached dashboard extract for ", crop)
    dat <- readRDS(extract_path)
  } else {
    message("No cached extract for ", crop, " - building it now")
    base_filename <- find_base_filename(result_dir, crop)
    masked_path <- file.path(result_dir, paste0(base_filename, "_cropmask.RDS"))
    if (!file.exists(masked_path)) {
      raw_path <- file.path(result_dir, paste0(base_filename, ".RDS"))
      results_df <- readRDS(raw_path)
      export_cropmask_full_results(
        results_df = results_df, crop = crop, crop_mask_dir = crop_mask_dir,
        output_dir = result_dir, base_filename = base_filename)
    }
    dat <- build_dashboard_extract(crop = crop, output_dir = result_dir, base_filename = base_filename)
  }

  dat$row_key <- paste(dat$XLAT, dat$LONG, dat$TRNO, dat$Cultivar, sep = "_")
  has_crop_mask <- !is.na(find_crop_mask_file(crop, crop_mask_dir, must_exist = FALSE))

  dashboard_rds_path <- file.path(result_dir, paste0(crop, "_dashboard_data.RDS"))
  saveRDS(dat, dashboard_rds_path)

  rmarkdown::render(
    input = file.path(repo_root, "main/DSSAT/dashboard_template.Rmd"),
    output_file = paste0(crop, "_dashboard.html"),
    output_dir = result_dir,
    params = list(
      data_rds = dashboard_rds_path,
      crop_name = crop,
      country_name = country_name,
      has_crop_mask = has_crop_mask
    ),
    envir = new.env()
  )
  message("Dashboard rendered to: ", file.path(result_dir, paste0(crop, "_dashboard.html")))
}
