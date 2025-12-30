############################
### Merge DSSAT results ####
############################
source("~/agwise-planting-date-and-cultivar/Script/generic/DSSAT/merge_DSSAT_output.R")

# Settings
country <- "Kenya"
useCaseName <- "KALRO_app2"
Crop <- "Maize"
fert_file <- "fert_fact_KEN.csv"
season <- 1

# Run the code. Normally nothing needs to be changed below this line
path.to.temdata <- paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", 
                          country, "_", useCaseName, "/", Crop, 
                          "/Landing/DSSAT/")

fert_df <- read_csv(paste0(path.to.temdata, fert_file), show_col_types = FALSE,
                    progress = FALSE)

varietyids <- unique(fert_df$INGENO)

merge_DSSAT_output(country = country, useCaseName = useCaseName, Crop = Crop,
                   AOI = TRUE, season = season, varietyids = varietyids,
                   zone_folder = TRUE, level2_folder = FALSE)



#####################################################
### Produce simple response statistics and plots ####
#####################################################
dir_path <- paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",
                   useCaseName, "/", Crop, "/result/DSSAT/AOI/")
dssat_data <- readRDS(paste0(dir_path, "useCase_", country, "_", useCaseName,
                             "_", Crop, "_AOI_season_", season, ".RDS"))

long_term_avg_dssat_data <- dssat_data %>%
  mutate(
    HDAT = as.Date(HDAT),
    Year = year(HDAT),
    N_rate = as.numeric(str_extract(TNAM, "(?<=^)[0-9]+(?=N)")),
    P_rate = as.numeric(str_extract(TNAM, "(?<=\\.)[0-9]+(?=P)")),
    fert_trt = sub("@.*", "", TNAM),
    plant_trt = sub(".*@", "", TNAM),
    lat_lon = paste(XLAT, LONG, sep = ", ")) %>%
  group_by(fert_trt, lat_lon, Variety, plant_trt, N_rate, P_rate) %>%
  dplyr::summarise(HWAH_avg = mean(HWAH), .groups = "drop") #%>%
# pivot_wider(
#   names_from = N_rate,
#   values_from = HWAH_avg,
#   names_prefix = "N_"
# )


write_csv(long_term_avg_dssat_data,
          paste0(dir_path, "long_term_avg_yields.csv"))

long_for_plot <- long_term_avg_dssat_data

for (variety in unique(long_term_avg_dssat_data$Variety)) {
  for (location in long_term_avg_dssat_data$lat_lon[1:5]) {
    for (P_rate_i in unique(long_term_avg_dssat_data$P_rate)) {
      df_loc <- long_for_plot %>% filter(lat_lon == location,
                                         Variety == variety,
                                         P_rate == P_rate_i) %>%
        group_by(fert_trt, lat_lon, Variety, N_rate, P_rate) %>%
        dplyr::summarise(avg_yield = mean(HWAH_avg))
      
      p <- ggplot(df_loc, aes(x = N_rate, y = avg_yield)) +
        geom_line() +
        geom_point() +
        theme_bw() +
        labs(title = paste0("Location: ", location, ". Variety: ", variety, 
                            ". P rate: ", P_rate_i, " kg/ha"),
             x = "N rate (kg/ha)",
             y = "Yield (kg/ha)")
      
      ggsave(
        filename = paste0(dir_path, "avg_yield_", location, "_", variety, "_P",
                          P_rate_i, ".png"),
        plot = p, width = 8, height = 6, dpi = 300
      )
      
      # Boxplots 
      # df_loc <- long_for_plot %>% filter(lat_lon == location,
      #                                    Variety == variety,
      #                                    P_rate == P_rate_i)
      # p <- ggplot(df_loc, aes(x = factor(N_rate), y = HWAH_avg)) +
      #   geom_boxplot(fill = "lightblue", color = "darkblue") +
      #   theme_bw() +
      #   labs(
      #     title = paste("Location:", location, "Variety:", variety),
      #     x = "N rate (kg/ha)",
      #     y = "Yield (kg/ha)"
      #   )
      
      # ggsave(
      #   filename = paste0(dir_path, "avg_yield_", location, "_", variety, "_P",
      #                     P_rate_i, ".png"),
      #   plot = p, width = 8, height = 6, dpi = 300
      # )
      
      # print(p)
    }
  }
}

