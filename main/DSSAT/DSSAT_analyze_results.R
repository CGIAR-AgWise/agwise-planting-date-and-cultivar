packages_required <- c('dplyr', 'ggplot2', 'rlang', 'readr', 'scales', 'tidyterra')
invisible(lapply(packages_required, load_or_install))

source(paste0(project_root, "/Scripts/generic/DSSAT/helpers_DSSAT_analyze_results.R"))


run_full_soil_comparison <- function(
    project_root, country, useCaseName, Crop, AOI = TRUE, season, 
    variable = "HWAH", lat = NULL, lon = NULL, map_year = NULL) {
  

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


# TODO Add this function that calls all the helpers
run_fertilizer_comparison <- function(
    all_results, variable = HWAH, by_treatment = T, ...) {
  summary_DSSAT_results(all_results, variable = variable, by_treatment = T)
  
  plot_DSSAT_pixel(all_results, lat = lat_pixel, lon = lon_pixel,
                   variable = variable)
  
  plot_aggregate(all_results, variable = variable)
  
  plot_map(
    all_results, treatment = treatment_to_plot, year_selected = map_year,
    variable = variable)
}


# Scatter plot by pixel, variety and planting date
plot_yield_by_pixel <- function(
    save_path, df, pixels_to_plot, zone, ncol = 5, yield_col = "HWAH") {

  if (!dir.exists(save_path)) {
    dir.create(save_path, recursive = T)
  }
  
  df$pixel_num <- as.numeric(gsub(".*EXTE(\\d+).*", "\\1", df$file_name))
  
  df$PDAT <- as.Date(df$PDAT)
  
  df_filtered <- df[df$pixel_num %in% pixels_to_plot, ]
  
  # Quick sanity check to ensure data exists for specified pixels
  if (nrow(df_filtered) == 0) {
    stop("No data found matching the provided pixel numbers.")
  }
  
  # Ensure Variety is treated as a factor so ggplot handles discrete shapes automatically
  df_filtered$Variety <- as.factor(df_filtered$Variety)
  
  df_filtered$`Coords` <- paste(df_filtered$Lat, ",", df_filtered$Long)

  # 4. Generate the grid of scatter subplots
  # Removing scale_shape_manual allows ggplot2 to automatically select the shapes
  p <- ggplot(df_filtered, aes(x = PDAT, y = .data[[yield_col]], shape = Variety)) +
    geom_point(size = 2.5) +  
    facet_wrap(~ `Coords`, ncol = ncol, labeller = label_both) +
    theme_bw() +
    labs(
      x = "Planting Date",
      y = paste("Yield (", yield_col, ")", sep = ""),
      title = paste("Yield by pixel of AOI in", zone),
      shape = "Variety"
    ) +
    theme(
      legend.position = "bottom",                  # Consolidates into a single shared legend at the bottom
      strip.background = element_rect(fill = "gray95"), # Custom layout for subplot headers
      axis.text.x = element_text(angle = 45, hjust = 1) # Prevents overlapping dates
    )
  
  # 5. Dynamically calculate saving dimensions based on the grid layout size
  num_plots <- length(unique(df_filtered$pixel_num))
  num_rows <- ceiling(num_plots / ncol)
  
  calculated_width <- ncol * 3.5
  calculated_height <- (num_rows * 3) + 1.5  # Extra room for the shared title and legend
  
  # Save the final visualization
  ggsave(
    filename = paste0(save_path, "/yield_by_pixel_pd_var.png"), 
    plot = p, 
    width = calculated_width, 
    height = calculated_height, 
    dpi = 300,
    limitsize = FALSE
  )
  
  message(paste("Plot successfully generated and saved to:", save_path))
}


# Statistics table
generate_dssat_statistics <- function(save_path, df, zone) {
  
  # 1. Ensure output directory exists recursively
  if (!dir.exists(save_path)) {
    dir.create(save_path, recursive = TRUE)
  }
  
  # 2. Extract pixel numbers and create uniform coordinate identifiers
  df$pixel_num <- as.numeric(gsub(".*EXTE(\\d+).*", "\\1", df$file_name))
  df$Coords <- paste(df$Lat, ",", df$Long)
  
  # 3. Identify relevant numerical DSSAT outputs to analyze
  # Skipping outputs that are entirely 0 in your sample (like CNAM, GNAM) but keeping them if present
  dssat_outputs <- c("CWAM", "HWAH", "NDCH", "TMAXA", "TMINA", "SRADA", "PRCP", "ETCP", "ESCP", "WUE")
  # Filter only columns that actually exist in the passed dataframe
  dssat_outputs <- intersect(dssat_outputs, colnames(df))
  
  # Helper function to compute stats for a given grouping
  compute_metrics <- function(data, group_var_name) {
    data %>%
      select(all_of(c(group_var_name, dssat_outputs))) %>%
      pivot_longer(cols = all_of(dssat_outputs), names_to = "Variable", values_to = "Value") %>%
      filter(!is.na(Value)) %>%
      group_by(.data[[group_var_name]], Variable) %>%
      summarise(
        Mean = mean(Value),
        SD = sd(Value),
        CV_percent = (sd(Value) / mean(Value)) * 100,
        Min = min(Value),
        Max = max(Value),
        Count = n(),
        .groups = "drop"
      ) %>%
      rename(Group_Value = .data[[group_var_name]]) %>%
      mutate(Group_Type = group_var_name, Group_Value = as.character(Group_Value))
  }
  
  # 4. Calculate stats for each required observation group
  stats_all     <- df %>% mutate(Group = "All Observations") %>% compute_metrics("Group")
  stats_pixel   <- compute_metrics(df, "Coords")
  stats_variety <- compute_metrics(df, "Variety")
  stats_tnam    <- compute_metrics(df, "TNAM")
  
  # 5. Bind all groupings together into a clean, unified master table
  final_stats_table <- bind_rows(stats_all, stats_pixel, stats_variety, stats_tnam) %>%
    select(Group_Type, Group_Value, Variable, Mean, SD, CV_percent, Min, Max, Count)
  
  # 6. Save the table as a CSV file using your file naming structure
  file_destination <- paste0(save_path, "/dssat_summary_statistics.csv")
  write_csv(final_stats_table, file_destination)
  
  message(paste("Statistics table successfully generated and saved to:", file_destination))
  
  return(final_stats_table)
}


# Average yield map
plot_yield_map <- function(save_path, df, zone, yield_col = "HWAH") {
  
  if (!dir.exists(save_path)) {
    dir.create(save_path, recursive = TRUE)
  }
  
  map_data <- df %>%
    group_by(Lat, Long) %>%
    summarise(
      Avg_Yield = mean(.data[[yield_col]], na.rm = TRUE),
      .groups = "drop"
    )
  
  if (nrow(map_data) == 0) {
    stop("No data found to plot on the map.")
  }
  
  p <- ggplot(map_data, aes(x = Long, y = Lat, fill = Avg_Yield)) +
    geom_tile(color = "white", linewidth = 0.2) + # Distinct thin border around squares
    scale_fill_viridis_c(
      option = "viridis", 
      name = paste("Avg yield (kg/ha)")
    ) +
    coord_quickmap() + 
    theme_minimal() +
    labs(
      x = "Longitude",
      y = "Latitude",
      title = paste("Spatial Distribution of Average Yield in", zone),
      subtitle = paste("Averaged across all planting dates and Varieties"),
      caption = paste("Metric:", yield_col)
    ) +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(color = "gray40", size = 10),
      legend.position = "right",
      legend.title = element_text(size = 10, face = "bold"),
      panel.grid.major = element_line(color = "gray90", linetype = "dashed"),
      panel.grid.minor = element_blank()
    )
  
  ggsave(
    filename = paste0(save_path, "/yield_grid_map_", zone, ".png"), 
    plot = p, 
    width = 7, 
    height = 6, 
    dpi = 300
  )
  
  message(paste("Grid map successfully generated and saved to:", save_path))
}


