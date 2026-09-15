#!/usr/bin/env Rscript
###############################################################################
# Script: mozambique_maize_chokwe_forecast.R
# Purpose: Run an AgWISE YAML-configured forecast-to-DSSAT use case.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-09-14
###############################################################################

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_file <- if (length(file_arg)) normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE) else NA_character_
candidate_dirs <- unique(c(if (!is.na(script_file)) dirname(script_file), normalizePath("usecases", mustWork = FALSE)))
script_dir <- candidate_dirs[file.exists(file.path(candidate_dirs, "00_usecase_helpers.R"))][1]
if (is.na(script_dir)) stop("Could not locate usecases/00_usecase_helpers.R. Run this wrapper from the project root or place it in usecases/.")
Sys.setenv(AGWISE_USECASES_DIR = script_dir)
source(file.path(script_dir, "00_usecase_helpers.R"))

run_usecase_config(file.path(
  script_dir, "configs", "MOZ", "maize_chokwe.yml"
))
