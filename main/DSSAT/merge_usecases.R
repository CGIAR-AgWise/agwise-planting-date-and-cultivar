#!/usr/bin/env Rscript
###############################################################################
# Script: merge_usecases.R
# Purpose: Merge several already-run usecases for ONE country into one new
#          usecase directory, so results that were split across separate
#          pipeline runs (e.g. Nigeria's maize, currently four usecases -
#          useCase_Nigeria_full_apr/_jul/_jun/_mar - each simulating a
#          different, non-overlapping set of states with the planting month
#          appropriate for that region) show up as one coherent
#          country/crop result, the way every other country already has a
#          single "_full" usecase.
#
#          Standalone and independent of run_dssat_pipeline.R - it never
#          runs automatically, and never touches the source usecases. It
#          only reads their result/DSSAT/AOI/ raw RDS (not transform/ -
#          nothing downstream reads that, and it's tens of thousands of
#          small per-point files per usecase) and writes a NEW usecase
#          directory.
#
#          Ranking (Combination_Rank/Date_Rank) is grouped per pixel
#          (XLAT, LONG) only - see add_date_rank()/add_combination_rank() in
#          get_pdate_cultivar_recommendation.R - so concatenating the source
#          usecases' raw rows and re-ranking via build_crop_dashboard() is
#          correct whether or not their zones overlap, with no special
#          casing needed either way.
#
# Usage:
#   Rscript main/DSSAT/merge_usecases.R \
#     --country Nigeria \
#     --usecases full_apr,full_jul,full_jun,full_mar \
#     --merged-name full
#
#   --country       Country name exactly as used in data/usecases/useCase_<Country>_<usecase> (e.g. "Nigeria").
#   --usecases      Comma-separated list of SOURCE usecase names (the part after useCase_<Country>_), e.g. full_apr,full_jul,full_jun,full_mar.
#   --merged-name   Usecase name for the NEW merged usecase (e.g. "full" -> data/usecases/useCase_Nigeria_full).
#
# After running, re-run build_dashboard_store.R (optionally with its
# --usecases flag) to pick up the merged usecase and, if desired, exclude
# the pre-merge source usecases from the dashboard store without deleting
# them.
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

country <- arg(args, "country")
usecases_arg <- arg(args, "usecases")
merged_name <- arg(args, "merged-name")
if (is.null(country) || is.null(usecases_arg) || is.null(merged_name)) {
  stop(
    "Usage: Rscript merge_usecases.R --country <Country> ",
    "--usecases <name1,name2,...> --merged-name <name>")
}
source_names <- trimws(strsplit(usecases_arg, ",")[[1]])
if (length(source_names) < 2) {
  stop("--usecases needs at least 2 usecase names to merge, got: ", usecases_arg)
}

source(file.path(repo_root, "main/DSSAT/00_load_packages.R"))
source(file.path(repo_root, "main/DSSAT/common_helpers.R"))
source(file.path(repo_root, "main/DSSAT/get_pdate_cultivar_recommendation.R"))
suppressPackageStartupMessages(library(dplyr))

### Resolve and validate source usecase directories
source_dirs <- setNames(
  vapply(source_names, function(nm) project_usecase_dir(repo_root, country, nm), character(1)),
  source_names)
missing <- source_dirs[!dir.exists(source_dirs)]
if (length(missing) > 0) {
  stop("Source usecase(s) not found:\n  ", paste(missing, collapse = "\n  "))
}

### Resolve destination usecase directory - refuse to clobber an existing,
### unrelated merged usecase; the caller should remove a stale one first
### rather than this script silently overwriting whatever's there.
merged_dir <- project_usecase_dir(repo_root, country, merged_name)
if (dir.exists(merged_dir) && !(merged_dir %in% source_dirs)) {
  stop(
    "Destination usecase already exists: ", merged_dir,
    "\nRemove it first if you want to re-merge into it:\n  rm -r ", merged_dir)
}

### Union of crops across all source usecases, reporting any source that's
### missing a given crop rather than silently dropping it.
source_crop_dirs <- lapply(source_dirs, discover_crops)
all_crops <- sort(unique(unlist(lapply(source_crop_dirs, names))))
if (length(all_crops) == 0) {
  stop("No crops with result/DSSAT/AOI outputs found under any of the source usecases.")
}
message("Crops found across source usecases: ", paste(all_crops, collapse = ", "))

crop_mask_dir <- file.path(repo_root, "Landing", "crop_masks")