# Optimal TNAM per pixel
plot_optimal_tnam_map <- function(save_path, df, zone, yield_col = "HWAH") {
  
  # 1. Ensure output directory exists recursively
  if (!dir.exists(save_path)) {
    dir.create(save_path, recursive = TRUE)
  }
  
  # 2. Identify the management option (TNAM) that maximizes yield per pixel
  # Group by coordinate, then extract the row containing the maximum yield
  map_data <- df %>%
    group_by(Lat, Long) %>%
    slice_max(order_by = .data[[yield_col]], n = 1, with_ties = FALSE) %>%
    ungroup()
  
  # Quick validation check
  if (nrow(map_data) == 0) {
    stop("No data found to plot on the map.")
  }
  
  # Convert TNAM to a factor to ensure a discrete classification color scheme
  map_data$TNAM <- as.factor(map_data$TNAM)
  
  # 3. Create the discrete grid tile map
  # Using scale_fill_brewer for a high-contrast discrete palette (e.g., "Set2" or "Dark2")
  p <- ggplot(map_data, aes(x = Long, y = Lat, fill = TNAM)) +
    geom_tile(color = "white", linewidth = 0.2) + # Clean borders around grid cells
    scale_fill_brewer(palette = "Set2", name = "Optimal Planting") +
    coord_quickmap() + 
    theme_minimal() +
    labs(
      x = "Longitude",
      y = "Latitude",
      title = paste("Optimal Planting Window by Pixel in", zone),
      subtitle = paste("Planting date yielding the highest maximum", yield_col)
    ) +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(color = "gray40", size = 10),
      legend.position = "right",
      legend.title = element_text(size = 10, face = "bold"),
      panel.grid.major = element_line(color = "gray90", linetype = "dashed"),
      panel.grid.minor = element_blank()
    )
  
  # 4. Save the map image
  ggsave(
    filename = paste0(save_path, "/optimal_tnam_map_", yield_col, ".png"), 
    plot = p, 
    width = 7.5, 
    height = 6, 
    dpi = 300
  )
  
  message(paste("Optimal TNAM map successfully generated and saved to:", save_path))
}


