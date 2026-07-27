### Rank planting dates for each pixel and cultivar based on yields
add_date_rank <- function(df, metric = "HWAH") {
  df %>%
    group_by(XLAT, LONG, Cultivar) %>%
    mutate(Date_Rank = dplyr::row_number(dplyr::desc(.data[[metric]]))) %>%
    ungroup()
}


### Rank planting-date-cultivar combination for each pixel based on a chosen metric
add_combination_rank <- function(df, metric = "HWAH") {
  df %>%
    dplyr::group_by(XLAT, LONG) %>%
    dplyr::mutate(
      Combination_Rank = dplyr::row_number(dplyr::desc(.data[[metric]]))) %>%
    dplyr::ungroup()
}


### Plot maps of preferred planting dates for top 3 highest yields by cultivar
plot_planting_date_gradients <- function(
    df, country_name = "Rwanda", output_dir = ".", file_prefix = "") {
  plot_df <- df %>%
    dplyr::mutate(
      
      PDAT_clean = as.Date(PDAT)
    ) %>%
    
    dplyr::filter(Date_Rank <= 3)
  
  # Build the ordered factor labels for 4x3 plot rows/columns
  plot_df <- plot_df %>%
    dplyr::mutate(
      Rank_Label = factor(
        paste("Rank", Date_Rank), 
        levels = c("Rank 1", "Rank 2", "Rank 3")
      ),
      Cultivar = factor(
        Cultivar,
        # Not every crop has all 4 maturity classes (e.g. Potato/Wheat only
        # have Short/Medium/Long) - keep whichever are actually present, in
        # the canonical short-to-long order.
        levels = intersect(c("Short", "Medium", "Long", "Longer"), unique(as.character(Cultivar)))
      )
    )
  
  
  # Update the Rank_Label based on the input data
  plot_df <- plot_df %>%
    dplyr::mutate(
      Rank_Label = factor(
        dplyr::case_when(
          Date_Rank == 1 ~ "Top Recommendation",
          Date_Rank == 2 ~ "Second Choice",
          Date_Rank == 3 ~ "Third Choice"
        ),
        levels = c("Top Recommendation", "Second Choice", "Third Choice")
      )
    )
  
  # Fetch the requested country outline map
  country_outline <- ggplot2::map_data("world", region = country_name)
  
  # Calculate calendar math directly from the dynamic data boundaries
  min_date <- min(plot_df$PDAT_clean, na.rm = TRUE)
  max_date <- max(plot_df$PDAT_clean, na.rm = TRUE)
  mid_date <- min_date + (max_date - min_date) / 2
  date_breaks <- c(min_date, mid_date, max_date)
  
  # Generate the map
  rec <- ggplot() +
    geom_tile(data = plot_df, aes(x = LONG, y = XLAT, fill = as.numeric(PDAT_clean))) +
    geom_path(data = country_outline, aes(x = long, y = lat, group = group), 
              color = "black", linewidth = 0.4, inherit.aes = FALSE) +
    
    facet_grid(Rank_Label ~ Cultivar, scales = "fixed") +
    
    # X Axis
    scale_x_continuous(
      breaks = scales::breaks_pretty(n = 3),
      labels = function(x) paste0(abs(x), "°", ifelse(x >= 0, "E", "W"))
    ) +
    
    # Y Axis
    scale_y_continuous(
      breaks = scales::breaks_pretty(n = 4),
      labels = function(y) paste0(abs(y), "°", ifelse(y >= 0, "N", "S"))
    ) +
    
    scale_fill_gradient2(
      name = "Planting Date",
      low = "dodgerblue4",        
      mid = "gold",               
      high = "firebrick",         
      midpoint = as.numeric(mid_date),
      breaks = as.numeric(date_breaks),
      labels = format(date_breaks, "%b %d")
    ) +
    
    coord_equal() +
    theme_bw() +
    labs(x = NULL, y = NULL) + 
    theme(
      
      strip.background = element_blank(),
      strip.text = element_text(face = "bold"),
      
      legend.position = "right", 
      legend.key.height = unit(1.5, "cm"),
      axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
    )
  
  plot_path <- file.path(output_dir, paste0(file_prefix, "planting_date_gradients.png"))
  ggplot2::ggsave(
    filename = plot_path,
    plot = rec,
    width = 10,
    height = 8,
    dpi = 300
  )
  message("Planting date plot saved to ", plot_path)
  
}


