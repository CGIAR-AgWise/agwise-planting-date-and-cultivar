###############################################################################
# Script: readGeo_CM_zone.R
# Purpose: Create weather and soil files in DSSAT format.
#
# Authors: Alvaro Carmona-Cabrero, Jemal S. Ahmed (jemal.ahmed@cgiar.org), P. Moreno, A. Sila, S. Mkuhlani, E. Bendito Garcia
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-06-07
###############################################################################


### Source helper functions
source(paste0(project_root, '/main/DSSAT/helpers_readGeo_CM_zone.R'))


#' Function that creates the soil and weather file for one location/folder
#'
#' @param i last digits of the folder (folder ID) and pixel number
#' @param country country name
#' @param path.to.extdata working directory to save the weather and soil data in DSSAT format
#' @param path.to.temdata directory with template weather and soil data in DSSAT format
#' @param TemperatureMax dataframe with the maximum data for all the locations
#' @param TemperatureMin dataframe with the minimum temperature data for all the locations
#' @param SolarRadiation dataframe with the solar radiation data for all the locations
#' @param Rainfall dataframe with the rainfall data for all the locations
#' @param RelativeHum dataframe with the relative humidity data for all the locations
#' @param coords dataframe with the locations and metadata
#' @param Soil dataframe with the soil data information
#' @param AOI True if the data is required for target area, and false if it is for trial sites
#' @return soil and weather file in DSSAT format
#' @export
#'
#' @examples process_grid_element(1)
            
process_grid_element <- function(
    i, country, path.to.extdata, path.to.temdata, TemperatureMax,
    TemperatureMin, SolarRadiation, Rainfall, coords, Soil, AOI, varietyid,
    zone, level2 = NA, Depth = c(5, 15, 30, 60, 100, 200)) {

  pathOUT <- define_pathOUT(path.to.extdata = path.to.extdata, i = i,
                            zone = zone, level2 = level2)
  setwd(pathOUT)

  ### Creation of DSSAT WTH file ###
  TemperatureMax_i <- filter_by_coord(TemperatureMax, coords, i)
  TemperatureMin_i <- filter_by_coord(TemperatureMin, coords, i)
  SolarRadiation_i <- filter_by_coord(SolarRadiation, coords, i)
  Rainfall_i <- filter_by_coord(Rainfall, coords, i)
 
  # Location name
  location <- unique(TemperatureMax_i$NAME_2)
  
  # Pivot longer
  TemperatureMax_i <- pivot_weather(
    TemperatureMax_i, value_name = "TMAX", AOI = AOI)
  TemperatureMin_i <- pivot_weather(
    TemperatureMin_i, value_name = "TMIN", AOI = AOI)
  SolarRadiation_i <- pivot_weather(
    SolarRadiation_i, value_name = "SRAD", AOI = AOI)
  Rainfall_i <- pivot_weather(
    Rainfall_i, value_name = "RAIN", AOI = AOI)

  # Creation of DSSAT weather file
  tst <- build_DSSAT_WTH(TMAX = TemperatureMax_i, TMIN = TemperatureMin_i, 
                         SRAD = SolarRadiation_i, RAIN = Rainfall_i)

  # Add station information
  general_new <- get_DSSAT_WTH_header(tst = tst, location = location, i = i, coords = coords)
  attr(tst, "GENERAL") <- general_new

  
  ### Write DSSAT file ###
  DSSAT::write_wth(tst, paste0("WHTE", formatC(width = 4, (as.integer(i)), flag = "0"), ".WTH"))
  
  
  ### Creation of DSSAT SOIL.SOL file ###
  lon_i <- as.numeric(coords[i, 1])
  lat_i <- as.numeric(coords[i, 2])
  
  # Get soil ISRIC data from server
  LL15 <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                              var = "PWP", Depth = Depth, scale = 1)
  DUL <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                             var = "FC", Depth = Depth, scale = 1)
  SAT <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                             var = "SWS", Depth = Depth, scale = 1)
  SKS <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                             var = "KS", Depth = Depth, scale = 10)
  SSS <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                             var = "KS", Depth = Depth, scale = 10, round_digits = 1)
  BDM <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                       var = get_var_name(var = "bdod", Depth), Depth = Depth)
  LOC <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                       var = get_var_name(var = "soc", Depth), Depth = Depth, scale = 10)
  LCL <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                       var = get_var_name(var = "clay", Depth), Depth = Depth)
  LSI <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                       var = get_var_name(var = "silt", Depth), Depth = Depth)
  Sand <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                        var = get_var_name(var = "sand", Depth), Depth = Depth)
  LNI <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                       var = get_var_name("nitrogen", Depth), Depth = Depth, scale = 10)
  LHW <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                       var = get_var_name("phh2o", Depth), Depth = Depth)
  LDR <- get_site_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                             var = "LDR")
  CEC <- get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i, 
                       var = get_var_name(var = "cec", Depth), Depth = Depth)
  
  # Try get P variables
  soil_p <- FALSE
  P_data <- NULL
  
  ### Try to get P variables
  SLPX <- NA
  SLPT <- NA
  try({
    SLPX <- tryCatch(
      get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i,
                    var = get_var_name(var = "P", Depth), Depth = Depth, round_digits = 2),
      error = function(e) {
        message("SLPX not available: ", e$message)
        rep(-99, length(Depth))  # fill with DSSAT missing value
      }
    )
    
    SLPT <- tryCatch(
      get_depth_var(Soil = Soil, lon = lon_i, lat = lat_i,
                    var = "Ptot", Depth = Depth, round_digits = 1),
      error = function(e) {
        message("SLPT not available: ", e$message)
        rep(-99, length(Depth))  # fill with DSSAT missing value
      }
    )
    
    # Mark soil_p TRUE if at least one variable is available
    if (!(all(SLPX == -99) & all(SLPT == -99))) {
      soil_p <- TRUE
    }
    
    # Build P_data with all DSSAT-required columns
    na_vars <- c("SLPO", "CACO3", "SLAL", "SLFE", "SLMN", "SLPA", "SLPB", 
                 "SLKE", "SLMG", "SLNA", "SLSU", "SLEC", "SLCA")
    
    P_data <- data.frame(matrix(-99, nrow = length(Depth),
                                ncol = length(na_vars))) %>%
      mutate(SLPX = SLPX,
             SLPT = SLPT)
    colnames(P_data) <- c(na_vars, "SLPX", "SLPT")
    
  }, silent = TRUE)
  
  # Get Soil texture, albedo, Lower Runoff limit ~ Curve Number, Soil Layer Upper Limit and Root Growth Factor
  max_depths <- depths_to_numeric(Depth)
  texture_list <- get_texture_params(
    LCL = LCL, LSI = LSI, Sand = Sand, Depth = max_depths)
  texture <- texture_list$texture
  texture_soil <- texture_list$texture_soil
  ALB <- texture_list$ALB
  LRO <- texture_list$LRO
  SLU <- texture_list$SLU
  RGF <- texture_list$RGF
  
  # Read DSSAT soil template
  ex_profile <- suppressWarnings(DSSAT::read_sol(
    paste(path.to.temdata, "soil.sol", sep = "/"), id_soil = "IBPN910025"))

  # Modify DSSAT soil profile
  soilid <- modify_ex_profile(
    template_ex_profile = ex_profile, texture_soil = texture_soil, 
    texture = texture, location = location, country = country, lat = lat_i, 
    lon = lon_i, ALB = ALB, SLU = SLU, LRO = LRO, LDR = LDR, Depth = max_depths, 
    LL15 = LL15, SAT = SAT, DUL = DUL, SSS = SSS, BDM = BDM, LOC = LOC, 
    LCL = LCL, LSI = LSI, LNI = LNI, LHW = LHW, CEC = CEC, RGF = RGF, i = i,
    soil_p = soil_p, P_data = P_data
  )

    DSSAT::write_sol(soilid, 'SOIL.SOL', append = FALSE)
}

  
# Reading the weather and soil data for crop model and transforming it to DSSAT format
#'
#' @param country country name
#' @param useCaseName use case name  name
#' @param Crop the name of the crop to be used in creating file name to write out the result.
#' @param AOI True if the data is required for target area, and false if it is for trial sites
#' @param season when data is needed for more than one season, this needs to be provided to be used in the file name
#' @param pathIn_zone TRUE if the input data (in geo_4cropModel) are organized by zone or province and false if it is just one file 
#' @param Depth list of soil depths information 
                 
