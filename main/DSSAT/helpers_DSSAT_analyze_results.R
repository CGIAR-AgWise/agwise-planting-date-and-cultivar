# Read ISRIC vs ISDA merged dataset
read_isric_isda_data <- function(
    project_root, country, useCaseName, Crop, season, AOI) {
  if (AOI) {
    dir_path <- paste0(project_root, "/Data/useCase_", country, "_", useCaseName,
                       "/", Crop, "/result/DSSAT/AOI/")
  } else {
    dir_path <- paste0(project_root, "/Data/useCase_", country, "_", useCaseName,
                       "/", Crop, "/result/DSSAT/fieldData/")
  }
  isric_path <- paste0(dir_path, "ISRIC_useCase_", country, "_", useCaseName, "_",
                       Crop, "_AOI_season_", season, ".RDS")
  isda_path <- paste0(dir_path, "ISDA_useCase_", country, "_", useCaseName, "_",
                      Crop, "_AOI_season_", season, ".RDS")
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


# Add year column
add_year_column <- function(df, date_col = "HDAT") {
  df$Year <- as.numeric(format(as.Date(df[[date_col]]), "%Y"))
  return(df)
}


# Get common pixels for the ISRIC and ISDA dataset
get_common_pixels <- function(isric_data, isda_data) {
  common_pixels <- inner_join(
    isric_data %>% distinct(Lat, Long),
    isda_data  %>% distinct(Lat, Long),
    by = c("Lat", "Long")
  )
  common_pixels
}


# Read non-Soil comparison merged data
read_non_soil_comparison_merged_dataset <- function(
    project_root, country, useCaseName, Crop, season, AOI, Soil_source) {
  if (AOI) {
    dir_path <- paste0(project_root, "/Data/useCase_", country, "_", useCaseName,
                       "/", Crop, "/result/DSSAT/AOI/")
    file_name <- paste0(
      Soil_source, "_useCase_", country, "_", useCaseName, "_", Crop, 
      "_AOI_season_", season, ".RDS")
  } else {
    dir_path <- paste0(project_root, "/Data/useCase_", country, "_", useCaseName,
                       "/", Crop, "/result/DSSAT/fieldData/")
  }
  
  merged_df <- readRDS(paste0(dir_path, file_name))
  return(merged_df)
}


### Summarize by treatment 
summary_DSSAT_results <- function(data, variable = HWAH, by_treatment = TRUE) {
  
  var <- enquo(variable)
  
  if(by_treatment) {
    summary_table <- data %>%
      group_by(TNAM) %>%
      summarise(
        n = n(),
        min = min(!!var, na.rm = TRUE),
        Q1 = quantile(!!var, 0.25, na.rm = TRUE),
        median = median(!!var, na.rm = TRUE),
        mean = mean(!!var, na.rm = TRUE),
        Q3 = quantile(!!var, 0.75, na.rm = TRUE),
        max = max(!!var, na.rm = TRUE),
        .groups = "drop"
      )
  } else {
    summary_table <- data %>%
      summarise(
        n = n(),
        min = min(!!var, na.rm = TRUE),
        Q1 = quantile(!!var, 0.25, na.rm = TRUE),
        median = median(!!var, na.rm = TRUE),
        mean = mean(!!var, na.rm = TRUE),
        Q3 = quantile(!!var, 0.75, na.rm = TRUE),
        max = max(!!var, na.rm = TRUE)
      )
  }
  
  return(summary_table)
}


# Plot time series of a variable for a pixel
plot_DSSAT_pixel <- function(data, lat, lon, variable = HWAH) {
  library(dplyr)
  library(ggplot2)
  library(lubridate)
  
  var <- enquo(variable)
  
  pixel_data <- data %>%
    filter(XLAT == lat, LONG == lon) %>%
    mutate(year = year(PDAT))
  
  ggplot(pixel_data, aes(x = year, y = !!var, color = TNAM, group = TNAM)) +
    geom_line() +
    geom_point() +
    labs(
      title = paste(quo_name(var), " over years at (", lat, ",", lon, ")", sep = ""),
      x = "Year",
      y = quo_name(var)
    ) +
    theme_minimal()
}


### Plot time series for the aggregate (across space) and treatment response
plot_aggregate <- function(data, variable = HWAH) {
  library(dplyr)
  library(ggplot2)
  library(lubridate)
  
  var <- enquo(variable)
  
  agg_data <- data %>%
    mutate(year = year(PDAT)) %>%
    group_by(year, TNAM) %>%
    summarise(mean_value = mean(!!var, na.rm = TRUE), .groups = "drop")
  
  ggplot(agg_data, aes(x = year, y = mean_value, color = TNAM)) +
    geom_line(size = 1) +
    geom_point() +
    labs(
      title = paste("Average", quo_name(var), "per Treatment Over Years"),
      x = "Year",
      y = paste("Mean", quo_name(var))
    ) +
    theme_minimal()
}


### 
plot_map <- function(data, treatment, year_selected, variable = HWAH) {
  library(dplyr)
  library(ggplot2)
  library(lubridate)
  
  var <- enquo(variable)
  
  map_data <- data %>%
    filter(TNAM == treatment, year(PDAT) == year_selected)
  
  ggplot(map_data, aes(x = LONG, y = XLAT, fill = !!var)) +
    geom_tile() +
    scale_fill_viridis_c(option = "plasma") +
    labs(
      title = paste(quo_name(var), "for", treatment, "in", year_selected),
      x = "Longitude",
      y = "Latitude",
      fill = quo_name(var)
    ) +
    theme_minimal()
}