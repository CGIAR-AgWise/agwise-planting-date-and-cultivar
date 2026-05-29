#!/usr/bin/env Rscript
###############################################################################
# Script: run_multi_country.R
# Purpose: Run multiple AgWISE use-case YAML configurations.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE)) else "usecases"
source(file.path(script_dir, "00_usecase_helpers.R"))

cli <- parse_usecase_args()
config_args <- cli[[".positionals"]] %||% character()
repo_root <- usecase_repo_root()

if (!length(config_args)) {
  config_args <- list.files(
    file.path(repo_root, "usecases", "configs"),
    pattern = "[.]ya?ml$",
    recursive = TRUE,
    full.names = TRUE
  )
}

if (!length(config_args)) {
  stop("No YAML configs found. Add configs under usecases/configs/<ISO3>/ or pass config paths.")
}

for (config in config_args) {
  message("\n=== Running use-case config: ", config, " ===")
  run_usecase_config(config)
}
