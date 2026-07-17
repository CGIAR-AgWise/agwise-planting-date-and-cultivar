add_date_rank <- function(df) {
  df %>%
    group_by(XLAT, LONG, Cultivar) %>%
    mutate(Date_Rank = dense_rank(desc(HWAH))) %>%
    ungroup()
}


plot_planting_date_gradients <- function(df, country_name = "Rwanda") {
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
        levels = c("Short", "Medium", "Long", "Longer")
      )
    )
  
  
  # Update the Rank_Label based on the input data
  df <- df %>%
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
  min_date <- min(df$PDAT_clean, na.rm = TRUE)
  max_date <- max(df$PDAT_clean, na.rm = TRUE)
  mid_date <- min_date + (max_date - min_date) / 2
  date_breaks <- c(min_date, mid_date, max_date)
  
  # Generate the map
  ggplot() +
    geom_tile(data = df, aes(x = Long, y = Lat, fill = as.numeric(PDAT_clean))) +
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
}


plot_yield_gradients <- function(df, yield_col = "HWAH", country_name = "Rwanda") {
  df <- df %>%
    dplyr::mutate(
      
      PDAT_clean = as.Date(PDAT)
    ) %>%
    
    dplyr::filter(Date_Rank <= 3)
  
  # Build the ordered factor labels for 4x3 plot rows/columns
  df <- df %>%
    dplyr::mutate(
      Rank_Label = factor(
        paste("Rank", Date_Rank), 
        levels = c("Rank 1", "Rank 2", "Rank 3")
      ),
      Cultivar = factor(
        Cultivar, 
        levels = c("Short", "Medium", "Long", "Longer")
      )
    )
  # Update the Rank_Label based on the input data
  df <- df %>%
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
  max_yield <- max(df[[yield_col]], na.rm = TRUE)
  yield_breaks <- seq(0, max_yield, length.out = 4)
  
  # Generate the map
  ggplot() +
    geom_tile(data = df, aes(x = Long, y = Lat, fill = .data[[yield_col]])) +
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
      name = yield_col,
      colors = c("dodgerblue4", "gold", "firebrick"),
      breaks = yield_breaks,
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
}


# dates_map <- plot_planting_date_gradients(plot_df, country)
# print(dates_map)
# 
# yields_map <- plot_yield_gradients(plot_df, "HWAH", country)
# print(yields_map)