### Plot maps of top 3-highest yields by cultivar
plot_yield_gradients <- function(
    df, yield_col = "HWAH", country_name = "Rwanda", output_dir = ".", file_prefix = "") {
  plot_df <- df %>%
    dplyr::mutate(
      
      PDAT_clean = as.Date(PDAT)
    ) %>%
    
    dplyr::filter(Date_Rank <= 3)
  
  # Build the ordered factor labels for 4x3 plot rows/columns
  plot_df <- plot_df %>%
    dplyr::mutate(
      Rank_Label = factor(
        paste("Rank", Date_Rank), 
        levels = c("Rank 1", "Rank 2", "Rank 3")
      ),
      Cultivar = factor(
        Cultivar,
        # Not every crop has all 4 maturity classes (e.g. Potato/Wheat only
        # have Short/Medium/Long) - keep whichever are actually present, in
        # the canonical short-to-long order.
        levels = intersect(c("Short", "Medium", "Long", "Longer"), unique(as.character(Cultivar)))
      )
    )
  # Update the Rank_Label based on the input data
  plot_df <- plot_df %>%
    dplyr::mutate(
      Rank_Label = factor(
        dplyr::case_when(
          Date_Rank == 1 ~ "Top Recommendation",
          Date_Rank == 2 ~ "Second Choice",
          Date_Rank == 3 ~ "Third Choice"
        ),
        levels = c("Top Recommendation", "Second Choice", "Third Choice")
      )
    )
  
  # Fetch the requested country outline map
  country_outline <- ggplot2::map_data("world", region = country_name)
  
  # Use data masking to evaluate the chosen yield column safely
  max_yield <- max(plot_df[[yield_col]], na.rm = TRUE)
  yield_breaks <- seq(0, max_yield, length.out = 4)
  
  # Generate the map
  yields <- ggplot() +
    geom_tile(data = plot_df, aes(x = LONG, y = XLAT, fill = .data[[yield_col]])) +
    geom_path(data = country_outline, aes(x = long, y = lat, group = group), 
              color = "black", linewidth = 0.4, inherit.aes = FALSE) +
    
    facet_grid(Rank_Label ~ Cultivar, scales = "fixed") +
    
    # X & Y Axis scales
    scale_x_continuous(
      breaks = scales::breaks_pretty(n = 3),
      labels = function(x) paste0(abs(x), "°", ifelse(x >= 0, "E", "W"))
    ) +
    scale_y_continuous(
      breaks = scales::breaks_pretty(n = 4),
      labels = function(y) paste0(abs(y), "°", ifelse(y >= 0, "N", "S"))
    ) +
    

    scale_fill_gradientn(
      name = "Harvested Yield",
      colors = c("dodgerblue4", "gold", "firebrick"),
      breaks = scales::breaks_pretty(n = 4),
      labels = scales::label_comma(accuracy = 1)
    ) +
    
    coord_equal() +
    theme_bw() +
    labs(x = NULL, y = NULL) + 
    theme(
      strip.background = element_blank(),
      strip.text = element_text(face = "bold"),
      legend.position = "right", 
      legend.key.height = unit(1.5, "cm"),
      axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
    )
  
  plot_path <- file.path(output_dir, paste0(file_prefix, "yield_by_pdate_cultivar.png"))
  ggplot2::ggsave(
    filename = plot_path,
    plot = yields,
    width = 10,
    height = 8,
    dpi = 300
  )
  
  message("Yield plot by planting dates and cultivars saved to ", plot_path)
}


### Get statistics for DSSAT results
summarize_and_save_dssat <- function(
    df, outputs = c("HWAH", "CWAM", "WUE"), output_dir = ".", file_prefix = "") {
  
  # Grouping
  group_vars <- c("Cultivar", "PDAT")
  
  missing_vars <- setdiff(outputs, names(df))
  if (length(missing_vars) > 0) {
    stop("The following requested output variables do not exist in df: ", 
         paste(missing_vars, collapse = ", "))
  }
  
  # Compute stats for requested output variables
  summary_df <- df %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_vars))) %>%
    dplyr::summarise(
      n_simulations = dplyr::n(),
      
      # Track crop failure rate (where MDAT failed to simulate)
      maturity_failure_rate_pct = (sum(is.na(MDAT)) / dplyr::n()) * 100,
      
      # Compute stats across each requested variable in `outputs`
      dplyr::across(
        dplyr::all_of(outputs),
        list(
          mean   = ~ mean(.x, na.rm = TRUE),
          median = ~ median(.x, na.rm = TRUE),
          sd     = ~ sd(.x, na.rm = TRUE),
          cv_pct = ~ (sd(.x, na.rm = TRUE) / mean(.x, na.rm = TRUE)) * 100,
          p10    = ~ quantile(.x, 0.10, na.rm = TRUE),
          p90    = ~ quantile(.x, 0.90, na.rm = TRUE)
        ),
        .names = "{.col}_{.fn}"
      ),
      .groups = "drop"
    )
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  
  fixed_filename <- paste0(file_prefix, "treatment_summary.csv")
  file_path <- file.path(output_dir, fixed_filename)
  
  write_csv(summary_df, file_path)
  message("Summary statistics successfully saved to: ", file_path)
  
  
  return(summary_df)
}


