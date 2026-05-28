###############################################################################
# Script: soil_comparison_stats.R
# Purpose: Run soil-source comparison summaries for DSSAT simulation outputs.
#
# Author: Jemal S. Ahmed
# Email: jemal.ahmed@cgiar.org
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-05-29
###############################################################################

library(dplyr)
library(ggplot2)
library(rlang)

source(paste0(project_root, "/main/DSSAT/helpers_soil_comparison_stats.R"))

run_full_soil_comparison <- function(
    project_root,
    country,
    useCaseName,
    Crop,
    AOI = TRUE,
    season,
    variable = "HWAH",
    lat = NULL,
    lon = NULL,
    map_year = NULL
) {

  # Get ISRIC and ISDA data
  soil_comparison_data <- read_isric_isda_data(project_root, country, useCaseName,
                                               Crop, season, AOI)
  
  isric_data <- soil_comparison_data$ISRIC
  isda_data <- soil_comparison_data$ISDA
  
  common_pixels <- get_common_pixels(soil_comparison_data$ISRIC,
                                     soil_comparison_data$ISDA)
  
  # Add Year column
  isric_data <- add_year(isric_data)
  isda_data  <- add_year(isda_data)
  
  # Keep common pixels
  common_pixels <- get_common_pixels(isric_data, isda_data)
  
  isric_data <- inner_join(isric_data, common_pixels, by = c("Lat", "Long"))
  isda_data  <- inner_join(isda_data,  common_pixels, by = c("Lat", "Long"))
  
  # Merge datasets
  merged <- inner_join(
    isric_data %>% select(Lat, Long, Year, TNAM,
                          ISRIC = !!sym(variable)),
    isda_data  %>% select(Lat, Long, Year, TNAM,
                          ISDA = !!sym(variable)),
    by = c("Lat", "Long", "Year", "TNAM")
  )
  
  ### 1. Overall performance
  overall <- data.frame(
    RMSE = sqrt(mean((merged$ISRIC - merged$ISDA)^2, na.rm = TRUE)),
    Bias = mean(merged$ISDA - merged$ISRIC, na.rm = TRUE),
    Correlation = cor(merged$ISRIC, merged$ISDA,
                      use = "complete.obs"),
    N = nrow(merged)
  )
  
  ### 2. Yearly regional metrics
  yearly_summary <- merged %>%
    group_by(Year) %>%
    summarise(
      RMSE = sqrt(mean((ISRIC - ISDA)^2, na.rm = TRUE)),
      Bias = mean(ISDA - ISRIC, na.rm = TRUE),
      Correlation = cor(ISRIC, ISDA,
                        use = "complete.obs"),
      N = n()
    )
  
  ### 3. Time series for one location
  timeseries_plot <- NULL
  timeseries_metrics <- NULL
  
  if (!is.null(lat) & !is.null(lon)) {
    
    ts_data <- merged %>%
      filter(abs(Lat - lat) < 1e-4,
             abs(Long - lon) < 1e-4)
    
    ts_long <- ts_data %>%
      pivot_longer(
        cols = c(ISRIC, ISDA),
        names_to = "Dataset",
        values_to = "Yield"
      )
    
    # create combined grouping
    ts_long$Group <- paste(ts_long$Dataset, ts_long$TNAM)
    
    # manual color palette
    cold_cols <- c("#08306B", "#2171B5", "#6BAED6", "#C6DBEF")
    warm_cols <- c("#67000D", "#CB181D", "#FB6A4A", "#FCAE91")
    
    names(cold_cols) <- paste("ISRIC", unique(ts_long$TNAM))
    names(warm_cols) <- paste("ISDA", unique(ts_long$TNAM))
    
    color_map <- c(cold_cols, warm_cols)
    
    timeseries_plot <- ggplot(ts_long,
                              aes(x = Year,
                                  y = Yield,
                                  color = Group,
                                  group = Group)) +
      geom_line(linewidth = 1) +
      geom_point(size = 2) +
      scale_color_manual(values = color_map) +
      labs(title = paste("Time Series at", lat, lon),
           y = variable,
           color = "Dataset + Planting Date") +
      theme_minimal()
  }
  
  ### 4. Scatter plot
  scatter_plot <- ggplot(merged,
                         aes(ISRIC, ISDA)) +
    geom_point(alpha = 0.4) +
    geom_abline(slope = 1, intercept = 0,
                linetype = "dashed") +
    labs(x = "ISRIC",
         y = "ISDA",
         title = paste("Scatter:", variable)) +
    theme_minimal()
  
  ### 5. Spatial difference
  spatial_map <- NULL
  
  if (!is.null(map_year)) {
    
    diff_df <- merged %>%
      filter(Year == map_year)
    
    spatial_map <- ggplot(diff_df,
                          aes(Long, Lat,
                              fill = ISDA - ISRIC)) +
      geom_tile() +
      scale_fill_gradient2() +
      coord_equal() +
      labs(title = paste(variable, "Spatial Difference ISDA - ISRIC:", map_year),
           fill = "Difference") +
      theme_minimal()
  }

  return(list(
    overall_metrics = overall,
    yearly_metrics = yearly_summary,
    timeseries_metrics = timeseries_metrics,
    timeseries_plot = timeseries_plot,
    scatter_plot = scatter_plot,
    spatial_map = spatial_map,
    merged_data = merged
  ))
}
