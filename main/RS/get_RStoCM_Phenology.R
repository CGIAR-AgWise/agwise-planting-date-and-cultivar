# Get the actual planting window derived from remote sensing to be used as input for crop models for the Use Case  

# Introduction: 
# This script allows extracting the planting dates windows from remote sensing for crop models. It provides for each crop model
# location (lon, lat), the planting window observed over the remote sensing planting dates time series. It covers :
# (1) - Read and shaping of the data
# (2) - Extraction of the 25% - 50% and 75% planting dates from remote sensing
# (3) - Write the results

#### Getting started #######

# 1. Sourcing required packages -------------------------------------------
packages_required <- c("terra", "sf", "purrr", "dplyr", "readr")

# check and install packages that are not yet installed
installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
  install.packages(packages_required[!installed_packages])}

# load required packages
suppressWarnings(suppressPackageStartupMessages(invisible(lapply(packages_required, library, character.only = TRUE))))

# 2. Obtain the planting window from remote sensing -------------------------------------------

RSplantingWindow <- function (country, useCaseName, crop, coord, CropModelName, overwrite = FALSE){
  
  #' @description Function that will allow to obtain the optimal planting date from Crop Model and to save each year as a raster file. The CM output should be a RDS file with at least 4 columns lon, lat, year and doy.
  #' @param country country name
  #' @param useCaseName use case name
  #' @param crop targeted crop with the first letter in uppercase. 
  #' @param overwrite default is FALSE 
  #' @param coord names of the columns with the lon lat column (ex. c(lon, lat))
  #' @param CropModelName name of the crop model used for the simulation.
  
  #' @return csv file of actual planting window at the Use Case level for each location in the original file, the results will be written out in /agwise-planting-date-and-cultivar/Data/useCase/crop/result/RS/RSPlantingDate
  #' @examples RSplantingWindow(country="Rwanda", useCaseNameFrom="CMRS", crop="Maize", coord=c('lon','lat'), CropModelName="DSSAT", overwrite=TRUE)
  
  #' 
  #' 
  
  ## 2.1. Setting the directory to store the output ####
  pathOut <- paste("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/", crop, "/result/RS/RSPlantingDate", sep="")
  
  if (!dir.exists(pathOut)){
    dir.create(file.path(pathOut), recursive = TRUE)
  }
  
  ## 2.2. Read and prepare the relevant data ####
  
  ### 2.2.1. Read and prepare the crop model coordinates ####
  # Load points with coordinates
  pathIn <- paste("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/", crop, "/result/",CropModelName,"/", sep="")
  fileIn_name <- paste0(country,"_",useCaseName,"_Coordinates_SpatialCropModelling.csv")
  
  pointCM <- read_csv(paste0(pathIn, fileIn_name))
  
  # Convert to spatial object (assumes WGS84)
  pointCM_sf <- vect(pointCM, geom = coord, crs = "EPSG:4326")
  
  # Create buffer in degrees (~5 km)
  buffers <- buffer(pointCM_sf, width = 0.045) # 0.045 ~ 5 km
  
  ### 2.2.2. Read the list of annual planting dates raster from remote sensing ####
  ## Get the list the raster of actual planting date
  raster_files <- list.files(paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/", crop, "/result/RS/RSPlantingDate"), pattern = "\\.tif$", full.names = TRUE)
  
  if (length(raster_files) == 0) {
    stop("No .tif files found in the raster folder.")
  }
  
  ## Stack the list of the actual planting date
  raster_stack <- terra::rast(raster_files)
  
  ## 2.3. Extract the planting dates ####
  
  outFile <- pointCM
  outFile$q25 <- NA
  outFile$q50 <- NA
  outFile$q75 <- NA
  
  ### 2.3.1. Loop on location in buffers ####
  for (i in 1:nrow(buffers)){
    
    print(buffers[i])
    
    # Extract the time series
    ts <- terra::extract(raster_stack, buffers[i])
    
    # Compute the q25, q50 and q75
    outFile$q25[i] <- round(quantile(ts[2:length(ts)], 0.25,na.rm=TRUE))
    outFile$q50[i] <- round(quantile(ts[2:length(ts)], 0.50,na.rm=TRUE))
    outFile$q75[i] <- round(quantile(ts[2:length(ts)], 0.75,na.rm=TRUE))
  }
  
  ### 2.3.2. Write to csv ####
  fileOut_name <- paste0(country,"_",useCaseName,"_",crop,"_Coordinates_SpatialCropModelling_with_RSPlantingDates_Quantiles.csv")
 write_csv(outFile, paste0(pathOut, "/",fileOut_name))
 
}

# country="Rwanda"
# crop ="Maize"
# useCaseName = "CMRS"
# coord = c("lon", "lat")
# CropModelName="DSSAT"
# overwrite=TRUE

