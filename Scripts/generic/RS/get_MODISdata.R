# Downloading of MODIS NDVI data for the Use Case

# Introduction: 
# This script allows the downloading of MODIS NDVI data (MOD13Q1 and MYD13Q1) used for the planting date exercise and crop type mapping, it allows to : 
# (1) Preparing the environment for the downloading
# (2) Interactive download of MODIS 
# (3) Renaming of the MODIS file 

#### Getting started #######

# 1. Sourcing required packages -------------------------------------------
packages_required <- c( "sf","geodata", "dplyr", "tidyterra", "modisfast", "terra", "lubridate")

installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
  install.packages(packages_required[!installed_packages])}

lapply(packages_required, library, character.only = TRUE)

# load required packages
suppressWarnings(suppressPackageStartupMessages(invisible(lapply(packages_required, library, character.only = TRUE))))




# 2. Downloading MODIS Data -------------------------------------------

download_MODIS<-function(country,useCaseName, level=0, admin_unit_name=NULL, Start_year, End_year, overwrite=FALSE){
  
  #' @description 
  #' @param country country name
  #' @param useCaseName use case name  name
  #' @param level the admin unit level, in integer, to be downloaded -  Starting with 0 for country, then 1 for the first level of subdivision (from 1 to 3). Default is zero
  #' @param admin_unit_name name of the administrative level to be download, default is NULL (when level=0) , else, to be specified as a vector (eg. c("Nandi"))
  #' @param overwrite default is FALSE 
  #' @param Start_year the first year of the period of interest in integer
  #' @param End_year the last year of the period of interest in integer
  #'
  #' @return one VI layer each 8 days (both TERRA and AQUA) over the period of interest, in WGS 84 (EPSG 4326) and the result will be written out in agwise-planting-date-and-cultivar/Data/useCaseName/RS/raw/
  #'
  #' @examples download_MODIS (country = "Kenya", useCaseName = "KALRO", level= 2, admin_unit_name = c("Butula"), Start_year = 2021, End_year = 2021, overwrite = TRUE)
  #' 
  #'
  #'
  #'  # Clean up the memory
  gc()
  
  ## 2.1. Preparing the environment ####
  ### 2.1.1. Creating a directory to store the downloaded data ####
  
  pathOut <- paste("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/", "RS/raw/", sep="")
  
  if (!dir.exists(pathOut)){
    dir.create(file.path(pathOut), recursive = TRUE)
  }
  
  ### 2.1.2. Get the country boundaries ####
  
  # Read the relevant shape file from gdam to be used to crop the global data
  countryShp <- geodata::gadm(country, level, path= pathOut)
  
  # Case admin_unit_name == NULL
  if (is.null(admin_unit_name)){
    countryShp <-countryShp
  }
  
  # Case admin_unit_name is not null 
  if (!is.null(admin_unit_name)) {
    if (level == 0) {
      print("admin_unit_name is not null, level can't be eq. to 0 and should be set between 1 and 3")
    }
    if (level == 1){
      countryShp <- subset(countryShp, countryShp$NAME_1 %in% admin_unit_name)
    } 
    if (level == 2){
      countryShp <- subset(countryShp, countryShp$NAME_2 %in% admin_unit_name)
    }
    if (level == 3){
      countryShp <- subset(countryShp, countryShp$NAME_3 %in% admin_unit_name)
    }
  }
  
  terra::writeVector(countryShp,paste0(pathOut,"/useCase_", country, "_",useCaseName,"_Boundary.shp"), overwrite=overwrite)
  #spafile <- paste0(pathOut,"/useCase_", country, "_",useCaseName,"_Boundary.shp")
  
  ### 2.1.3. Define the downloading parameters
  ## User and Password
  user = "amitcimmyt" 
  password = "Ambica_81"
  ## Login to Earthdata servers with your EOSDIS credentials. 
  log <- mf_login(credentials = c(user,password))  # set your own EOSDIS username and password
  
  ## Extent and time range of interest
  roi <- st_as_sf(countryShp)
  roi <- st_cast(roi, to = "POLYGON")
  roi$id <- seq(1:nrow(roi))
  
  start_date = paste0(Start_year,'-01-05')
  end_date = paste0(End_year, '-12-31') 
  
  time_range <- as.Date(c(start_date, end_date))
 
  ## MODIS collections and variables of interest
  collectionT <- "MOD13Q1.061"  #for Terra
  collectionA <- "MYD13Q1.061"  #for Aqua
  variables <- c("_250m_16_days_NDVI") # run mf_list_variables("MOD11A2.061") for an exhaustive list of variables available for the collection "MOD11A1.062"
  
  ## 2.2. MODIS data download and processing ####
  setwd(pathOut)
  
  ### 2.2.1. MODIS data download ####
  ## Get the URLs of the data 
  #for Terra
  urlsT <- mf_get_url(
    collection = collectionT,
    variables = variables,
    roi = roi,
    time_range = time_range
  )
  
  #for Aqua
  urlsA <- mf_get_url(
    collection = collectionA,
    variables = variables,
    roi = roi,
    time_range = time_range
  )
  
  ## Download the data. 
  res_terra <- mf_download_data(urlsT, parallel = T, path=pathOut) # for Terra
  res_aqua <- mf_download_data(urlsA, parallel = T, path=pathOut) # for Aqua
  
  ### 2.2.2. Process the MODIS data ####
  
  ## Copy past all the files in the same directory
  # Create a new directory
  dir.create(file.path(pathOut, "NDVI/MOD13Q1"), showWarnings = FALSE, recursive=T) # for Terra
  dir.create(file.path(pathOut, "NDVI/MYD13Q1"), showWarnings = FALSE, recursive=T) # for Aqua
  from.dir <- paste0(pathOut, '/data')
  to.dir   <- paste0(pathOut,'/NDVI')
  
  filesT    <- list.files(path = from.dir, pattern=collectionT, full.names = TRUE, recursive = TRUE) # for Terra
  for (f in filesT) file.copy(from = f, to = paste0(to.dir,'/MOD13Q1'))
  
  filesA    <- list.files(path = from.dir, pattern=collectionA, full.names = TRUE, recursive = TRUE) # for Aqua
  for (f in filesA) file.copy(from = f, to = paste0(to.dir,'/MYD13Q1'))

  ## Import, Merge and Reproject MODIS data with Terra
  modis_terra <- mf_import_data(
    path = paste0(to.dir,'/MOD13Q1'),
    collection = collectionT, 
    proj_epsg = 4326
  ) #for Terra
  
  ## Rename MODIS layer
  # Convert date into DOY
  doy_terra <- yday(time(modis_terra)) #for Terra
  
  # Convert DOY into a 3 digits number
  doy_terra <- sprintf("%03d", doy_terra)
  
  # Convert date into Year
  year_terra <- year(time(modis_terra)) #for Terra
  
  # Set names
  names(modis_terra) <- paste0(country,'_NDVI_',year_terra,'_', doy_terra) #for Terra
  
  # Save layers
  terra::writeRaster(modis_terra, filename=paste0(to.dir, '/',names(modis_terra), ".tif"), overwrite=TRUE)
  rm(modis_terra)
  
  # Clean up the memory
  gc()
  
  ## Import, Merge and Reproject MODIS data with Aqua
  modis_aqua <- mf_import_data(
    path = paste0(to.dir,'/MYD13Q1'),
    collection = collectionA, 
    proj_epsg = 4326
  ) #for Aqua
  
  ## Rename MODIS layer
  # Convert date into DOY
  doy_aqua <- yday(time(modis_aqua)) #for Aqua
  
  # Convert DOY into a 3 digits number
  doy_aqua <- sprintf("%03d", doy_aqua)
  
  # Convert date into Year
  year_aqua <- year(time(modis_aqua)) #for Aqua
  
  # Set names
  names(modis_aqua) <- paste0(country,'_NDVI_',year_aqua,'_', doy_aqua) #for Aqua
  
  # Save layers
  terra::writeRaster(modis_aqua, filename=paste0(to.dir, '/',names(modis_aqua), ".tif"), overwrite=TRUE)
  rm(modis_aqua)
  
  #### 2.2.3. Clear the folder ####
  
  ## Delete the GDAM folder
  unlink(paste0(pathOut, '/gadm'), force=TRUE, recursive = TRUE)
  
  ## Delete the data folder
  unlink(paste0(pathOut, '/data'), force=TRUE, recursive = TRUE)
  
  ## Delete MOD/MY folder
  unlink(paste0(to.dir,'/MOD13Q1'), force=TRUE, recursive=TRUE)
  unlink(paste0(to.dir,'/MYD13Q1'), force=TRUE, recursive=TRUE)
  
  ## Delete the .json file
  unlink(list.files(to.dir, pattern=".json", full.names = T))
  
  # Clean up the memory
  gc()
  
}


 
 