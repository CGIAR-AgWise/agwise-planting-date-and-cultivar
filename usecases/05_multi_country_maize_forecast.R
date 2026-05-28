#!/usr/bin/env Rscript
###############################################################################
# Script: 05_multi_country_maize_forecast.R
# Purpose: Run the configured multi-country maize use cases.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE)) else "usecases"
source(file.path(script_dir, "00_usecase_helpers.R"))

configs <- c(
  "configs/KEN/maize_example.yml",
  "configs/RWA/maize_rab.yml",
  "configs/ETH/maize_national.yml",
  "configs/GHA/maize_national.yml",
  "configs/MWI/maize_national.yml"
)

for (config in configs) {
  run_usecase_config(config)
}