### Save NC file of top combinations
#
# Writes one CF-conventional variable per physical quantity (cultivar,
# planting_date, <metric>), each with a labeled "rank" dimension, rather than
# stacking all of them into anonymous numbered bands of a single variable.
#
# @param crop, country, forecast_year, season, bc_method: recorded as global
#   attributes so the file is self-describing without its companion CSV/code.
export_top_combinations_nc <- function(
    df, metric = "HWAH", top_n = 5, output_dir = ".", file_prefix = "",
    crop = NA_character_, country = NA_character_, forecast_year = NA_integer_,
    season = NA_integer_, bc_method = NA_character_) {

  # Ensure target directory exists
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # 1. Fixed, canonical cultivar order (not unique()'s arbitrary first-
  #    appearance order) so the same name always gets the same code, and a
  #    legend is embeddable in the file regardless of which subset of
  #    maturity classes this crop has.
  cultivar_order <- intersect(
    c("Short", "Medium", "Long", "Longer"),
    unique(as.character(df$Cultivar[!is.na(df$Cultivar)]))
  )

  # 2. Add ranking across (XLAT, LONG) without grouping by Cultivar
  df_ranked <- df %>%
    add_combination_rank(metric = metric) %>%
    dplyr::filter(Combination_Rank <= top_n) %>%
    dplyr::mutate(
      PDAT_clean = as.Date(PDAT),
      # Days since epoch, not day-of-year: PDAT_doy would alias Dec 31 (365)
      # and Jan 2 (2) as if the January date were earlier, which is a real
      # risk here since the planting window can cross a calendar year.
      PDAT_days_since_epoch = as.numeric(PDAT_clean),
      Cultivar_ID = as.numeric(factor(Cultivar, levels = cultivar_order))
    )

  # 3. Build one multi-layer SpatRaster per quantity, one layer per rank
  build_rank_layers <- function(value_col) {
    layers <- lapply(seq_len(top_n), function(r) {
      rank_df <- df_ranked %>%
        dplyr::filter(Combination_Rank == r) %>%
        dplyr::select(LONG, XLAT, dplyr::all_of(value_col))
      terra::rast(rank_df, type = "xyz", crs = "EPSG:4326")
    })
    rr <- terra::rast(layers)
    terra::depth(rr) <- seq_len(top_n)
    terra::depthName(rr) <- "rank"
    names(rr) <- paste0("rank_", seq_len(top_n))
    rr
  }

  cultivar_rast <- build_rank_layers("Cultivar_ID")
  pdate_rast    <- build_rank_layers("PDAT_days_since_epoch")
  metric_rast   <- build_rank_layers(metric)

  # 4. Combine into one multi-variable dataset - each quantity keeps its own
  #    name, units and long_name instead of being flattened into one variable.
  sds_obj <- terra::sds(cultivar_rast, pdate_rast, metric_rast)
  names(sds_obj) <- c("cultivar", "planting_date", metric)
  cultivar_legend <- paste(seq_along(cultivar_order), cultivar_order, sep = "=", collapse = ", ")
  terra::units(sds_obj) <- c(
    paste0("categorical code (", cultivar_legend, ")"),
    "days since 1970-01-01",
    if (metric %in% c("HWAH", "CWAM")) "kg/ha" else "unknown"
  )
  terra::longnames(sds_obj) <- c(
    "Recommended cultivar maturity class (categorical code, see units for legend)",
    "Recommended planting date",
    paste0("Simulated ", metric, " for the recommended cultivar/date combination, rank ", 1, "-", top_n)
  )

  # 5. Export to NetCDF, named so it's identifiable outside its own folder
  file_path <- file.path(output_dir, paste0(
    file_prefix, "top_", top_n, "_", metric, "_combination_recommendation.nc"))

  # Note: terra::writeCDF's `atts` values must not contain commas - it splits
  # on them when parsing "key=value" pairs, so the cultivar legend (which does
  # contain commas) is deliberately left out here; it's already correctly
  # attached to the cultivar variable itself as flag_values/flag_meanings.
  global_atts <- c(
    paste0("crop=", crop),
    paste0("country=", country),
    paste0("forecast_year=", forecast_year),
    paste0("season=", season),
    paste0("bias_correction_method=", bc_method),
    paste0("rank_meaning=rank 1 is the best combination by ", metric, " at each pixel"),
    paste0("generated=", as.character(Sys.time()))
  )

  terra::writeCDF(
    sds_obj,
    filename = file_path,
    overwrite = TRUE,
    atts = global_atts
  )

  # 6. terra's writeCDF has no per-variable custom-attribute hook, so patch
  #    in proper CF flag_values/flag_meanings on the cultivar variable, and a
  #    calendar attribute on the date variable, directly via ncdf4.
  nc <- ncdf4::nc_open(file_path, write = TRUE)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  ncdf4::ncatt_put(nc, "cultivar", "flag_values", as.integer(seq_along(cultivar_order)))
  ncdf4::ncatt_put(nc, "cultivar", "flag_meanings", paste(cultivar_order, collapse = " "))
  ncdf4::ncatt_put(nc, "planting_date", "calendar", "standard")
  ncdf4::ncatt_put(nc, "rank", "long_name", paste0("Recommendation rank (1 = best by ", metric, ")"))
  ncdf4::ncatt_put(nc, "rank", "units", "1")

  message("Exported Top ", top_n, " NetCDF (cultivar/planting_date/", metric, ") to: ", file_path)
  invisible(file_path)
}


