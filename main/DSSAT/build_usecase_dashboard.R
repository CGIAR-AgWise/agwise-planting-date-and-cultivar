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
#          run_dssat_pipeline.R now also builds each crop's dashboard
#          automatically at the end of its own run (Step 6); this script
#          remains useful standalone to rebuild dashboards for a whole
#          usecase at once (e.g. after a template/styling change) without
#          rerunning DSSAT.
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

### discover_crops() / find_base_filename() live in common_helpers.R (shared
### with main/DSSAT/merge_usecases.R).
crop_dirs <- discover_crops(usecase_dir)
if (length(crop_dirs) == 0) {
  stop("No crops with result/DSSAT/AOI outputs found under: ", usecase_dir)
}
message("Found crops: ", paste(names(crop_dirs), collapse = ", "))

### For each crop: build (or reuse) its dashboard, via the same function
### run_dssat_pipeline.R now also calls automatically at the end of each
### crop's own pipeline run.
for (crop in names(crop_dirs)) {
  result_dir <- crop_dirs[[crop]]
  base_filename <- find_base_filename(result_dir, crop)
  build_crop_dashboard(
    crop = crop, result_dir = result_dir, base_filename = base_filename,
    crop_mask_dir = crop_mask_dir, repo_root = repo_root,
    country_name = country_name)
}
