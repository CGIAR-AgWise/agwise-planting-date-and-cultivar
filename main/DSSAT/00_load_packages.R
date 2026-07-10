###############################################################################
# Script: 00_load_packages.R
# Purpose: Load required packages for the DSSAT workflow.
#
# Authors: Alvaro Carmona-Cabrero
# Institution: CGIAR (IITA & Alliance of Bioversity International and CIAT)
# Date: 2026-07-09
###############################################################################

load_or_install <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

packages_required <- c(
  "yaml", "mgsub", "countrycode", "parallel", "foreach", "future",
  "future.apply", "furrr", "sp", "sf", "terra", "rgl", "geodata",
  "chirps", "tidyverse", "readr", "stringr", "lubridate", "purrr",
  "dplyr", "DSSAT"
)

invisible(lapply(packages_required, load_or_install))