# TODO: Update this part
# Separate first and second half of the data
# years_sorted <- sort(unique(year(as.Date(dssat_data$HDAT))))
# half_n <- floor(length(years_sorted) / 2)
# first_half_years <- years_sorted[1:half_n]
# second_half_years <- years_sorted[(half_n+1):length(years_sorted)]
# 
# first_half_avg_dssat_data <- dssat_data %>%
#   mutate(
#     HDAT = as.Date(HDAT),
#     Year = year(HDAT),
#     N_rate = as.numeric(str_extract(TNAM, "^[0-9]+")),
#     lat_lon = paste(XLAT, LONG, sep = ", ")
#   ) %>%
#   filter(Year %in% first_half_years) %>%
#   group_by(N_rate, lat_lon, Variety) %>%
#   summarise(HWAH_avg = mean(HWAH), .groups = "drop") %>%
#   pivot_wider(
#     names_from = N_rate,
#     values_from = HWAH_avg,
#     names_prefix = "N_"
#   )
# 
# write_csv(first_half_avg_dssat_data,
#           paste0(dir_path, "first_half_avg_yields.csv"))
# 
# 
# second_half_avg_dssat_data <- dssat_data %>%
#   mutate(
#     HDAT = as.Date(HDAT),
#     Year = year(HDAT),
#     N_rate = as.numeric(str_extract(TNAM, "^[0-9]+")),
#     lat_lon = paste(XLAT, LONG, sep = ", ")
#   ) %>%
#   filter(Year %in% second_half_years) %>%
#   group_by(N_rate, lat_lon, Variety) %>%
#   summarise(HWAH_avg = mean(HWAH), .groups = "drop") %>%
#   pivot_wider(
#     names_from = N_rate,
#     values_from = HWAH_avg,
#     names_prefix = "N_"
#   )
# 
# write_csv(second_half_avg_dssat_data,
#           paste0(dir_path, "second_half_avg_yields.csv"))
# 
# 
# # Combine first and second half to plot them together
# long_first <- first_half_avg_dssat_data %>%
#   pivot_longer(
#     cols = starts_with("N_"),
#     names_to = "N_rate",
#     values_to = "HWAH_avg"
#   ) %>%
#   mutate(
#     N_rate = as.numeric(gsub("N_", "", N_rate)),
#     period = paste(as.character(first_half_years[1]), 
#                    as.character(first_half_years[half_n]), sep = "-")
#   )
# 
# # Second half
# long_second <- second_half_avg_dssat_data %>%
#   pivot_longer(
#     cols = starts_with("N_"),
#     names_to = "N_rate",
#     values_to = "HWAH_avg"
#   ) %>%
#   mutate(
#     N_rate = as.numeric(gsub("N_", "", N_rate)),
#     period = paste(as.character(second_half_years[1]), 
#                    as.character(second_half_years[length(second_half_years)]),
#                    sep = "-")
#   )
# 
# # Combine first and second half period
# long_both <- bind_rows(long_first, long_second)
# 
# # Plot first and second half period yields
# for (variety in unique(long_term_avg_dssat_data$Variety)){
#   for (location in long_both$lat_lon[1:5]) {
#     
#     df_loc <- long_both %>% filter(lat_lon == location)
#     
#     p <- ggplot(df_loc,
#                 aes(x = N_rate,
#                     y = HWAH_avg,
#                     color = period,
#                     group = period)) +
#       geom_line(linewidth = 1.1) +
#       geom_point(size = 2) +
#       theme_bw() +
#       labs(
#         title = paste("Location:", location, "Variety:", variety),
#         x = "N rate (kg/ha)",
#         y = "Yield (kg/ha)",
#         color = "Period"
#       ) +
#       scale_color_manual(values = c("2001-2011" = "blue",
#                                     "2012-2022" = "red"))
#     
#     print(p)
#   }
# }