### Save CSV file of top combinations
export_top_combinations_csv <- function(
    df, metric = "HWAH", top_n = 5, output_dir = ".", file_prefix = "") {
  
  # Ensure target directory exists
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # 1. Rank combinations and select the top N per pixel
  df_ranked <- df %>%
    add_combination_rank(metric = metric) %>%
    dplyr::filter(Combination_Rank <= top_n) %>%
    dplyr::mutate(
      PDAT_clean = format(as.Date(PDAT), "%Y-%m-%d")
    )
  
  # 2. Reshape from long to wide format (1 row per XLAT, LONG pixel)
  df_wide <- df_ranked %>%
    dplyr::select(
      XLAT, LONG, Combination_Rank, Cultivar, PDAT_clean, Metric_Value = .data[[metric]]
    ) %>%
    tidyr::pivot_wider(
      id_cols = c(XLAT, LONG),
      names_from = Combination_Rank,
      values_from = c(Cultivar, PDAT_clean, Metric_Value),
      names_glue = "{.value}_Rank_{Combination_Rank}"
    )
  
  # 3. Interleave columns by rank (Rank 1 Cultivar, Date, Metric -> Rank 2 Cultivar, Date, Metric...)
  ordered_cols <- c("XLAT", "LONG")
  for (r in 1:top_n) {
    ordered_cols <- c(
      ordered_cols,
      paste0("Cultivar_Rank_", r),
      paste0("PDAT_clean_Rank_", r),
      paste0("Metric_Value_Rank_", r)
    )
  }
  
  # Select available columns (handles cases where a pixel has fewer than top_n options)
  existing_cols <- intersect(ordered_cols, names(df_wide))
  
  df_output <- df_wide %>%
    dplyr::select(dplyr::all_of(existing_cols)) %>%
    # Rename Metric_Value columns to match the actual metric name (e.g., HWAH_Rank_1)
    dplyr::rename_with(
      ~ gsub("Metric_Value", metric, .x),
      dplyr::starts_with("Metric_Value")
    ) %>%
    dplyr::rename_with(
      ~ gsub("PDAT_clean", "PDAT", .x),
      dplyr::starts_with("PDAT_clean")
    ) %>%
    dplyr::arrange(XLAT, LONG)
  
  # 4. Save to CSV
  file_path <- file.path(output_dir, paste0(
    file_prefix, "top_", top_n, "_", metric, "_combination_recommendation.csv"))
  
  write.csv(df_output, file = file_path, row.names = FALSE)
  
  message("Exported Top ", top_n, " CSV recommendations to: ", file_path)
  
  return(df_output)
}

