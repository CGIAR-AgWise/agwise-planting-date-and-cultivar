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

repo_root <- usecase_repo_root()
configs <- list.files(
  file.path(repo_root, "usecases", "configs"),
  pattern = "[.]ya?ml$",
  recursive = TRUE,
  full.names = TRUE
)
configs <- configs[vapply(configs, function(config) {
  identical(read_usecase_yaml(config)$crop, "Maize")
}, logical(1))]

if (!length(configs)) {
  stop("No maize YAML configs found under usecases/configs/<ISO3>/")
}

for (config in configs) {
  run_usecase_config(config)
}
