#!/usr/bin/env Rscript
###############################################################################
# Script: add_rain_onset_to_results.R
# Purpose: Bring an already-finished usecase crop up to date with what
#          run_dssat_pipeline.R now produces for the Shiny dashboard's
#          rainfall maps, without re-running DSSAT:
#            - onset_date added to the merged results RDS (re-saved)
#            - <base>_daily_rain.RDS from the bias-corrected PRCP cubes
#            - dashboard extract/data RDS rebuilt (no HTML render)
#          Then rebuild the store with build_dashboard_store.R.
#
# Usage:
#   Rscript main/DSSAT/add_rain_onset_to_results.R <config.yml> [<config.yml> ...]
#
#   For a usecase whose config was deleted, restore it from git first, e.g.
#     git show a809d96~1:usecases/configs/ZMB/maize_sep_init.yml > /tmp/zmb.yml
###############################################################################

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE))
repo_root <- normalizePath(file.path(script_dir, "..", ".."), mustWork = TRUE)

source(file.path(repo_root, "usecases", "00_usecase_helpers.R"))
source(file.path(repo_root, "main/DSSAT/run_dssat_pipeline.R"))
source(file.path(repo_root, "main/DSSAT/00_load_packages.R"))
source(file.path(repo_root, "main/DSSAT/common_helpers.R"))
source(file.path(repo_root, "main/DSSAT/helpers_DSSAT_expfile.R"))
source(file.path(repo_root, "main/DSSAT/get_pdate_cultivar_recommendation.R"))
source(file.path(repo_root, "main/DSSAT/bc_daily_rain.R"))

configs <- commandArgs(trailingOnly = TRUE)
if (length(configs) == 0) {
  stop("Usage: Rscript main/DSSAT/add_rain_onset_to_results.R <config.yml> [<config.yml> ...]")
}

for (config_path in configs) {
  usecase <- read_usecase_yaml(usecase_config_file(config_path, repo_root))
  complete_usecase <- load_dssat_defaults(usecase, repo_root)
  message("\n=== ", complete_usecase$country_name, " / ", complete_usecase$use_case_name,
          " / ", complete_usecase$crop, " ===")

  result_dir <- file.path(
    project_usecase_dir(repo_root, complete_usecase$country_name, complete_usecase$use_case_name),
    complete_usecase$crop, "result", "DSSAT", "AOI")
  base_filename <- paste0(
    complete_usecase$soil_source, "_useCase_", complete_usecase$country_name,
    "_", complete_usecase$use_case_name, "_", complete_usecase$crop,
    "_AOI_season_", complete_usecase$season)
  # Usecase folders renamed after the run keep their old file names
  if (!file.exists(file.path(result_dir, paste0(base_filename, ".RDS")))) {
    base_filename <- tryCatch(find_base_filename(result_dir, complete_usecase$crop), error = function(e) NULL)
    if (is.null(base_filename)) {
      warning("No merged results in ", result_dir, " - skipped.", call. = FALSE)
      next
    }
  }
  raw_path <- file.path(result_dir, paste0(base_filename, ".RDS"))

  results_df <- add_onset_dates(readRDS(raw_path))
  saveRDS(results_df, raw_path)
  message("onset_date added to: ", raw_path, " (", sum(is.na(results_df$onset_date)), " NA rows)")

  write_daily_rain(complete_usecase, results_df, output_dir = result_dir, base_filename = base_filename)

  build_crop_dashboard(
    crop = complete_usecase$crop, result_dir = result_dir, base_filename = base_filename,
    crop_mask_dir = file.path(repo_root, "Landing", "crop_masks"), repo_root = repo_root,
    country_name = complete_usecase$country_name, force_rebuild = TRUE, render_html = FALSE)
}
