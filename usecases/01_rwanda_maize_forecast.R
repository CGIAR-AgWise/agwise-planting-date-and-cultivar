#!/usr/bin/env Rscript
###############################################################################
# Script: 01_rwanda_maize_forecast.R
# Purpose: Run the Rwanda maize use case from its YAML configuration.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE)) else "usecases"
source(file.path(script_dir, "00_usecase_helpers.R"))
run_usecase_config("configs/RWA/maize_rab.yml")
