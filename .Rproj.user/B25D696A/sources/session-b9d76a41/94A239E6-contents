## 00_config_GHA.R

country_code <- "KEN"
country <- "Kenya"
useCaseName <- "KALRO_app2"
Crop <- "Maize"


base_dir <- paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_", useCaseName, "/", Crop, "/Forecast")
country_dir <- file.path(base_dir, country_code)

dir_raw_obs <- file.path(country_dir, "raw", "Observation")
dir_raw_model <- file.path(country_dir, "raw", "daily_model_data")

dir_bc_hcst <- file.path(country_dir, "processed", "bias_corrected", "hindcast")
dir_bc_fcst <- file.path(country_dir, "processed", "bias_corrected", "forecast")

dir_ext_hcst <- file.path(country_dir, "processed", "extremes", "hindcast")
dir_ext_fcst <- file.path(country_dir, "processed", "extremes", "forecast")

dir_scores <- file.path(country_dir, "scores")
dir_logs <- file.path(country_dir, "logs")

dirs_to_create <- c(
  dir_raw_obs, dir_raw_model,
  dir_bc_hcst, dir_bc_fcst,
  dir_ext_hcst, dir_ext_fcst,
  dir_scores, dir_logs
)

for (d in dirs_to_create) if (!dir.exists(d)) dir.create(d, recursive = TRUE)


