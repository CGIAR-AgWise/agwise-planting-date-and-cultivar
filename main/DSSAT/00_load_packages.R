###############################################################################
# Script: 00_load_packages.R
# Purpose: Load required packages for the DSSAT workflow.
#
# Authors: Alvaro Carmona-Cabrero
# Institution: CGIAR (IITA & Alliance of Bioversity International and CIAT)
# Date: 2026-06-07
###############################################################################

load_or_install <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

packages_required <- c(
  "yaml", "countrycode", "stringr", "lubridate", "readr", "purrr", "terra",
  "geodata", "DSSAT", "future", "furrr", "future.apply", "tidyverse"
)
packages_required <- c(
  "chirps", "terra", "sf", "rgl", "sp", "geodata", "tidyverse", "countrycode", 
  "DSSAT", "furrr", "future", "lubridate", "dplyr", "parallel", "future.apply",
  "foreach")


invisible(lapply(packages_required, load_or_install))
