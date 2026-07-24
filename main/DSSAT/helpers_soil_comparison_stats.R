###############################################################################
# Script: helpers_soil_comparison_stats.R
# Purpose: Helper functions for comparing DSSAT outputs by soil data source.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

read_isric_isda_data <- function(project_root, country, useCaseName, Crop, season, AOI) {
  if (!exists("project_usecase_dir", mode = "function")) {
    source(file.path(project_root, "main", "DSSAT", "common_helpers.R"))
  }
  usecase_dir <- project_usecase_dir(project_root, country, useCaseName)
  if (AOI) {
    dir_path <- file.path(usecase_dir, Crop, "result", "DSSAT", "AOI")
  } else {
    dir_path <- file.path(usecase_dir, Crop, "result", "DSSAT", "fieldData")
  }
  isric_path <- file.path(
    dir_path,
    paste0("ISRIC_useCase_", country, "_", useCaseName, "_",
           Crop, "_AOI_season_", season, ".RDS"))
  isda_path <- file.path(
    dir_path,
    paste0("ISDA_useCase_", country, "_", useCaseName, "_",
           Crop, "_AOI_season_", season, ".RDS"))
  if (file.exists(isric_path) && file.exists(isda_path)) {
    isric_data <- readRDS(isric_path)
    isda_data <- readRDS(isda_path)
  } else {
    stop("Missing ISRIC/ISDA file. Change config file and rerun for the other soil source.")
  }
  
  return(list(
    ISRIC = isric_data, 
    ISDA = isda_data
    ))
}

add_year_column <- function(df, date_col = "HDAT") {
  df$Year <- as.numeric(format(as.Date(df[[date_col]]), "%Y"))
  return(df)
}


get_common_pixels <- function(isric_data, isda_data) {
  common_pixels <- inner_join(
    isric_data %>% distinct(Lat, Long),
    isda_data  %>% distinct(Lat, Long),
    by = c("Lat", "Long")
  )
  common_pixels
}
