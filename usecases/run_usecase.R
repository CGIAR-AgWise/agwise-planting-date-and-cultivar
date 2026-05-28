#!/usr/bin/env Rscript
###############################################################################
# Script: run_usecase.R
# Purpose: Run one AgWISE use-case YAML configuration.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE)) else "usecases"
source(file.path(script_dir, "00_usecase_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
config_arg <- args[!startsWith(args, "--")][1]
if (is.na(config_arg)) {
  stop("Usage: Rscript usecases/run_usecase.R usecases/configs/<ISO3>/<crop_usecase>.yml [--dry-run]")
}

run_usecase_config(config_arg)