#' @return weather and soil data in DSSAT format
#' @export
#'
#' @examples readGeo_CM(country = "Kenya",  useCaseName = "KALRO", Crop = "Maize", AOI = TRUE, season=1, Province = "Kiambu")
readGeo_CM_zone <- function(
  country, useCaseName, Crop, project_root, AOI = FALSE, season = 1, zone,
  level2 = NA, varietyid, pathIn_zone = TRUE,
    Depth = c(5, 15, 30, 60, 100, 200), Forecast = FALSE, 
    forecast_inputs = NULL,
    datasourcing_path = "~/agwise-datasourcing/dataops/datasourcing"
    )
  {

  # General input path with all the weather data
  # Define data input path based on the organization of the folders by zone and level2
  if (!Forecast) {
    general_pathIn <- paste0(
      datasourcing_path, "/Data/useCase_", country, "_",
      useCaseName, "/", Crop, "/result/geo_4cropModel")
  } else if (Forecast) {
    general_pathIn <- paste0(
      project_root, '/Data/useCase_', country, "_", useCaseName, "/", Crop, 
      "/transform/FC")
  
    country_code <- forecast_inputs$country_code
    
    get_bc_forecast_data(
      project_root, country, useCaseName, Crop, zone,
      forecast_inputs = forecast_inputs, season = season)
  }
  input_file <- function(name) {
    primary <- file.path(pathIn, paste0(forecast_prefix, name))
    fallback <- file.path(pathIn, name)
    if (Forecast && nzchar(forecast_prefix) && !file.exists(primary) && file.exists(fallback)) {
      fallback
    } else {
      primary
    }
  }
  # Define RS file paths based on AOI
  if (AOI) {
    Rainfall_file <- input_file(paste0("Rainfall_Season_", season, "_PointData_AOI.RDS"))
    SolarRadiation_file <- input_file(paste0("solarRadiation_Season_", season, "_PointData_AOI.RDS"))
    TemperatureMax_file <- input_file(paste0("temperatureMax_Season_", season, "_PointData_AOI.RDS"))
    TemperatureMin_file <- input_file(paste0("temperatureMin_Season_", season, "_PointData_AOI.RDS"))
    # Read ISDA or ISRIC soil file
    if (length(Depth) == 2) {
      # ISDA
      Soil_file <- input_file("ISDA_SoilDEM_PointData_AOI_profile.RDS")
      if (!file.exists(Soil_file)) get_ISDA_soilRDS(
        country = country, useCaseName = useCaseName, Crop = Crop)
      
    } else {
      # ISRIC
      Soil_file <- input_file("SoilDEM_PointData_AOI_profile.RDS")  
    }
    
  } else {
    Rainfall_file <- paste0(pathIn, "Rainfall_PointData_trial.RDS")
    SolarRadiation_file <- paste0(pathIn, "solarRadiation_PointData_trial.RDS")
    TemperatureMax_file <- paste0(pathIn, "temperatureMax_PointData_trial.RDS")
    TemperatureMin_file <- paste0(pathIn, "temperatureMin_PointData_trial.RDS")
    if (length(Depth) == 2) {
      # ISDA
      Soil_file <- paste0(pathIn, "ISDA_SoilDEM_PointData_trial_profile.RDS")
      if (!file.exists(Soil_file)) get_ISDA_soilRDS(
        country = country, useCaseName = useCaseName, Crop = Crop)
    } else {
      #ISRIC
      Soil_file <- paste0(pathIn, "SoilDEM_PointData_trial_profile.RDS")
    }
  }
  
  # Read and filter the RS data. Filtering seems unnecessary due to data storage (by zone)
  Rainfall <- read_and_filter(
    file = Rainfall_file,
    zone = zone,
    level2 = level2)
  SolarRadiation <- read_and_filter(
    file = SolarRadiation_file,
    zone = zone,
    level2 = level2)
  TemperatureMax <- read_and_filter(
    file = TemperatureMax_file,
    zone = zone,
    level2 = level2)
  TemperatureMin <- read_and_filter(
    file = TemperatureMin_file,
    zone = zone,
    level2 = level2)
  Soil <- read_and_filter(
    file = Soil_file,
    zone = zone,
    level2 = level2)
  
  # Get metadata
  metaData <- get_metadata(AOI, Rainfall, Soil)

  # Keep Soil observations with available Rainfall data
  Soil <- filter_soil_by_meta(Soil, metaData)

  # Keep weather observations with available Soil data
  Rainfall <- filter_by_metadata(Rainfall, metaData)
  SolarRadiation <- filter_by_metadata(SolarRadiation, metaData)
  TemperatureMax <- filter_by_metadata(TemperatureMax, metaData)
  TemperatureMin <- filter_by_metadata(TemperatureMin, metaData)

  # Working directory for Weather and Soil data in DSSAT format
  path.to.extdata <- create_extdata_path(
    project_root, country, useCaseName, Crop, varietyid, AOI)

  # Define DSSAT template data (soil and weather files in DSSAT format)
  path.to.temdata <- create_dssat_temdata_path(
    project_root, country, useCaseName, Crop)

  # Get unique locations
  coords <- metaData
  if(AOI) {
    coords <- unique(metaData[, c("longitude", "latitude")])
  } else {
    coords <- metaData
  }
  
  # Sequence of location indices
  indices <- seq_len(nrow(as.matrix(coords)))
  n_indices <- length(indices)
  
  log_file <- file.path(path.to.extdata, "progress_log_readGeo_CM.txt")
  
  if (file.exists(log_file)) {
    file.remove(log_file)
  }
  
  plan_multisession(per_worker_gb = 3)
  
  messages_list <- future_lapply(
    indices,
    function(i) {
      start_msg <- paste(
        "Start experiment:", i, "of", length(indices), "variety", varietyid
      )
      
      process_grid_element(
        i = i, country = country, path.to.extdata = path.to.extdata,
        path.to.temdata = path.to.temdata, TemperatureMax = TemperatureMax,
        TemperatureMin = TemperatureMin, SolarRadiation = SolarRadiation,
        Rainfall = Rainfall, coords = coords, Soil = Soil, AOI = AOI,
        varietyid = varietyid, zone = zone, level2 = level2, Depth = Depth
      )
      
      end_msg <- paste(
        "Finished experiment:", i, "of", length(indices), "variety", varietyid
      )
      
      c(start_msg, end_msg)
    },
    future.packages = packages_required,
    future.seed = TRUE
  )
}