# Optimal planting date per pixel
plot_planting_date_map <- function(
    save_path, df, zone, yield_col = "HWAH", region_shape = NULL) {
  
  # 1. Ensure output directory exists
  if (!dir.exists(save_path)) {
    dir.create(save_path, recursive = TRUE)
  }
  
  # Ensure PDAT is a true Date object
  df$PDAT <- as.Date(df$PDAT)
  
  # 2. Extract the row with the maximum yield for each unique pixel coordinate
  map_data <- df %>%
    group_by(Lat, Long) %>%
    slice_max(order_by = .data[[yield_col]], n = 1, with_ties = FALSE) %>%
    ungroup()
  
  if (nrow(map_data) == 0) {
    stop("No data found to plot.")
  }
  
  # Find the absolute range of dates in the optimal set to anchor our legend scales
  min_date <- min(map_data$PDAT)
  max_date <- max(map_data$PDAT)
  
  # 3. Base Map Construction (Data Grid)
  p <- ggplot() +
    # Layer 1: The continuous data grid tiles
    geom_tile(data = map_data, aes(x = Long, y = Lat, fill = as.numeric(PDAT)), 
              color = "white", linewidth = 0.2)
  
  # Layer 2: Optional Shapefile Overlay
  if (!is.null(region_shape)) {
    p <- p + geom_spatvector(data = region_shape, fill = NA, color = "black", linewidth = 0.6)
  }
  
  # 4. Styling, Slide Formatting, and Spatial Coordinates Fix
  p <- p +
    scale_fill_viridis_c(
      option = "plasma",
      name = "Optimal Planting Date",
      labels = function(x) format(as.Date(x, origin = "1970-01-01"), "%b %d"),
      breaks = as.numeric(seq(min_date, max_date, length.out = 4))
    ) +
    
    # CRITICAL FIX: Use coord_sf() instead of coord_quickmap() to support vector layers
    coord_sf() + 
    
    theme_minimal(base_size = 14) + 
    labs(
      x = "Longitude",
      y = "Latitude",
      title = paste("Optimal Calendar Planting Dates:", zone),
      subtitle = "Gradient shows dates maximizing crop yield"
    ) +
    theme(
      plot.title = element_text(face = "bold", size = 16, margin = margin(b = 6)),
      plot.subtitle = element_text(color = "gray30", size = 11, margin = margin(b = 15)),
      legend.position = "right",
      legend.title = element_text(size = 11, face = "bold"),
      legend.text = element_text(size = 10),
      panel.grid.major = element_line(color = "gray92", linetype = "solid"),
      panel.grid.minor = element_blank(),
      plot.background = element_rect(fill = "white", color = NA)
    )
  
  # 5. Save in widescreen 16:9 format
  file_destination <- paste0(save_path, "/cont_ptimal_calendar_dates.png")
  ggsave(
    filename = file_destination, 
    plot = p, 
    width = 10, 
    height = 5.625, 
    dpi = 300
  )
  
  message(paste("Map with boundary overlay successfully saved to:", file_destination))
}