for (crop in all_crops) {
  message("\n== ", crop, " ==")
  contributing <- Filter(function(nm) crop %in% names(source_crop_dirs[[nm]]), source_names)
  missing_crop <- setdiff(source_names, contributing)
  if (length(missing_crop) > 0) {
    warning(
      "Crop '", crop, "' is missing from usecase(s): ",
      paste(missing_crop, collapse = ", "), " - merging only from: ",
      paste(contributing, collapse = ", "), call. = FALSE)
  }

  raw_list <- vector("list", length(contributing))
  base_filenames <- character(length(contributing))
  for (i in seq_along(contributing)) {
    nm <- contributing[[i]]
    result_dir_i <- source_crop_dirs[[nm]][[crop]]
    base_filenames[[i]] <- find_base_filename(result_dir_i, crop)
    raw_path <- file.path(result_dir_i, paste0(base_filenames[[i]], ".RDS"))
    raw_list[[i]] <- readRDS(raw_path)
    message(sprintf("  %-12s %7d rows (%s)", nm, nrow(raw_list[[i]]), base_filenames[[i]]))
  }

  merged_raw <- dplyr::bind_rows(raw_list)
  message(sprintf("  %-12s %7d rows (merged)", "TOTAL", nrow(merged_raw)))

  # Each source's raw grid already has many rows per pixel (one per
  # cultivar x treatment) - so overlap across SOURCES has to be checked on
  # each source's own DISTINCT pixel set, not on raw row counts (which would
  # spuriously flag nearly every pixel as "overlapping" just from a single
  # source's own within-pixel repeats).
  pixel_keys_per_source <- lapply(raw_list, function(df) unique(paste(df$XLAT, df$LONG)))
  overlap_pixels <- sum(duplicated(unlist(pixel_keys_per_source)))
  if (overlap_pixels > 0) {
    message(
      "  Note: ", overlap_pixels, " pixel(s) appear in more than one source ",
      "usecase - ranks will be recomputed across all of them together for ",
      "that pixel, which is fine, just flagging it.")
  } else {
    message("  No pixel overlap between source usecases.")
  }

  ### Reuse the first source's soil-source/season tokens for the merged raw
  ### RDS's filename (cosmetic only - nothing downstream parses it), just
  ### swapping in the merged usecase's own name. Warn, don't error, if
  ### sources disagree - not worth failing the merge over a filename detail.
  parse_tokens <- function(base_filename, usecase_name) {
    m <- regmatches(
      base_filename,
      regexec(paste0("^(.*)_useCase_.*_", usecase_name, "_.*_AOI_season_([0-9]+)$"), base_filename))[[1]]
    if (length(m) != 3) return(list(soil_source = NA_character_, season = NA_character_))
    list(soil_source = m[[2]], season = m[[3]])
  }
  tokens <- Map(parse_tokens, base_filenames, contributing)
  soil_sources <- unique(vapply(tokens, `[[`, character(1), "soil_source"))
  seasons <- unique(vapply(tokens, `[[`, character(1), "season"))
  if (length(soil_sources) > 1 || length(seasons) > 1) {
    warning(
      "Source usecases disagree on soil-source/season token in their raw ",
      "filenames (", paste(soil_sources, collapse = "/"), " / ",
      paste(seasons, collapse = "/"), ") - using the first source's.", call. = FALSE)
  }
  soil_source <- if (is.na(soil_sources[[1]])) "merged" else soil_sources[[1]]
  season <- if (is.na(seasons[[1]])) "1" else seasons[[1]]
  merged_base_filename <- paste0(
    soil_source, "_useCase_", country, "_", merged_name, "_", crop, "_AOI_season_", season)

  merged_result_dir <- file.path(merged_dir, crop, "result", "DSSAT", "AOI")
  dir.create(merged_result_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(merged_raw, file.path(merged_result_dir, paste0(merged_base_filename, ".RDS")))

  ### Regenerates the crop-mask file, ranked dashboard extract, dashboard
  ### data RDS, and HTML dashboard for the merged usecase - see
  ### get_pdate_cultivar_recommendation.R, reused as-is.
  build_crop_dashboard(
    crop = crop, result_dir = merged_result_dir, base_filename = merged_base_filename,
    crop_mask_dir = crop_mask_dir, repo_root = repo_root, country_name = country,
    force_rebuild = TRUE)
}

message(
  "\nMerged usecase written to: ", merged_dir,
  "\nRe-run build_dashboard_store.R (optionally with --usecases naming just ",
  "the usecases you want, e.g. this merged one instead of its ",
  length(source_names), " sources) to pick this up in the dashboard.")
