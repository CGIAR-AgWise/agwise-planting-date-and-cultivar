#!/usr/bin/env Rscript
###############################################################################
# Script: prepare_kvuno_upload.R
# Purpose: Convert one of this repo's DSSAT AOI result files (as produced by
#          merge_DSSAT_output()/run_dssat_pipeline.R - one row per pixel x
#          cultivar x planting-date trial, with yield and weather columns)
#          into the flat, ranked format the Kvuno API (kvuno.agwise.org)
#          expects for upload via /ui/upload or POST /api/v1/data/upload:
#          one row per pixel x cultivar x planting_option, with only
#          country/lat/lon/province/variety/season_type/opt_date/
#          planting_option - see GET /ui/columns on the Kvuno server for the
#          authoritative column list this mirrors.
#
#          Kvuno stores the RANKED RECOMMENDATION only (planting_option is a
#          rank, 1 = best) - no yield or other simulation output - so this
#          script computes the same per-pixel/cultivar ranking add_date_rank()
#          uses in get_pdate_cultivar_recommendation.R (row_number(desc(
#          <metric>)) grouped by pixel + cultivar) and drops everything else.
#
#          Pixel identity uses XLAT/LONG, not the file's separate Lat/Long
#          columns: XLAT/LONG is the AOI point actually simulated (echoed by
#          DSSAT's own .OUT report - see merge_DSSAT_output.R), and the same
#          pair every downstream ranking/rasterizing step in this repo
#          groups/keys by (add_date_rank(), build_rank_layers() in
#          get_pdate_cultivar_recommendation.R). Lat/Long instead comes from
#          the weather (.WHT) file's header - i.e. which weather station/grid
#          cell fed the run, not the AOI point - and can disagree with
#          XLAT/LONG by several degrees where the weather grid didn't align
#          exactly with the AOI grid.
#
#          season_type has no equivalent in this repo's output (each run is
#          a single season) and is left NA unless --season-type is given.
#
# Usage:
#   Rscript main/Kvuno/prepare_kvuno_upload.R \
#     --file data/usecases/useCase_Nigeria_full/Maize/result/DSSAT/AOI/ISRIC_useCase_Nigeria_full_Maize_AOI_season_1.RDS \
#     --country Nigeria
#
#   Rscript main/Kvuno/prepare_kvuno_upload.R \
#     --file data/usecases/useCase_Zambia_full/Maize/result/DSSAT/AOI/ISRIC_useCase_Zambia_full_Maize_AOI_season_1.RDS \
#     --country Zambia --top-n 5
#
#   --file          Path to an AOI result RDS (merge_DSSAT_output()'s raw
#                   output, or its _cropmask companion - same columns).
#   --country       Country name to stamp on every row (e.g. "Nigeria").
#   --metric        Yield/quality column to rank planting dates by within
#                   each pixel x cultivar. Default: HWAH.
#   --top-n         Keep only planting_option <= this rank per pixel x
#                   cultivar (Kvuno's existing Zambia data uses 5). Default: 5.
#   --season-type   Value to stamp into season_type on every row. Default:
#                   NA (this repo doesn't produce season_type).
#   --out           Output .RDS path. Default: ./kvuno_upload/<basename of
#                   --file> (created if it doesn't exist).
#
# Output columns match Kvuno's /ui/columns exactly (country, lat, lon,
# opt_date, planting_option, province, season_type, variety), so the file
# uploads through /ui/upload with every column auto-mapped - no manual
# mapping step needed.
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

file_path   <- arg(args, "file")
country     <- arg(args, "country")
metric      <- arg(args, "metric", "HWAH")
top_n       <- as.integer(arg(args, "top-n", "5"))
season_type <- arg(args, "season-type", NA_character_)
out_path    <- arg(args, "out")

if (is.null(file_path) || is.null(country)) {
  stop(
    "Usage: Rscript prepare_kvuno_upload.R --file <AOI_result.RDS> --country <Country> ",
    "[--metric HWAH] [--top-n 5] [--season-type <value>] [--out <path>]")
}
if (!file.exists(file_path)) {
  stop("--file not found: ", file_path)
}
if (is.null(out_path)) {
  out_dir <- "kvuno_upload"
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  out_path <- file.path(out_dir, basename(file_path))
}

suppressPackageStartupMessages(library(dplyr))
Sys.setlocale("LC_TIME", "C")  # force English month abbreviations (%b) regardless of system locale

df <- readRDS(file_path)

required_cols <- c("XLAT", "LONG", "Cultivar", "PDAT", "zone", metric)
missing_cols <- setdiff(required_cols, names(df))
if (length(missing_cols) > 0) {
  stop(
    "Input file is missing expected column(s): ", paste(missing_cols, collapse = ", "),
    ". Present columns: ", paste(names(df), collapse = ", "))
}

message(
  "Ranking planting dates within each pixel x cultivar by ", metric,
  " (descending), keeping the top ", top_n, "...")

ranked <- df %>%
  group_by(XLAT, LONG, Cultivar) %>%
  mutate(planting_option = dplyr::row_number(dplyr::desc(.data[[metric]]))) %>%
  ungroup() %>%
  filter(planting_option <= top_n)

upload_df <- data.frame(
  country         = country,
  lat             = ranked$XLAT,
  lon             = ranked$LONG,
  province        = ranked$zone,
  variety         = tolower(ranked$Cultivar),
  season_type     = season_type,
  opt_date        = format(ranked$PDAT, "%d-%b"),
  planting_option = ranked$planting_option,
  stringsAsFactors = FALSE
)

variety_values <- sort(unique(upload_df$variety))
message(
  "variety values in output: ", paste(variety_values, collapse = ", "),
  " - check this matches Kvuno's existing convention (e.g. an 'average' or ",
  "'longer' cultivar label won't be recognized if the rest of the dataset ",
  "only uses short/medium/long).")

saveRDS(upload_df, out_path)
message(
  nrow(upload_df), " rows written to ", out_path,
  " (", length(unique(paste(upload_df$lat, upload_df$lon))), " pixels, ",
  length(variety_values), " variety values, country = ", country, ").")
