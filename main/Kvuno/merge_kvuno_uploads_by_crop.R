#!/usr/bin/env Rscript
###############################################################################
# Script: merge_kvuno_uploads_by_crop.R
# Purpose: Combine the per-country Kvuno-format files produced by
#          prepare_kvuno_upload.R (one row per pixel x variety x
#          planting_option, 8 columns matching Kvuno's /ui/columns) into one
#          file per crop, across all countries - since Kvuno's schema has no
#          crop field, keeping crops in separate upload files (rather than
#          uploading, say, Zambia's Maize and Soybean as two jobs that land
#          in the same undifferentiated table) is the only way to know which
#          uploaded rows belong to which crop.
#
#          Crop is read off each input filename via the same
#          "..._<Crop>_AOI_season_<N>.RDS" naming convention
#          prepare_kvuno_upload.R's default output uses (it keeps the source
#          AOI file's basename unchanged) - not from file content, since the
#          merged files themselves have no crop column either.
#
# Usage:
#   Rscript main/Kvuno/merge_kvuno_uploads_by_crop.R [--dir kvuno_upload] [--out-dir <dir>]
#
#   --dir       Directory of prepare_kvuno_upload.R outputs to merge. Default: kvuno_upload
#   --out-dir   Directory to write the merged per-crop files to. Default: same as --dir
#
# Output: <out-dir>/useCase_<Crop>_AllCountries.RDS per crop found.
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

args <- parse_args(commandArgs(trailingOnly = TRUE))

in_dir  <- arg(args, "dir", "kvuno_upload")
out_dir <- arg(args, "out-dir", in_dir)

if (!dir.exists(in_dir)) stop("--dir not found: ", in_dir)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

merged_pattern <- "^useCase_.*_AllCountries\\.RDS$"
files <- list.files(in_dir, pattern = "\\.RDS$", full.names = FALSE, ignore.case = TRUE)
files <- files[!grepl(merged_pattern, files)]  # don't re-merge a previous merge's own output

if (length(files) == 0) {
  stop("No source .RDS files found in ", in_dir, " (excluding already-merged useCase_*_AllCountries.RDS files).")
}

crop_of <- function(filename) {
  m <- regmatches(filename, regexec(".*_([A-Za-z]+)_AOI_season.*", filename))[[1]]
  if (length(m) < 2) NA_character_ else m[2]
}

crops <- vapply(files, crop_of, character(1))
unmatched <- files[is.na(crops)]
if (length(unmatched) > 0) {
  stop(
    "Could not parse a crop name (expected '..._<Crop>_AOI_season_<N>.RDS') from: ",
    paste(unmatched, collapse = ", "))
}

for (crop in sort(unique(crops))) {
  crop_files <- files[crops == crop]
  message("Merging ", length(crop_files), " file(s) for crop '", crop, "': ",
          paste(crop_files, collapse = ", "))

  parts <- lapply(crop_files, function(f) readRDS(file.path(in_dir, f)))
  expected_cols <- names(parts[[1]])
  bad <- Filter(function(i) !identical(names(parts[[i]]), expected_cols), seq_along(parts))
  if (length(bad) > 0) {
    stop(
      "Column mismatch merging crop '", crop, "' - ", crop_files[bad[1]],
      " has columns [", paste(names(parts[[bad[1]]]), collapse = ", "),
      "], expected [", paste(expected_cols, collapse = ", "), "]")
  }

  merged <- do.call(rbind, parts)
  out_path <- file.path(out_dir, paste0("useCase_", crop, "_AllCountries.RDS"))
  saveRDS(merged, out_path)
  message(
    nrow(merged), " rows written to ", out_path,
    " (countries: ", paste(sort(unique(merged$country)), collapse = ", "), ").")
}
