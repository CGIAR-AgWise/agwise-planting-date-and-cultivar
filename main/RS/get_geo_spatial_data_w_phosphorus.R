###############################################################################
# Script: get_geo_spatial_data_w_phosphorus.R
# Purpose: Load required packages for the DSSAT workflow.
#
# Authors: Alvaro Carmona-Cabrero, P.Moreno, L. Leroux
# Institution: CGIAR (IITA & Alliance of Bioversity International and CIAT)
# Date: 2026-07-09
###############################################################################

packages_required <- c(
  "parallel", "foreach", "sp", "sf", "terra", "geodata", "rgl", "plyr",
  "tidyverse", "lubridate"
)


load_or_install <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}


invisible(lapply(packages_required, load_or_install))


# load_or_generate_inputData version for the forecast part
load_or_generate_inputData_forecast <- function(
    country, useCaseName, Crop, dir_s2s, countryShapefile, inputData = NULL) {
  
  if (is.null(inputData)) {
    
    dataPath <- paste0(dir_s2s)
    inputData_path <- paste0(dir_s2s, "/AOI_GPS.RDS")
    
    if (file.exists(inputData_path)) {
      inputData <- readRDS(inputData_path)
    } else {
      getGridCoordinates_forecast(
        country, useCaseName, Crop, dir_s2s, countryShapefile, resltn = 0.05,
        provinces = NULL, district = NULL)
      inputData <- readRDS(inputData_path)
    }
  }
  
  return(inputData)
}


# getGridCoordinates version for the forecast part 
getGridCoordinates_forecast <- function(
    country, useCaseName, Crop, dir_s2s, countryShapefile, resltn = 0.05, 
    provinces = NULL, district = NULL, force_reanalysis = TRUE) { 
  
  pathOut <- dir_s2s
  
  if (!dir.exists(pathOut)) {
    dir.create(file.path(pathOut), recursive = TRUE)
  }
  
  # Do not compute if not requested and AOI_GPS.RDS exists
  if (!force_reanalysis && file.exists(paste0(pathOut, "AOI_GPS.RDS"))) {
    State_LGA <- readRDS(paste0(pathOut, "AOI_GPS.RDS"))
    
    return(State_LGA)
  }
  
  ### get country abbreviation to used in gdam function
  # countryCC <- countrycode(country, origin = 'country.name', destination = 'iso3c')
  
  ### read the relevant shape file from gdam to be used to crop the global data
  countrySpVec <- countryShapefile
  
  if(!is.null(provinces)) {
    level3 <- countrySpVec[countrySpVec$NAME_1 %in% provinces ]
  } else if (!is.null(district)) {
    level3 <- countrySpVec[countrySpVec$NAME_2 %in% district, ]
  } else {
    level3 <- countrySpVec
  }
  
  # plot(countrySpVec)
  # plot(level3, add = TRUE, col = "green")
  
  xmin <- ext(level3)[1]
  xmax <- ext(level3)[2]
  ymin <- ext(level3)[3]
  ymax <- ext(level3)[4]
  
  ### define a rectangular area that covers the whole study area (with buffer of 10 km around)
  lon_coors <- unique(round(seq(xmin - 0.1, xmax + 0.1, by = resltn),
                            digits = 3))
  lat_coors <- unique(round(seq(ymin - 0.1, ymax + 0.1, by = resltn),
                            digits = 3))
  rect_coord <- as.data.frame(expand.grid(x = lon_coors, y = lat_coors))
  
  if(resltn == 0.05) {
    rect_coord$x <- floor(rect_coord$x * 10) / 10 + ifelse(
      rect_coord$x - (floor(rect_coord$x * 10) / 10) < 0.05, 0.025, 0.075)
    rect_coord$y <- floor(rect_coord$y * 10) / 10 + ifelse(
      abs(rect_coord$y) - (floor(abs(rect_coord$y) * 10) / 10) < 0.05, 0.025, 0.075)
  }
  
  rect_coord <- unique(rect_coord[, c("x", "y")])
  # } else if (resltn == 0.01) {
  #   rect_coord$x <- floor(rect_coord$x*100)/100
  #   rect_coord$y <- floor(rect_coord$y*100)/100
  #   rect_coord <- unique(rect_coord[,c("x", "y")])
  # } else {
  #  names(rect_coord) <- c("x", "y")
  # }
  
  State_LGA <- as.data.frame(raster::extract(countrySpVec, rect_coord))
  State_LGA$lon <- rect_coord$x
  State_LGA$lat <- rect_coord$y
  State_LGA$country <- country
  
  State_LGA <- unique(State_LGA[, c("country", "NAME_1", "NAME_2", "lon", "lat")])
  
  if(!is.null(provinces)) {
    State_LGA <- droplevels(State_LGA[State_LGA$NAME_1 %in% provinces, ])
  } else if (!is.null(district)) {
    State_LGA <- droplevels(State_LGA[State_LGA$NAME_2 %in% district, ])
  }
  
  State_LGA <- droplevels(State_LGA[!is.na(State_LGA$NAME_2), ])
  
  saveRDS(State_LGA, paste0(pathOut, "/AOI_GPS.RDS"))
  
  return(State_LGA)
}






#####################################################################################################################################
#' @description a function to be used to define path, input data (GPS files), geospatial layers
#'
#' @param country 
#' @param useCaseName 
#' @param Crop 
#' @param inputData 
#' @param Planting_month_date 
#' @param Harvest_month_date 
#' @param varName 
#' @param soilProfile true of false based on if teh user need to have soil data or not
#' @param AOI 
#' @param pathOut1 the path towrite out the sourced data 
#'
#' @return
#' @export
#'
#' @examples
Paths_Vars <- function(
    country, useCaseName, Crop, inputData = NULL, Planting_month_date,
    Harvest_month_date, varName, soilProfile =TRUE, AOI = TRUE, pathOut = NULL) 
  {
  if(country=="Honduras"){
    varsbasePath <- "/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/Honduras/"
    varsbasePathSoil <- "/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/"
  }else{
    varsbasePath <- "/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/"
  }
  dataPath <- "~/agwise-datacuration/dataops/datacuration/Data/useCase_"
  OutputPath <- "~/agwise-datasourcing/dataops/datasourcing/Data/useCase_"
  
  readLayers_soil_isric <- NULL
  shapefileHC <- NULL
  
  if(is.null(inputData)){
    if(AOI == TRUE){
      inputData <- readRDS(paste(dataPath,country, "_", useCaseName,"/", Crop, "/result/AOI_GPS.RDS", sep=""))
    }else{
      inputData <- readRDS(paste(dataPath,country, "_", useCaseName,"/", Crop, "/result/compiled_fieldData.RDS", sep=""))
    }
  }
  
  listRasterRF <-list.files(path=paste0(varsbasePath, "Rainfall/chirps"), pattern=".nc$", full.names = TRUE)[-c(1:2)]
  listRasterTmax <-list.files(path=paste0(varsbasePath, "TemperatureMax/AgEra"), pattern=".nc$", full.names = TRUE)
  listRasterTMin <-list.files(path=paste0(varsbasePath, "TemperatureMin/AgEra"), pattern=".nc$", full.names = TRUE)
  listRasterRH <-list.files(path=paste0(varsbasePath, "RelativeHumidity/AgEra"), pattern=".nc$", full.names = TRUE)
  listRasterSR <-list.files(path=paste0(varsbasePath, "SolarRadiation/AgEra"), pattern=".nc$", full.names = TRUE)
  listRasterWS <-list.files(path=paste0(varsbasePath, "WindSpeed/AgEra"), pattern=".nc$", full.names = TRUE)
  
  if(soilProfile == TRUE){
    if(country=="Honduras"){
      listRaster_soil <-list.files(path=paste0(varsbasePathSoil, "Soil/soilGrids/profile/World"), pattern=".tif$")
      readLayers_soil <- terra::rast(paste(paste0(varsbasePathSoil, "Soil/soilGrids/profile/World"), listRaster_soil, sep="/"))
      shapefileHC <- st_read(paste0(varsbasePathSoil, "Soil/HC27/HC27 CLASSES.shp"), quiet= TRUE)%>%
        st_make_valid()
    }else{
      listRaster_soil <-list.files(path=paste0(varsbasePath, "Soil/soilGrids/profile"), pattern=".tif$")
      listRaster_soil_P <-list.files(path=paste0(varsbasePath, "Soil/soilGrids"), pattern="p.*\\.tif$")
      readLayers_soil <- terra::rast(paste(paste0(varsbasePath, "Soil/soilGrids/profile"), listRaster_soil, sep="/"))
      readLayers_soil_P <- NULL
      try(readLayers_soil_P <- terra::rast(paste(paste0(varsbasePath, "Soil/soilGrids"), listRaster_soil_P, sep="/")))
      shapefileHC <- st_read(paste0(varsbasePath, "Soil/HC27/HC27 CLASSES.shp"), quiet= TRUE)%>%
        st_make_valid() 
    }
    
    if(is.null(pathOut)){
      pathOut <- paste(OutputPath, country, "_", useCaseName,"/", Crop, "/result/geo_4cropModel/", sep="")
    }
  }else{
    listRaster_soil <-list.files(path=paste0(varsbasePath, "Soil/iSDA"), pattern=".tif$")
    readLayers_soil <- terra::rast(paste(paste0(varsbasePath, "Soil/iSDA"), listRaster_soil, sep="/"))
    listRaster_soil_isric <-list.files(path=paste0(varsbasePath, "Soil/soilGrids"), pattern=".tif$")
    readLayers_soil_isric <- terra::rast(paste(paste0(varsbasePath, "Soil/soilGrids"), listRaster_soil_isric, sep="/"))
    if(is.null(pathOut)){
      pathOut <- paste(OutputPath, country, "_", useCaseName,"/", Crop, "/result/geo_4ML/", sep="")
    }
  }
  return(list(inputData, listRasterRF, listRasterTmax, listRasterTMin, listRasterRH,listRasterSR, listRasterWS, readLayers_soil, readLayers_soil_isric, shapefileHC, pathOut,readLayers_soil_P))
}

################################################################################
#' @description a function to estimate P at different depths
#'
#' @param k = decay coefficient (controls how fast P decreases)
#' @param z = depth in cm
#' @param P_mean_0_30 = your measured mean P from 0–30 cm
#'
#' @return
#' @export
#'
#' @examples
# TODO: Revise this equation
extrapolate_P <- function(P_mean_0_30, z, k){
  A <- P_mean_0_30 * (30 * k) / (1 - exp(-30 * k))
  P <- A * exp(-k * z)
  return(P)
}


# TODO: Revise these equations
mehlich3_to_olsen <- function(mehlich3_P){
  # Equations from: https://www.nature.com/articles/s41597-023-02022-4
  soil_calcareous <- FALSE
  # TODO: add logic for calcareous or soil pH
  if (!soil_calcareous) olsen_P <- 0.47 * mehlich3_P + 2.4
  if (soil_calcareous) olsen_P <- 0.41 * mehlich3_P + 1.1
  return(olsen_P)
}


################################################################################
# DATA SOURCE https://data.chc.ucsb.edu/products/CHIRPS-2.0/ for rainfall
# https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators?tab=form fr AgEra 5 data
# Is a helper function for extract_geoSpatialPointData. Extract geo-spatial data with time dimension 
#' @description this functions loops through all .nc files (~30 - 40 years) for rain. temperature, solar radiation, wind speed and relative humidity. 
#' Planting_month_date should be set to one month prior to the earliest possible planting month and date so that data is available to-set initial conditions while running crop model. 
#' 
#' @param country country name to be used to extract the first two level of administrative units to attach to the data. 
#' @param inputData is a data frame and must have the c(lat, lon, plantingDate, harvestDate). For field observations, plantingDate  harvestDate should be given in yyyy-mm-dd format. 
#' @param AOI TRUE if data for multiple years is required. FALSE if data is required for field trials, for which the actual interval between the planting and harvest dates will be used. 
#' @param Planting_month_date if AOI is TRUE, Planting_month_date should be provided in mm-dd format. weather data across years between Planting_month_date and Harvest_month_date will be provided. 
#' @param Harvest_month_date if AOI is TRUE, Harvest_month_date should be provided in mm-dd format.  weather data across years between Planting_month_date and Harvest_month_date will be provided
#' @param varName is the name of the variable for which data is required and it is one of c("Rainfall", "temperatureMax", "temperatureMin", "relativeHumidity", "solarRadiation", "windSpeed")
#' @param plantingWindow number of weeks starting considering the Planting_month_date as earliest planting week. It is given when several planting dates are to be tested to determine optimal planting date and it should be given in  
#' @param jobs defines how many cores to use for parallel data sourcing
#' 
#' @return based on the provided variable name, this function returns, daily data for every GPS together with longitude, latitude, planting Date, harvest Date, NAME_1, NAME_2 and 
#' daily data with columns labelled with the concatenation of variable name and Julian day of data.  When AOI is set to FALSE, every GPS location is allowed to have 
#' its own unique planting and harvest dates and in this case, because the different GPS location can have non-overlapping dates, NA values are filled for dates prior to
#' planting and later than harvest dates. When AOI is true, the user defined Planting_month_date and Harvest_month_date is considered for all locations and data is provided across the years. 
#' The weather data is extracted 1 months before the actual planting month 
#' @examples: inputData <- data.frame(lon=c(29.3679, 29.3941,  29.390), lat=c(-1.539, -1.716, -1.716), 
#' plantingDate  = c("2020-08-27", "2020-09-04", "2020-09-04"),
#' harvestDate = c("2020-12-29", "2020-12-29", "2020-12-29"))
#' get_weather_pointData(inputData = inputData, country = "Rwanda", AOI=FALSE, 
#'                     Planting_month_date=NULL, Harvest_month_date=NULL, varName="temperatureMin", jobs=10)
#'                
get_weather_pointData <- function(
    country, inputData, AOI = FALSE, Planting_month_date = NULL,
    Harvest_month_date = NULL, varName, listRaster, plantingWindow = 1, jobs) {
  
  if(AOI == TRUE) {
    if(is.null(Planting_month_date) | is.null(Harvest_month_date)) {
      print("with AOI=TRUE, Planting_month_date, Harvest_month_date can not be null, please refer to the documentation and provide mm-dd for both parameters")
      return(NULL)
    }
    
    ## check if both planting and harvest dates are in the same year
    Planting_month <- as.numeric(str_extract(Planting_month_date, "[^-]+"))
    Harvest_month <- as.numeric(str_extract(Harvest_month_date, "[^-]+"))
    
    ## py and hy are used only as place holder for formatting purposes
    if(Planting_month < Harvest_month){
      planting_harvest_sameYear <- TRUE
      py <- 2000
      hy <- 2000
    }else{
      planting_harvest_sameYear <- FALSE
      py <- 2000
      hy <- 2001
    }
    
    ## set planting date one moth prior to the given Planting_month_date so that initial condition for the crop model could be set correctly
    Planting_month_date <- as.Date(paste0(py, "-",Planting_month_date)) ## the year is only a place holder to set planting month 1 month earlier
    Planting_month_date <- Planting_month_date %m-% months(1)
    
    ## set harvest date one month later to the make sure there is enough weather data until maturity 
    Harvest_month_date <- as.Date(paste0(hy, "-",Harvest_month_date)) ## the year is only a place holder 
    
    ## if multiple planting dates are to be tested, adjust the Harvest_month_date to extract weather data for the later planting dates.  
    if(plantingWindow > 1 & plantingWindow < 5){
      Harvest_month_date <- Harvest_month_date %m+% months(1)
    }else if(plantingWindow >= 5 & plantingWindow <=8){
      Harvest_month_date <- Harvest_month_date %m+% months(2)
    }
    
    if(year(Planting_month_date) < year(Harvest_month_date)){
      planting_harvest_sameYear <- FALSE
    }
  }
  
  # 1. read all the raster files
  
  # if(AOI == TRUE & varName == "Rainfall"){
  #   listRaster <- listRaster[20:42]
  # }else if (AOI == TRUE){
  #   listRaster <- listRaster[22:44]
  # }
  # 
  
  
  
  ## 2. format the input data with GPS, dates and ID and add administrative unit info
  if(AOI == TRUE){
    countryCoord <- unique(inputData[, c("lon", "lat")])
    countryCoord <- countryCoord[complete.cases(countryCoord), ]
    ## After checking if planting and harvest happens in the same year, get the date of the year 
    countryCoord$startingDate <- Planting_month_date
    countryCoord$endDate <- Harvest_month_date
    countryCoord <- countryCoord[complete.cases(countryCoord), ]
    names(countryCoord) <- c("longitude", "latitude", "startingDate", "endDate")
    countryCoord$ID <- c(1:nrow(countryCoord))
    ground <- countryCoord[, c("longitude", "latitude", "startingDate", "endDate", "ID")]
    
  }else{
    inputData <- unique(inputData[, c("lon", "lat", "plantingDate", "harvestDate")])
    inputData$plantingDate <- as.Date(inputData$plantingDate)
    inputData$harvestDate <- as.Date(inputData$harvestDate)
    inputData$plantingDate <- inputData$plantingDate %m-% months(1)
    inputData <- inputData[complete.cases(inputData), ]
    inputData$ID <- c(1:nrow(inputData))
    names(inputData) <- c("longitude", "latitude", "startingDate", "endDate", "ID")
    ground <- inputData
  }
  
  # ground$harvestDate <- as.Date(ground$harvestDate, "%Y-%m-%d")
  countryShp <- geodata::gadm(country, level = 2, path='.')
  dd2 <- raster::extract(countryShp, ground[, c("longitude", "latitude")])[, c("NAME_1", "NAME_2")]
  ground$NAME_1 <- dd2$NAME_1
  ground$NAME_2 <- dd2$NAME_2
  
  ## 3.get the seasonal rainfall parameters for AOI
  
  if(AOI == TRUE){
    if (planting_harvest_sameYear ==  TRUE) {
      
      cls <- makeCluster(jobs)
      doParallel::registerDoParallel(cls)
      
      rf_result <- foreach(i=1:length(listRaster), .packages = c('terra', 'plyr', 'stringr','tidyr')) %dopar% {
        rasti <- listRaster[i]
        pl_j <-as.POSIXlt(unique(ground$startingDate))$yday
        hv_j <-as.POSIXlt(unique(ground$endDate))$yday
        PlHvD <- terra::rast(rasti, lyrs=c(pl_j:hv_j))
        xy <- ground[, c("longitude", "latitude")]
        raini <- terra::extract(PlHvD, xy, method='simple', cells=FALSE)
        raini <- raini[,-1]
        if(varName %in% c("temperatureMax","temperatureMin")){
          raini <- raini-273.3
        }else if (varName == "solarRadiation"){
          raini <- raini/1000000
        }
        ground_adj <- ground
        lubridate::year(ground_adj$startingDate) <- as.numeric(str_extract(rasti, "[[:digit:]]+"))
        lubridate::year(ground_adj$endDate) <- as.numeric(str_extract(rasti, "[[:digit:]]+"))
        start <- as.Date(unique(ground_adj$startingDate))
        maxDaysDiff <- abs(max(min(pl_j) - max(hv_j)))
        end <- start + as.difftime(maxDaysDiff, units="days")
        ddates <- seq(from=start, to=end, by=1)
        names(raini) <- paste(varName, ddates[1:length(names(raini))], sep="_")
        # names(raini) <- paste(varName, sub("^[^_]+", "", names(raini)), sep="")
        ground_adj$startingDate <- as.character(ground_adj$startingDate)
        ground_adj$endDate <- as.character(ground_adj$endDate)
        if (i==1){
          ground2 <- cbind(ground, raini)
        }else{
          ground2 <- raini
        }
        
        
      }
      
      data_points <- dplyr::bind_cols(rf_result, .name_repair = "minimal")
      data_points <- data_points[, !duplicated(colnames(data_points))]
      stopCluster(cls)
    }else{
      cls <- makeCluster(jobs)
      doParallel::registerDoParallel(cls)
      ## Rainfall
      rf_result2 <- foreach(i = 1:(length(listRaster)-1), .packages = c('terra', 'plyr', 'stringr','tidyr')) %dopar% {
        listRaster <- listRaster[order(listRaster)]
        rast1 <- listRaster[i]
        rast2 <- listRaster[i+1]
        ground_adj <- ground
        lubridate::year(ground_adj$startingDate) <- as.numeric(str_extract(rast1, "[[:digit:]]+"))
        lubridate::year(ground_adj$endDate) <- as.numeric(str_extract(rast2, "[[:digit:]]+"))
        start <- as.Date(unique(ground_adj$startingDate))
        maxDaysDiff <- as.numeric(max(ground_adj$endDate) - min(ground_adj$startingDate))
        end <- start + as.difftime(maxDaysDiff, units="days")
        ddates <- seq(from=start, to=end, by=1)
        # Convert planting Date and harvesting in Julian Day 
        pl_j <-as.POSIXlt(unique(ground_adj$startingDate))$yday
        hv_j <-as.POSIXlt(unique(ground_adj$endDate))$yday
        rasti1 <- terra::rast(rast1, lyrs=c(pl_j:terra::nlyr(terra::rast(rast1))))
        rasti2 <- terra::rast(rast2, lyrs=c(1:hv_j))
        PlHvD <- c(rasti1, rasti2)
        xy <- ground[, c("longitude", "latitude")]
        raini <- terra::extract(PlHvD, xy, method='simple', cells=FALSE)
        raini <- raini[,-1]
        if(varName %in% c("temperatureMax","temperatureMin")){
          raini <- raini - 273.3
        }else if (varName == "solarRadiation"){
          raini <- raini/1000000
        }
        names(raini) <- paste(varName, ddates, sep="_")
        ground_adj$startingDate <- as.character(ground_adj$startingDate)
        ground_adj$endDate <- as.character(ground_adj$endDate)
        if (i==1){
          ground2 <- cbind(ground, raini)
        }else{
          ground2 <- raini
        }
      }
      
      data_points <- dplyr::bind_cols(rf_result2, .name_repair = "minimal")
      data_points <- data_points[, !duplicated(colnames(data_points))]
      
      stopCluster(cls)
    }
    
  } else {
    
    
    # Get the Year
    ground$yearPi <- as.numeric(format(as.POSIXlt(ground$startingDate), "%Y"))
    ground$yearHi <- as.numeric(format(as.POSIXlt(ground$endDate), "%Y"))
    
    ## drop data with planting dates before 1981, as there is no global layer available for years before 1981 pfr rain and 1979 for AgeEra files
    ground <- droplevels(ground[ground$yearPi >= 1981 & ground$yearHi >= 1981, ])
    
    # Convert planting date and harvesting date in Julian Day
    ground$ pl_j <-as.POSIXlt(ground$startingDate)$yday
    ground$hv_j <-as.POSIXlt(ground$endDate)$yday
    
    # get the max number of days on the field to be used as column names. 
    start <- as.Date(min(ground$startingDate))
    maxDaysDiff <- abs(max(min(ground$pl_j) - max(ground$hv_j)))
    end <- maxDaysDiff +  as.Date(max(ground$endDate)) # start + as.difftime(maxDaysDiff, units="days")
    ddates <- seq(from=start, to=end, by=1)
    
    # create list of all possible column names to be able to row bind data from different sites with different planting and harvest dates ranges
    # rf_names <- c(paste0(varName, "_",  c(min(ground$pl_j):max(ground$hv_j))))
    rf_names <- c(paste0(varName, "_",  ddates))
    rf_names2 <-  as.data.frame(matrix(nrow=length(rf_names), ncol=1))
    colnames(rf_names2) <- "dataDate"
    rf_names2[,1] <- rf_names
    rf_names2$ID <- c(1:nrow(rf_names2))
    
    
    data_points <- NULL
    for(i in 1:nrow(ground)){
      print(i)
      groundi <- ground[i, c("longitude", "latitude", "startingDate", "endDate", "ID", "NAME_1", "NAME_2","yearPi", "yearHi", "pl_j", "hv_j")]
      yearPi <- as.numeric(groundi$yearPi)
      yearHi <- as.numeric(groundi$yearHi)
      pl_j <- groundi$pl_j
      hv_j <- groundi$hv_j
      
      # Case planting and harvesting dates span the same year
      if (yearPi == yearHi) {
        rasti<-listRaster[which(grepl(yearPi, listRaster, fixed=TRUE) == TRUE)]
        rasti <- terra::rast(rasti, lyrs=c(pl_j:hv_j))
      }
      
      # Case planting and harvesting dates span two different years
      if (yearPi < yearHi) {
        rasti1<-listRaster[which(grepl(yearPi, listRaster, fixed=TRUE) == TRUE)]
        rasti1 <- terra::rast(rasti1, lyrs=c(pl_j:terra::nlyr(terra::rast(rasti1))))
        rasti2 <-listRaster[which(grepl(yearHi, listRaster, fixed=TRUE) == TRUE)]
        rasti2 <- terra::rast(rasti2, lyrs=c(1:hv_j))
        rasti <- c(rasti1, rasti2)
        
      }
      
      ### Extract the information for the i-th row 
      
      xy <- groundi[, c("longitude", "latitude")]
      xy <- xy %>%
        mutate_if(is.character, as.numeric)
      
      raini <- terra::extract(rasti, xy,method='simple', cells=FALSE)
      raini <- raini[,-1]
      if(varName %in% c("temperatureMax","temperatureMin")){
        raini <- raini-274
      }else if (varName == "solarRadiation"){
        raini <- raini/1000000
      }
      
      start <- as.Date(unique(groundi$startingDate))
      maxDaysDiff <- as.numeric(groundi$endDate - groundi$startingDate)
      end <- start + as.difftime(maxDaysDiff, units="days")
      ddates <- seq(from=start, to=end, by=1)
      names(raini) <- paste(varName, ddates, sep="_")
      raini <- as.data.frame(t(raini))
      raini$dataDate <- rownames(raini)
      rownames(raini) <- NULL
      
      ## merging data for different trials with differing growing period requires having data for the whole period of time
      raini <- merge(raini, rf_names2, by="dataDate", all.y=TRUE)
      raini <- raini[order(raini$ID),]
      rownames(raini) <- raini$dataDate
      raini <- raini %>% dplyr::select(-c(ID,dataDate))
      raini2 <- as.data.frame(t(raini))
      rownames(raini2) <- NULL
      raini2 <- cbind(groundi, raini2)
      data_points <- rbind(data_points, raini2)
    }
  }
  
  
  
  data_points <- data_points %>% 
    select_if(~sum(!is.na(.)) > 0)
  
  return(data_points)
  
}



################################################################################
# https://rdrr.io/cran/geodata/man/soil_grids.html
# https://rdrr.io/cran/geodata/man/soil_af.html
# https://rdrr.io/cran/geodata/man/soil_af_isda.html
# https://rdrr.io/cran/geodata/man/elevation.html DEm data from SRTM
#' @description Is a helper function for extract_geoSpatialPointData. Extract geo-spatial data with no temporal dimension, i,e,. soil properties and topography variables
#' 
#' @param country country name to be sued to extract the first two level of administrative units to attach to the data. 
#' @param inputData is a data frame and must have the c(lat, lon) 
#' @param profile is true/false, if true data, isirc data for the six soil profiles will be processed. This is required for DSSAT and other crop models. 
#' @param pathOut is path used to download the DEM layers temporarily and these layers can be removed after obtaining the data from this function. 
#' 
#' 
#' @return a data frame with lon, lat,teh top two admistrnative zones, soil properties with columns named with variable names attached with depth,  
#' elevations variables attached for every GPS location 
#' @examples: get_soil_DEM_pointData(country = "Rwanda", profile = FALSE, pathOut = getwd(),
#' inputData = data.frame(lon=c(29.35667, 29.36788), lat=c(-1.534350, -1.538792)))
get_soil_DEM_pointData <- function(
    country, inputData, soilProfile = FALSE, pathOut, Layers_soil = Layers_soil,
    Layers_soil_isric= Layers_soil_isric, shapefileHC = shapefileHC, 
    countryShapefile = countryShapefile,
    Layers_soil_P = NULL) {
  
  
  
  ## 2. read the shape file of the country and crop the global data
  countryShp <- countryShapefile
  inputData$country = country
  
  dd2 <- raster::extract(countryShp, inputData[, c("lon", "lat")])[, c("NAME_1", "NAME_2")]
  inputData$NAME_1 <- dd2$NAME_1
  inputData$NAME_2 <- dd2$NAME_2
  
  inputData2 <- unique(inputData[, c("lon", "lat", "NAME_1", "NAME_2", "country")])
  inputData2 <- inputData2[complete.cases(inputData2), ]
  inputData2$ID <- c(1:nrow(inputData2))
  gpsPoints <- unique(inputData2[, c("lon", "lat")])
  gpsPoints$lon <- as.numeric(gpsPoints$lon)
  gpsPoints$lat <- as.numeric(gpsPoints$lat)
  # gpsPoints <- gpsPoints[, c("x", "y")]
  areasCovered <- unique(c(raster::extract(countryShp, gpsPoints)$NAME_2))
  areasCovered <- areasCovered[!is.na(areasCovered)]
  print(areasCovered)
  
  
  for(aC in areasCovered){
    print(aC)
    countryShpA <- countryShp[countryShp$NAME_2 == aC]
    croppedLayer_soil <- terra::crop(Layers_soil, countryShpA)
    
    
    ## 3. apply pedo-transfer functions to get soil organic matter and soil hydraulics variables 
    if (soilProfile == TRUE){
      
      depths <- c("0-5cm","5-15cm","15-30cm","30-60cm","60-100cm","100-200cm")  
      
      
      ## Estimate P for all depths
      if(!is.null(Layers_soil_P)){
        croppedLayer_soil_P <- terra::crop(Layers_soil_P, countryShpA)
        
        # Convert 100mg/kg to mg/kg
        croppedLayer_soil_P$`P_0-30cm` <- croppedLayer_soil_P$`P_0-30cm` / 100
        
        mid_depths <- c(2.5, 10, 22.5, 45, 80, 150)
        k <- 0.03
        P_profile <- rast()
        for (p_rast_i in seq_along(names(croppedLayer_soil_P))){
          P_mean_rast <- croppedLayer_soil_P[[p_rast_i]]
          for(j in seq_along(mid_depths)){
            z <- mid_depths[j]
            new_layer <- app(P_mean_rast, fun = function(x) extrapolate_P(x, z, k))
            new_layer <- app(new_layer, fun = mehlich3_to_olsen)
            layer_name <- substr(names(croppedLayer_soil_P)[[p_rast_i]], 1, 
                                 nchar(names(croppedLayer_soil_P)[[p_rast_i]]) - 6)
            names(new_layer) <- paste0(layer_name, depths[j])
            P_profile <- c(P_profile, new_layer)
          }
        }
        croppedLayer_soil <- c(croppedLayer_soil, P_profile)
      }
      ## get soil organic matter as a function of organic carbon
      for(i in 1:length(depths)) {
        croppedLayer_soil[[paste0("SOM_",depths[i])]] <- (croppedLayer_soil[[paste0("soc_",depths[i])]] * 2)/10
      }
      
      
      ##### permanent wilting point (cm3/cm3) ####
      for(i in 1:length(depths)) {
        croppedLayer_soil[[paste0("PWP_",depths[i])]] <- (-0.024 * croppedLayer_soil[[paste0("sand_",depths[i])]]/100) + 0.487 *
          croppedLayer_soil[[paste0("clay_",depths[i])]]/100 + 0.006 * croppedLayer_soil[[paste0("SOM_",depths[i])]] + 
          0.005*(croppedLayer_soil[[paste0("sand_",depths[i])]]/100 * croppedLayer_soil[[paste0("SOM_",depths[i])]]) - 
          0.013*(croppedLayer_soil[[paste0("clay_",depths[i])]]/100 * croppedLayer_soil[[paste0("SOM_",depths[i])]]) +
          0.068*(croppedLayer_soil[[paste0("sand_",depths[i])]]/100 * croppedLayer_soil[[paste0("clay_",depths[i])]]/100 ) + 0.031
        croppedLayer_soil[[paste0("PWP_",depths[i])]] <- (croppedLayer_soil[[paste0("PWP_",depths[i])]] + 
                                                            (0.14 * croppedLayer_soil[[paste0("PWP_",depths[i])]] - 0.02))
      }
      
      ##### FC (cm3/cm3) ######
      for(i in 1:length(depths)) {
        croppedLayer_soil[[paste0("FC_",depths[i])]] <- -0.251 * croppedLayer_soil[[paste0("sand_",depths[i])]]/100 + 0.195 * 
          croppedLayer_soil[[paste0("clay_",depths[i])]]/100 + 0.011 * croppedLayer_soil[[paste0("SOM_",depths[i])]] + 
          0.006*(croppedLayer_soil[[paste0("sand_",depths[i])]]/100 * croppedLayer_soil[[paste0("SOM_",depths[i])]]) - 
          0.027*(croppedLayer_soil[[paste0("clay_",depths[i])]]/100 * croppedLayer_soil[[paste0("SOM_",depths[i])]]) + 
          0.452*(croppedLayer_soil[[paste0("sand_",depths[i])]]/100 * croppedLayer_soil[[paste0("clay_",depths[i])]]/100) + 0.299
        croppedLayer_soil[[paste0("FC_",depths[i])]] <- (croppedLayer_soil[[paste0("FC_",depths[i])]] + (1.283 * croppedLayer_soil[[paste0("FC_",depths[i])]]^2 - 0.374 * croppedLayer_soil[[paste0("FC_",depths[i])]] - 0.015))
        
      }
      
      
      ##### soil water at saturation (cm3/cm3) ######
      for(i in 1:length(depths)) {
        croppedLayer_soil[[paste0("SWS_",depths[i])]] <- 0.278*(croppedLayer_soil[[paste0("sand_",depths[i])]]/100)+0.034*
          (croppedLayer_soil[[paste0("clay_",depths[i])]]/100)+0.022*croppedLayer_soil[[paste0("SOM_",depths[i])]] -
          0.018*(croppedLayer_soil[[paste0("sand_",depths[i])]]/100*croppedLayer_soil[[paste0("SOM_",depths[i])]])- 0.027*
          (croppedLayer_soil[[paste0("clay_",depths[i])]]/100*croppedLayer_soil[[paste0("SOM_",depths[i])]])-
          0.584 * (croppedLayer_soil[[paste0("sand_",depths[i])]]/100*croppedLayer_soil[[paste0("clay_",depths[i])]]/100)+0.078
        croppedLayer_soil[[paste0("SWS_",depths[i])]] <- (croppedLayer_soil[[paste0("SWS_",depths[i])]] +(0.636*croppedLayer_soil[[paste0("SWS_",depths[i])]]-0.107))
        croppedLayer_soil[[paste0("SWS_",depths[i])]] <- (croppedLayer_soil[[paste0("FC_",depths[i])]]+croppedLayer_soil[[paste0("SWS_",depths[i])]]-(0.097*croppedLayer_soil[[paste0("sand_",depths[i])]]/100)+0.043)
        
      }
      
      ##### saturated conductivity (mm/h) ######
      for(i in 1:length(depths)) {
        b = (log(1500)-log(33))/(log(croppedLayer_soil[[paste0("FC_",depths[i])]])-log(croppedLayer_soil[[paste0("PWP_",depths[i])]]))
        lambda <- 1/b
        croppedLayer_soil[[paste0("KS_",depths[i])]] <- 1930*((croppedLayer_soil[[paste0("SWS_",depths[i])]]-croppedLayer_soil[[paste0("FC_",depths[i])]])^(3-lambda))
      }
      
      soilData <- croppedLayer_soil
      
    }else{
      
      depths <- c("0-20cm","20-50cm")  
      
      ## get soil organic matter as a function of organic carbon
      for(i in 1:length(depths)) {
        croppedLayer_soil[[paste0("SOM_",depths[i])]] <- (croppedLayer_soil[[paste0("oc_",depths[i])]] * 2)/10
      }
      
      ##### permanent wilting point (cm3/cm3) ####
      for(i in 1:length(depths)) {
        croppedLayer_soil[[paste0("PWP_",depths[i])]] <- (-0.024 * croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100) + 0.487 *
          croppedLayer_soil[[paste0("clay.tot.psa_",depths[i])]]/100 + 0.006 * croppedLayer_soil[[paste0("SOM_",depths[i])]] + 
          0.005*(croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100 * croppedLayer_soil[[paste0("SOM_",depths[i])]]) - 
          0.013*(croppedLayer_soil[[paste0("clay.tot.psa_",depths[i])]]/100 * croppedLayer_soil[[paste0("SOM_",depths[i])]]) +
          0.068*(croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100 * croppedLayer_soil[[paste0("clay.tot.psa_",depths[i])]]/100 ) + 0.031
        croppedLayer_soil[[paste0("PWP_",depths[i])]] <- (croppedLayer_soil[[paste0("PWP_",depths[i])]] + (0.14 * croppedLayer_soil[[paste0("PWP_",depths[i])]] - 0.02))
      }
      
      
      
      ##### FC (cm3/cm3) ######
      for(i in 1:length(depths)) {
        croppedLayer_soil[[paste0("FC_",depths[i])]] <- -0.251 * croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100 + 0.195 * 
          croppedLayer_soil[[paste0("clay.tot.psa_",depths[i])]]/100 + 0.011 * croppedLayer_soil[[paste0("SOM_",depths[i])]] + 
          0.006*(croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100 * croppedLayer_soil[[paste0("SOM_",depths[i])]]) - 
          0.027*(croppedLayer_soil[[paste0("clay.tot.psa_",depths[i])]]/100 * croppedLayer_soil[[paste0("SOM_",depths[i])]]) + 
          0.452*(croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100 * croppedLayer_soil[[paste0("clay.tot.psa_",depths[i])]]/100) + 0.299
        croppedLayer_soil[[paste0("FC_",depths[i])]] <- (croppedLayer_soil[[paste0("FC_",depths[i])]] + (1.283 * croppedLayer_soil[[paste0("FC_",depths[i])]]^2 - 0.374 * croppedLayer_soil[[paste0("FC_",depths[i])]] - 0.015))
        
      }
      
      
      ##### soil water at saturation (cm3/cm3) ######
      for(i in 1:length(depths)) {
        croppedLayer_soil[[paste0("SWS_",depths[i])]] <- 0.278*(croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100)+0.034*
          (croppedLayer_soil[[paste0("clay.tot.psa_",depths[i])]]/100)+0.022*croppedLayer_soil[[paste0("SOM_",depths[i])]] -
          0.018*(croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100*croppedLayer_soil[[paste0("SOM_",depths[i])]])- 0.027*
          (croppedLayer_soil[[paste0("clay.tot.psa_",depths[i])]]/100*croppedLayer_soil[[paste0("SOM_",depths[i])]])-
          0.584 * (croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100*croppedLayer_soil[[paste0("clay.tot.psa_",depths[i])]]/100)+0.078
        croppedLayer_soil[[paste0("SWS_",depths[i])]] <- (croppedLayer_soil[[paste0("SWS_",depths[i])]] +(0.636*croppedLayer_soil[[paste0("SWS_",depths[i])]]-0.107))
        croppedLayer_soil[[paste0("SWS_",depths[i])]] <- (croppedLayer_soil[[paste0("FC_",depths[i])]]+croppedLayer_soil[[paste0("SWS_",depths[i])]]-(0.097*croppedLayer_soil[[paste0("sand.tot.psa_",depths[i])]]/100)+0.043)
        
      }
      
      ##### saturated conductivity (mm/h) ######
      for(i in 1:length(depths)) {
        b = (log(1500)-log(33))/(log(croppedLayer_soil[[paste0("FC_",depths[i])]])-log(croppedLayer_soil[[paste0("PWP_",depths[i])]]))
        lambda <- 1/b
        croppedLayer_soil[[paste0("KS_",depths[i])]] <- 1930*((croppedLayer_soil[[paste0("SWS_",depths[i])]]-croppedLayer_soil[[paste0("FC_",depths[i])]])^(3-lambda))
      }
      
      names(croppedLayer_soil) <- gsub("0-20cm", "top", names(croppedLayer_soil))
      names(croppedLayer_soil) <- gsub("20-50cm", "bottom", names(croppedLayer_soil))
      names(croppedLayer_soil) <- gsub("_0-200cm", "", names(croppedLayer_soil))
      names(croppedLayer_soil) <- gsub("\\.", "_",  names(croppedLayer_soil)) 
      croppedLayer_isric <- terra::crop(Layers_soil_isric, countryShpA)
      names(croppedLayer_isric) <- gsub("0-30cm", "0_30", names(croppedLayer_isric))
      soilData <- c(croppedLayer_soil, croppedLayer_isric)
    }
    if(aC == areasCovered[1]){
      soilData_allregion <- soilData
    }else{
      soilData_allregion <- merge(soilData_allregion, soilData)
    }
  }
  
  
  ## 4. Extract point soil data 
  pointDataSoil <- as.data.frame(raster::extract(soilData_allregion, gpsPoints))
  pointDataSoil <- subset(pointDataSoil, select=-c(ID))
  pointDataSoil <- cbind(unique(inputData2[, c("country", "NAME_1", "NAME_2", "lon", "lat")]), pointDataSoil)
  
  ## 5. Extract DEM data: at lon and lat at steps of 5 degree
  # countryExt <- terra::ext(countryShp)
  
  # countryExt <- terra::ext(countryShp[countryShp$NAME_2 %in% unique(inputData2$NAME_2)])
  # 
  # lons <- seq(countryExt[1]-1, countryExt[2]+1, 5)
  # lats <- seq(countryExt[3]-1, countryExt[4]+1, 5)
  # griddem <- expand_grid(lons, lats)
  # 
  # # ## if the extent is not fully within a distince of 5 degrees this does not work, otherwise this would have been better script
  # listRaster_dem1 <-geodata::elevation_3s(lon=countryExt[1], lat=countryExt[3], path=getwd()) #xmin - ymin
  # listRaster_dem2 <-geodata::elevation_3s(lon=countryExt[1], lat=countryExt[4], path=getwd()) #xmin - ymax
  # listRaster_dem3 <-geodata::elevation_3s(lon=countryExt[2], lat=countryExt[3], path=getwd()) #xmax - ymin
  # listRaster_dem4 <-geodata::elevation_3s(lon=countryExt[2], lat=countryExt[4], path=getwd()) #xmax - ymax
  # listRaster_dem <- terra::mosaic(listRaster_dem1, listRaster_dem2, listRaster_dem3, listRaster_dem4, fun='mean')
  
  # dems <- c()
  # listRaster_demx <- NULL
  # for(g in 1:nrow(griddem)){
  #   listRaster_demx <- tryCatch(geodata::elevation_3s(lon=griddem$lons[g], lat=griddem$lats[g], path=pathOut),error=function(e){})
  #   dems <- c(dems, listRaster_demx)
  # }
  # 
  # if(!is.null(dems)){
  #   ## if mosaic works with list as dems is here, the next step is not necessary
  #   if(length(dems) == 1){
  #     listRaster_dem <- dems[[1]]
  #   }else if(length(dems) > 1 & length(dems) < 12){
  #     for (k in c((length(dems)+1):12)){
  #       dems[[k]] <- dems[[1]] 
  #     }
  #     ## as it is not possible to define the number of tiles before hand, as assumption is made to have 12 tiles and when that is not the case the first time will be 
  #     ## duplicated and the mean of it will be take which should not affect the result
  #     listRaster_dem <- terra::mosaic(dems[[1]], dems[[2]],dems[[3]],dems[[4]],
  #                                     dems[[5]], dems[[6]], dems[[7]],dems[[8]],
  #                                     dems[[9]], dems[[10]], dems[[11]],dems[[12]],
  #                                     fun='mean')
  #   }
  #   
  #   dem <- terra::crop(listRaster_dem, countryShp[countryShp$NAME_2 %in% unique(inputData2$NAME_2)])
  #   slope <- terra::terrain(dem, v = 'slope', unit = 'degrees')
  #   tpi <- terra::terrain(dem, v = 'TPI')
  #   tri <- terra::terrain(dem, v = 'TRI')
  #   
  #   ### ideally these four dem layers will be made to a list so that point extraction will be done at once, bu CG Labs capacity does not allow that ...
  #   topoLayer <- terra::rast(list(dem, slope, tpi, tri))
  #   datatopo <- terra::extract(topoLayer, gpsPoints, method='simple', cells=FALSE)
  #   datatopo <- subset(datatopo, select=-c(ID))
  #   topoData <- cbind(inputData2[, c("lon", "lat")], datatopo)
  #   names(topoData) <- c("lon", "lat" ,"altitude", "slope", "TPI", "TRI")
  #   
  #   
  #   pointDataSoil <- unique(merge(pointDataSoil, topoData, by=c("lon", "lat")))
  #   
  #   
  # }else{
  #   pointDataSoil = pointDataSoil
  # }
  
  
  ## 6. Extract harvest choice soil class and drainage rate (just for profile =TRUE)
  if(soilProfile == TRUE){
    coordinates_df <- data.frame(lat=pointDataSoil$lat, lon=pointDataSoil$lon)
    coordinates_sf <- st_as_sf(coordinates_df, coords = c("lon", "lat"), crs = 4326)
    intersecting_polygons <-st_join(coordinates_sf, shapefileHC)
    # Extract the geometry (latitude and longitude) from the 'joined_data' object
    intersecting_polygons  <-intersecting_polygons  %>%
      mutate(lon = st_coordinates(intersecting_polygons)[, "X"], 
             lat = st_coordinates(intersecting_polygons)[, "Y"]) 
    intersecting_polygons  <-as.data.frame(intersecting_polygons)
    intersecting_polygons$geometry <- NULL
    intersecting_polygons$ID <- NULL
    
    
    # Join the LDR (drainage rate) values to the intersecting_polygons data
    LDR_data <- data.frame(LDR = c(rep(0.2, 9), rep(0.5, 9), rep(0.75, 9)),
                           GRIDCODE = seq(1:27))
    
    LDR_data <- merge(intersecting_polygons,LDR_data)
    LDR_data$GRIDCODE <- NULL
    pointDataSoil <- unique(merge(pointDataSoil, LDR_data, by=c("lon", "lat")))
  }
  
  
  return(pointDataSoil)
}

################################################################################
#' Title Extract soil, DEM and daily weather data
#' This function reads the input data for GPS and dates for specific country-use Case-crop combination, in data-curation result folder and should be saved 
#' for the trial sites named as "compiled_fieldData.RDS" and for target areas as AOI_GPS.RDS. The input data should have lon, lat, ID, planting and harvest dates
#'
#' @param country country name to be used for cropping, extracting the top two administrative region names and to define input and output paths
#' @param useCaseName use case name or a project name, and this is used to define input and output paths
#' @param Crop is crop name and is used to define input and output paths
#' @param AOI is TRUE is the input data has defined planting and harvest dates otherwise FALSE
#' @param Planting_month_date planting month and date in mm-dd format and must be provided if AOI is TRUE. It is the earliest possible planting date in the target area. 
#' @param Harvest_month_date harvest month and date in mm-dd format and must be provided if AOI is TRUE 
#' @param plantingWindow is given when several planting dates are to be tested to determine optimal planting date and it should be given in number of weeks starting from Planting_month_date 
#' @param weatherData is TRUE is weather data is required otherwise FALSE
#' @param soilData is TRUE if soil data is required otherwise FALSE
#' @param soilProfile is TRUE if soil data from the six profile of ISRIC is required, otherwise set to FALSE
#' @param season when data is needed for more than one season, this needs to be provided to be used in the file name
#' @param jobs number of cores used to parallel weather data extraction
#'
#' @return If weatherData is TRUE, list of data frames with daily data for c("Rainfall", "temperatureMax", "temperatureMin", "relativeHumidity", "solarRadiation", "windSpeed") is returned. 
#' If soilData is set TRUE, soil properties at different depth plus elevation and derivatives of DEM are returned. These results are written out in paths defined by country, useCaseName, and crop 
#' and either raw or result of the different AgWise modules space in CG Labs. If AOI is set TRUE, the weather data between the Planting_month_date and Harvest_month_date and for 1979 - 2022 data will be returned. 

#' @examples extract_geoSpatialPointData(country = "Rwanda", useCaseName = "RAB", Crop = "Maize", AOI=FALSE, Planting_month_date=NULL, Harvest_month_date=NULL, 
#' soilData = TRUE, weatherData = TRUE,soilProfile = FALSE, jobs =10)
extract_geoSpatialPointData <- function(
    country, useCaseName, Crop,  inputData = NULL, countryShapefile = NULL, 
    AOI = FALSE, 
    Planting_month_date = NULL, Harvest_month_date = NULL, plantingWindow = 1, 
    weatherData = TRUE, soilData = TRUE, soilProfile = FALSE, season = 1, 
    pathOut = NULL, jobs = 10) {
  
  
  ARD <- Paths_Vars(country=country, useCaseName=useCaseName, Crop=Crop, inputData = inputData, 
                    Planting_month_date=Planting_month_date, Harvest_month_date=Harvest_month_date,
                    soilProfile =soilProfile, AOI = AOI,  pathOut = pathOut)
  
  inputData <- ARD[[1]]
  listRasterRF <- ARD[[2]]
  listRasterTmax <- ARD[[3]]
  listRasterTMin <- ARD[[4]]
  listRasterRH <- ARD[[5]]
  listRasterSR <- ARD[[6]]
  listRasterWS <- ARD[[7]]
  Layers_soil <- ARD[[8]]
  Layers_soil_isric <- ARD[[9]]
  shapefileHC <- ARD[[10]]
  pathOut <- ARD[[11]]
  Layers_soil_P <- ARD[[12]]
  
  
  
  if (!dir.exists(pathOut)){
    dir.create(file.path(pathOut), recursive = TRUE)
  }
  
  if(weatherData == TRUE) {
    i = 1
    wData <- list()
    for(varName in c("Rainfall", "temperatureMax", "temperatureMin",
                     "relativeHumidity", "solarRadiation", "windSpeed")) {
      
      if(varName == "Rainfall") {
        listRaster <- listRasterRF
      }else if (varName == "temperatureMax") {
        listRaster <- listRasterTmax
      }else if (varName == "temperatureMin") {
        listRaster <- listRasterTMin
      }else if(varName == "relativeHumidity") {
        listRaster <- listRasterRH
      }else if(varName == "solarRadiation") {
        listRaster <- listRasterSR
      }else if(varName == "windSpeed") {
        listRaster <- listRasterWS
      }
      
      listRaster <- listRaster[grep("2000", listRaster):grep("2023", listRaster)] 
      
      vData <- get_weather_pointData(
        inputData = inputData, country = country, AOI = AOI, 
        Planting_month_date = Planting_month_date, plantingWindow, 
        Harvest_month_date = Harvest_month_date, varName = varName, 
        listRaster = listRaster, jobs = jobs)
      
      w_name <- ifelse(
        AOI == T, paste0(varName, "_Season_", season, "_PointData_AOI.RDS"),
        paste0(varName, "_PointData_trial.RDS"))
      
      saveRDS(vData, paste0(pathOut, "/", w_name))
      message(paste("Data sourcing for ", varName, " is done", sep=""))
      rm(vData)
      i = i + 1
    }
  }
  
  
  if(soilData == TRUE) {
    sData <- get_soil_DEM_pointData(
      country = country, soilProfile = soilProfile, pathOut = pathOut,
      inputData = inputData, Layers_soil = Layers_soil, 
      Layers_soil_isric = Layers_soil_isric, shapefileHC = shapefileHC,
      countryShapefile = countryShapefile,
      Layers_soil_P = Layers_soil_P)
    
    if(AOI == TRUE) {
      if (soilProfile == TRUE) {
        s_name <- "SoilDEM_PointData_AOI_profile.RDS"
      } else {
        s_name <- "SoilDEM_PointData_AOI.RDS"
      }
    } else {
      if (soilProfile == TRUE) {
        s_name <- "SoilDEM_PointData_trial_profile.RDS"
      } else {
        s_name <- "SoilDEM_PointData_trial.RDS"
      }
    }
    saveRDS(sData, paste(pathOut, s_name, sep = "/"))
  }
  
  
  # if(weatherData == TRUE & soilData == TRUE & season == 1){
  #   wData[[7]] <- sData
  if (weatherData) {
    return(wData)  
  }
  # }else if (weatherData == TRUE & soilData == FALSE){
  #   return(wData)
  # }else if(weatherData == FALSE & soilData == TRUE & season == 1) {
  #   return(sData)
  # }
  
}




#################################################################################################################


# 3. Is a helper function for get_WeatherSummarydata to get seasonal rainfall parameters for point data over the cropping season  -------------------------------------------
#' @description is a function to get total rainfall, number of rainy days and monthly rainfall, and working when the planting and harvest happen in different years
#' @param raster1 the .nc file for the planting year, within get_rf_pointdata function, this is provided by the function 
#' @param raster2 the .nc file for the harvest year, within get_rf_pointdata function, this is provided by the function 
#' @param gpsdata a data frame with longitude and latitude 
#' @param pl_j the planting date as the date of the year
#' @param hv_j the harvest date as the date of the year
#'
#' @return  a data frame with total rainfall, number of rainy days and monthly rainfall
#' @example summary_pointdata_rainfall(rastLayer1="/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/Rainfall/chirps/1981.nc",
# raster2="/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/Rainfall/chirps/1982.nc",
# gpsdata=data.frame(longitude = c(29.375, 30.125), latitude = c(-2.825, -2.425)),  
# pl_j=35, hv_j=150, planting_harvest_sameYear = TRUE)
summarize_pointdata <- function(
    rastLayerRF_1 = NULL, rastLayerRF_2 = NULL, rastLayerTmax_1 = NULL, 
    rastLayerTmax_2 = NULL, rastLayerTmin_1 = NULL, rastLayerTmin_2 = NULL, 
    rastLayerRH_1 = NULL, rastLayerRH_2 = NULL, rastLayerSR_1 = NULL, 
    rastLayerSR_2 = NULL, rastLayerWS_1 = NULL, rastLayerWS_2 = NULL, 
    gpsdata, pl_j, hv_j, planting_harvest_sameYear) {
  
  # 3.1. Read the rainfall data and shape the ground data ####
  if(planting_harvest_sameYear == TRUE){
    PlHvD_RF <- terra::rast(rastLayerRF_1, lyrs=c(pl_j:hv_j)) 
    PlHvD_Tmax <- terra::rast(rastLayerTmax_1, lyrs=c(pl_j:hv_j)) 
    PlHvD_Tmin <- terra::rast(rastLayerTmin_1, lyrs=c(pl_j:hv_j)) 
    PlHvD_RH <- terra::rast(rastLayerRH_1, lyrs=c(pl_j:hv_j)) 
    PlHvD_SR <- terra::rast(rastLayerSR_1, lyrs=c(pl_j:hv_j)) 
    PlHvD_WS <- terra::rast(rastLayerWS_1, lyrs=c(pl_j:hv_j)) 
    
  }else{
    rastRF_i1 <- if(class(terra::rast(rastLayerRF_1))[1]=='SpatRaster'){terra::rast(rastLayerRF_1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastLayerRF_1))))}
    rastRF_i2 <- if(class(terra::rast(rastLayerRF_2))[1]=='SpatRaster'){terra::rast(rastLayerRF_2, lyrs=c(1:hv_j))}
    PlHvD_RF <- c(rastRF_i1, rastRF_i2)
    
    rastTmax_i1 <- if(class(terra::rast(rastLayerTmax_1))[1]=='SpatRaster'){terra::rast(rastLayerTmax_1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastLayerTmax_1))))}
    rastTmax_i2 <- if(class(terra::rast(rastLayerTmax_2))[1]=='SpatRaster'){terra::rast(rastLayerTmax_2, lyrs=c(1:hv_j))}
    PlHvD_Tmax <- c(rastTmax_i1, rastTmax_i2)
    
    rastTmin_i1 <- if(class(terra::rast(rastLayerTmin_1))[1]=='SpatRaster'){terra::rast(rastLayerTmin_1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastLayerTmin_1))))}
    rastTmin_i2 <- if(class(terra::rast(rastLayerTmin_2))[1]=='SpatRaster'){terra::rast(rastLayerTmin_2, lyrs=c(1:hv_j))}
    PlHvD_Tmin <- c(rastTmin_i1, rastTmin_i2)
    
    rastRH_i1 <- if(class(terra::rast(rastLayerRH_1))[1]=='SpatRaster'){terra::rast(rastLayerRH_1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastLayerRH_1))))}
    rastRH_i2 <- if(class(terra::rast(rastLayerRH_2))[1]=='SpatRaster'){terra::rast(rastLayerRH_2, lyrs=c(1:hv_j))}
    PlHvD_RH <- c(rastRH_i1, rastRH_i2)
    
    rastSR_i1 <- if(class(terra::rast(rastLayerSR_1))[1]=='SpatRaster'){terra::rast(rastLayerSR_1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastLayerSR_1))))}
    rastSR_i2 <- if(class(terra::rast(rastLayerSR_2))[1]=='SpatRaster'){terra::rast(rastLayerSR_2, lyrs=c(1:hv_j))}
    PlHvD_SR <- c(rastSR_i1, rastSR_i2)
    
    rastWS_i1 <- if(class(terra::rast(rastLayerWS_1))[1]=='SpatRaster'){terra::rast(rastLayerWS_1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastLayerWS_1))))}
    rastWS_i2 <- if(class(terra::rast(rastLayerWS_2))[1]=='SpatRaster'){terra::rast(rastLayerWS_2, lyrs=c(1:hv_j))}
    PlHvD_WS <- c(rastWS_i1, rastWS_i2)
  }
  
  xy <- gpsdata[, c("longitude", "latitude")]
  
  RFi <- if(class(PlHvD_RF) == "SpatRaster"){terra::extract(PlHvD_RF, xy, method='simple', cells=FALSE)}
  RFi <- RFi[,-1]
  
  Tmaxi <- if(class(PlHvD_Tmax) == "SpatRaster"){terra::extract(PlHvD_Tmax, xy, method='simple', cells=FALSE)}
  Tmaxi <- Tmaxi[,-1]
  Tmaxi <- Tmaxi-274
  
  Tmini <- if(class(PlHvD_Tmin) == "SpatRaster"){terra::extract(PlHvD_Tmin, xy, method='simple', cells=FALSE)}
  Tmini <- Tmini[,-1]
  Tmini <- Tmini-274
  
  RHi <- if(class(PlHvD_RH) == "SpatRaster"){terra::extract(PlHvD_RH, xy, method='simple', cells=FALSE)}
  RHi <- RHi[,-1]
  
  SRi <- if(class(PlHvD_SR) == "SpatRaster"){terra::extract(PlHvD_SR, xy, method='simple', cells=FALSE)}
  SRi <- SRi[,-1]
  SRi <- SRi/1000000
  
  WSi <- if(class(PlHvD_WS) == "SpatRaster"){terra::extract(PlHvD_WS, xy, method='simple', cells=FALSE)}
  WSi <- WSi[,-1]
  
  
  
  # 3.2. Get the rainfall seasonal parameters at a location ####
  ## The total rainfall over the growing period
  
  rainiq <- t(RFi)
  gpsdata$totalRF <- colSums(rainiq)
  
  ## The number of rainy days (thr >= 2 mm) over the growing period 
  gpsdata$nrRainyDays <- NULL
  for (m in 1:nrow(RFi)){
    # print(m)
    mdata <- RFi[m, ]
    mdata[mdata < 2] <- 0
    mdata[mdata >= 2] <- 1
    gpsdata$nrRainyDays[m] <- sum(mdata)
    
    ## The monthly rainfall, at 31 days interval and the remaining  days at the end, over the growing period
    mrdi <- RFi[m, ]
    mtmaxi <- Tmaxi[m,]
    mtmini <- Tmini[m,]
    mrhi <- RHi[m,]
    msri <- SRi[m,]
    mwsi <- WSi[m,]
    
    mdiv <- unique(c(seq(1, length(mrdi), 30), length(mrdi)))
    
    mdivq <- length(mrdi)%/%31
    mdivr <- length(mrdi)%%31
    
    ##################
    mrf <- NULL
    for (q in 1:mdivq){
      mrf <- c(mrf, sum(mrdi[((q*31)-30):(q*31)]))	
    }
    # Then add the remainder
    mrf <- c(mrf, sum(mrdi[(q*31):((q*31)+mdivr)]))
    
    mtmax <- NULL
    for (q in 1:mdivq){
      mtmax <- c(mtmax, mean(as.numeric(mtmaxi[((q*31)-30):(q*31)])))	
    }
    # Then add the remainder
    mtmax <- c(mtmax, mean(as.numeric(mtmaxi[(q*31):((q*31)+mdivr)])))
    
    mtmin <- NULL
    for (q in 1:mdivq){
      mtmin <- c(mtmin, mean(as.numeric(mtmini[((q*31)-30):(q*31)])))	
    }
    # Then add the remainder
    mtmin <- c(mtmin, mean(as.numeric(mtmini[(q*31):((q*31)+mdivr)])))
    
    mrh <- NULL
    for (q in 1:mdivq){
      mrh <- c(mrh, mean(as.numeric(mrhi[((q*31)-30):(q*31)])))	
    }
    # Then add the remainder
    mrh <- c(mrh, mean(as.numeric(mrhi[(q*31):((q*31)+mdivr)])))
    
    msr <- NULL
    for (q in 1:mdivq){
      msr <- c(msr, mean(as.numeric(msri[((q*31)-30):(q*31)])))	
    }
    # Then add the remainder
    msr <- c(msr, mean(as.numeric(msri[(q*31):((q*31)+mdivr)])))
    
    mws <- NULL
    for (q in 1:mdivq){
      mws <- c(mws, mean(as.numeric(mwsi[((q*31)-30):(q*31)])))	
    }
    # Then add the remainder
    mws <- c(mws, mean(as.numeric(mwsi[(q*31):((q*31)+mdivr)])))
    
    ###################################
    
    # for (q in 1:length(mdivq)){
    #   mrf <- c(mrf, sum(mdiv[q:31*q]))
    # }
    # 
    # mrf <- c()
    # mtmax <- c()
    # mtmin <- c()
    # mrh <- c()
    # msr <- c()
    # mws <- c()
    
    # for (k in 1:(length(mdiv)-1)) {
    #   # print(k)
    #   if(k == 1){
    #     mrf <- c(mrf, sum(mrdi[c(mdiv[k]:mdiv[k+1])]))
    #     mtmax <- c(mtmax, mean(as.numeric(mtmaxi[c(mdiv[k]:mdiv[k+1])])))
    #     mtmin <- c(mtmin, mean(as.numeric(mtmini[c(mdiv[k]:mdiv[k+1])])))
    #     mrh <- c(mrh, mean(as.numeric(mrhi[c(mdiv[k]:mdiv[k+1])])))
    #     msr <- c(msr, mean(as.numeric(msri[c(mdiv[k]:mdiv[k+1])])))
    #     mws <- c(mws, mean(as.numeric(mwsi[c(mdiv[k]:mdiv[k+1])])))
    #   }else{
    #     mrf <- c(mrf, sum(mrdi[c((mdiv[k]+1):(mdiv[k+1]))]))
    #     mtmax <- c(mtmax, mean(as.numeric(mtmaxi[c((mdiv[k]+1):(mdiv[k+1]))])))
    #     mtmin <- c(mtmin, mean(as.numeric(mtmini[c((mdiv[k]+1):(mdiv[k+1]))])))
    #     mrh <- c(mrh, mean(as.numeric(mrhi[c((mdiv[k]+1):(mdiv[k+1]))])))
    #     msr <- c(msr, mean(as.numeric(msri[c((mdiv[k]+1):(mdiv[k+1]))])))
    #     mws <- c(mws, mean(as.numeric(mwsi[c((mdiv[k]+1):(mdiv[k+1]))])))
    #   }
    # }}
    # 
    
    if(length(mrf) > 15){## if the crop is > 15 months on the field ( to account for cassava as well)
      mrf <- c(mrf, rep("NA", 15 -length(mrf)))
      mtmax <- c(mtmax, rep("NA", 15 - length(mtmax)))
      mtmin <- c(mtmin, rep("NA", 15 -length(mtmin)))
      mrh <- c(mrh, rep("NA", 15 -length(mrh)))
      msr <- c(msr, rep("NA", 15 -length(msr)))
      mws <- c(mws, rep("NA", 15 -length(mws)))
    }
    
    mrf_names <- c(paste0("Rain_month", c(1:15)))
    mtmax_names <- c(paste0("Tmax_month", c(1:15)))
    mtmin_names <- c(paste0("Tmin_month", c(1:15)))
    mrh_names <- c(paste0("relativeHumid_month", c(1:15)))
    msr_names <- c(paste0("solarRad_month", c(1:15)))
    mws_names <- c(paste0("windSpeed_month", c(1:15)))
    
    
    for (h in 1:length(mrf_names)) {
      colname <- mrf_names[h]
      gpsdata[[colname]][m] <- mrf[h]
      
      colname <- mtmax_names[h]
      gpsdata[[colname]] <- mtmax[h]
      
      colname <- mtmin_names[h]
      gpsdata[[colname]] <- mtmin[h]
      
      colname <- mrh_names[h]
      gpsdata[[colname]] <- mrh[h]
      
      colname <- msr_names[h]
      gpsdata[[colname]] <- msr[h]
      
      colname <- mws_names[h]
      gpsdata[[colname]] <- mws[h]
    }
    
    
    if(planting_harvest_sameYear== TRUE){
      gpsdata$plantingYear <- str_extract(rastLayerRF_1, "[[:digit:]]+")
      gpsdata$harvestYear <- str_extract(rastLayerRF_1, "[[:digit:]]+")
    }else{
      gpsdata$plantingYear <- str_extract(rastLayerRF_1, "[[:digit:]]+")
      gpsdata$harvestYear <- str_extract(rastLayerRF_2, "[[:digit:]]+")
    }
    
    gpsdata <- gpsdata %>% 
      select_if(~sum(!is.na(.)) > 0)
    
    return(gpsdata)
  }
  
}

# 5. Extract the season rainfall parameters for point based data -------------------------------------------
#' @description this functions loops through all .nc files (~30 -40 years) for rainfall to provide point based seasonal rainfall parameters.
#' @details for AOI it requires a "AOI_GPS.RDS" data frame with c("longitude","latitude") columns being saved in 
#'                            paste("~/agwise-datasourcing/dataops/datasourcing/Data/useCase_", country, "_",useCaseName, "/", Crop, "/raw", sep="") 
#'          for trial sites it requires a "compiled_fieldData.RDS" data frame with c("lon", "lat", "plantingDate", "harvestDate") beinf saved in 
#'                    paste("~/agwise-datacuration/dataops/datacuration/Data/useCase_",country, "_",useCaseName, "/", Crop, "/result", sep="")
#'
#' @param country country name
#' @param useCaseName use case name  name
#' @param Crop the name of the crop to be used in creating file name to write out the result.
#' @param AOI True if the data is required for target area, and false if it is for trial sites
#' @param overwrite default is FALSE 
#' @param Planting_month_date is provided as mm-dd, and for AOI, it is the intended planting date defined using expert knowledge, crop models, remote sensing analysis, etc, preferably it should also make use of climate forecast info
#' @param Harvest_month_date is provided as mm-dd, defined in similar way as Planting_month_date
#' @param jobs defines how many cores to use for parallel data sourcing
#' @param dataSource is among c("CHIRPS", "AgEra")
#' @param ID only when AOI  = FALSE, it is the column name Identifying the trial ID in compiled_fieldData.RDS
#' 
#' @return a data frame containing the col information & columns corresponding to the rainfall parameters#' 
#'        totalRF : Total rainfall between pl_Date and hv_Date (mm)
#'        nrRainyDays : Number of rainy days between pl_Date and hv_Date (days)
#'        di : Average daily rainfall between pl_Date and hv_Date (mm/day)
#'        Rain_monthx: total monthly rainfall 
#' @examples: get_rf_pointSummarydata(country = "Rwanda";  useCaseName = "RAB"; Crop = "Potato"; AOI = FALSE; overwrite = TRUE;
#' Planting_month_date = "07-01";  Harvest_month_date = "11-30";jobs=10, id = "TLID")
get_WeatherSummarydata <- function(
    country, useCaseName, Crop, AOI = FALSE, inputData = NULL,
    Planting_month_date = NULL, Harvest_month_date = NULL,  season = 1,
    pathOut = NULL) {
  
  jobs <- plan_multisession(per_worker_gb = 2, only_get_workers = T)
  
  ARD <- Paths_Vars(country=country, useCaseName=useCaseName, Crop=Crop, inputData = inputData, 
                    Planting_month_date=Planting_month_date, Harvest_month_date=Harvest_month_date,
                    soilProfile =FALSE, AOI = AOI,  pathOut = pathOut)
  
  
  inputData <- ARD[[1]]
  listRaster_RF <- ARD[[2]]
  listRaster_Tmax <- ARD[[3]]
  listRaster_Tmin <- ARD[[4]]
  listRaster_RH <- ARD[[5]]
  listRaster_SR <- ARD[[6]]
  listRaster_WS <- ARD[[7]]
  pathOut <- ARD[[11]]
  
  
  # Creation of the output dir
  if (!dir.exists(pathOut)){
    dir.create(file.path(pathOut), recursive = TRUE)
  }
  
  
  # Input point data AOI / Trial
  if(AOI == TRUE){
    countryCoord <- inputData
    countryCoord$ID <- c(1:nrow(inputData))
    countryCoord <- unique(countryCoord[, c("lon", "lat", "ID")])
    
    ## check if both planting and harvest dates are in the same year
    Planting_month <- as.numeric(str_extract(Planting_month_date, "[^-]+"))
    harvest_month <- as.numeric(str_extract(Harvest_month_date, "[^-]+"))
    if(Planting_month < harvest_month){
      planting_harvest_sameYear <- TRUE}
    else{
      planting_harvest_sameYear <- FALSE
    }
    
    # add a place holder for the year to get the julian date  
    if(planting_harvest_sameYear ==TRUE){
      countryCoord$plantingDate <- paste(2001, Planting_month_date, sep="-")
      countryCoord$harvestDate <- paste(2001, Harvest_month_date, sep="-")
    }else{
      countryCoord$plantingDate <- paste(2001, Planting_month_date, sep="-")
      countryCoord$harvestDate <- paste(2002, Harvest_month_date, sep="-")
    }
    countryCoord <- countryCoord[complete.cases(countryCoord),]
    names(countryCoord) <- c("longitude", "latitude", "ID" ,"plantingDate", "harvestDate")
    ground <- countryCoord
  }else{
    countryCoord <- unique(inputData[, c("longitude", "latitude", "plantingDate", "harvestDate")])
    countryCoord$ID <- c(1:nrow(countryCoord))
    countryCoord <- countryCoord[complete.cases(countryCoord), ]
    names(countryCoord) <- c("longitude", "latitude", "plantingDate", "harvestDate", "ID")
    ground <- countryCoord
    
  }
  
  ground$Planting <- as.Date(ground$plantingDate, "%Y-%m-%d")
  ground$Harvesting <- as.Date(ground$harvestDate, "%Y-%m-%d") 
  countryShp <- geodata::gadm(country, level = 2, path='.')
  dd2 <- raster::extract(countryShp, ground[, c("longitude", "latitude")])[, c("NAME_1", "NAME_2")]
  ground$NAME_1 <- dd2$NAME_1
  ground$NAME_2 <- dd2$NAME_2
  
  ground$pyear <- as.numeric(format(as.POSIXlt(ground$plantingDate), "%Y"))
  ground <- ground[ground$pyear >= 1981, ]
  
  # Clean the raster files
  trf_files <- list.files(dirname(listRaster_RF)[1])
  tmax_files <- list.files(dirname(listRaster_Tmax)[1])
  tmin_files <- list.files(dirname(listRaster_Tmin)[1])
  trh_files <- list.files(dirname(listRaster_RH)[1])
  tsr_files <- list.files(dirname(listRaster_SR)[1])
  tws_files <- list.files(dirname(listRaster_WS)[1])
  
  tmax <- which(tmax_files %in% trf_files)
  tmin <- which(tmin_files %in% trf_files)
  rh <- which(trh_files %in% trf_files)
  sr <- which(tsr_files %in% trf_files)
  ws <- which(tws_files %in% trf_files)
  
  length(ws)
  tmax_files <- tmax_files[tmax]
  tmin_files<- tmin_files[tmin]
  trh_files <- trh_files[rh]
  tsr_files <- tsr_files[sr]
  tws_files <- tws_files[ws]
  # listRaster_Tmax <- listRaster_Tmax[tmax]
  # listRaster_Tmin <- listRaster_Tmin[tmin]
  # listRaster_RH <- listRaster_RH[rh]
  # listRaster_SR <- listRaster_SR[sr]
  # listRaster_WS <- listRaster_WS[ws]
  
  # Compute the seasonal rainfall parameters
  if(AOI == TRUE){
    # Convert planting Date and harvesting in Julian Day 
    pl_j <-as.POSIXlt(unique(ground$Planting))$yday
    hv_j <-as.POSIXlt(unique(ground$Harvesting))$yday
    
    if (planting_harvest_sameYear ==  TRUE) {
      cls <- makeCluster(jobs)
      doParallel::registerDoParallel(cls)
      # Loop over all the years 
      rf_result <- foreach(i=1:(length(listRaster_RF)-1), .packages = c('terra', 'plyr', 'stringr','tidyr')) %dopar% {
        rastRF_1 <- listRaster_RF[i]
        rastTmax_1 <- listRaster_Tmax[i]
        rastTmin_1 <- listRaster_Tmin[i]
        rastRH_1 <- listRaster_RH[i]
        rastSR_1 <- listRaster_SR[i]
        rastWS_1 <- listRaster_WS[i]
        source("~/agwise-datasourcing/dataops/datasourcing/Scripts/generic/get_geoSpatialData_V2.R", local = TRUE)
        
        summarize_pointdata(rastLayerRF_1=rastRF_1, rastLayerRF_2 = NULL,
                            rastLayerTmax_1=rastTmax_1, rastLayerTmax_2 = NULL,
                            rastLayerTmin_1=rastTmin_1, rastLayerTmin_2 = NULL,
                            rastLayerRH_1=rastRH_1, rastLayerRH_2 = NULL,
                            rastLayerSR_1=rastSR_1, rastLayerSR_2 = NULL,
                            rastLayerWS_1=rastWS_1, rastLayerWS_2 = NULL,
                            gpsdata = ground, pl_j=pl_j, hv_j=hv_j, 
                            planting_harvest_sameYear = planting_harvest_sameYear)
      }
      rainfall_points <- do.call(rbind, rf_result)
      
    }
    
    
    if (planting_harvest_sameYear ==  FALSE) {
      cls <- makeCluster(jobs)
      doParallel::registerDoParallel(cls)
      
      #days <- (365 - pl_j) + hv_j
      
      #rasters <- days%/%31
      
      rf_result2 <- foreach(i = 1:(length(listRaster_RF)-1), .packages = c('terra', 'plyr', 'stringr','tidyr'),
                            .export = c('summarize_pointdata')) %dopar% {
                              
                              #for ( i in 1:(length(listRaster_RF)-1)){
                              rastRF_1 <- listRaster_RF[i]
                              rastRF_2 <- listRaster_RF[i+1]
                              
                              rastTmax_1 <- listRaster_Tmax[i]
                              rastTmax_2 <- listRaster_Tmax[i+1]
                              
                              rastTmin_1 <- listRaster_Tmin[i]
                              rastTmin_2 <- listRaster_Tmin[i+1]
                              
                              rastRH_1 <- listRaster_RH[i]
                              rastRH_2 <- listRaster_RH[i+1]
                              
                              rastSR_1 <- listRaster_SR[i]
                              rastSR_2 <- listRaster_SR[i+1]
                              
                              rastWS_1 <- listRaster_WS[i]
                              rastWS_2 <- listRaster_WS[i+1]
                              
                              print(i)
                              
                              
                              # source("~/agwise-datasourcing/dataops/datasourcing/Scripts/generic/get_geoSpatialData_V2.R", local = TRUE)
                              summarize_pointdata(rastLayerRF_1=rastRF_1, rastLayerRF_2 = rastRF_2, 
                                                  rastLayerTmax_1=rastTmax_1, rastLayerTmax_2 = rastTmax_2,
                                                  rastLayerTmin_1=rastTmin_1, rastLayerTmin_2 = rastTmin_2,
                                                  rastLayerRH_1=rastRH_1, rastLayerRH_2 = rastRH_2,
                                                  rastLayerSR_1=rastSR_1, rastLayerSR_2 = rastSR_2,
                                                  rastLayerWS_1=rastWS_1, rastLayerWS_2 = rastWS_2,
                                                  gpsdata = ground, pl_j=pl_j, hv_j=hv_j,
                                                  planting_harvest_sameYear = planting_harvest_sameYear)
                              
                            }   
      rainfall_points <- do.call(rbind, rf_result2)
      
      
      
      stopCluster(cls)}
    # Compute the seasonal rainfall parameters for trial data: having varying planting and harvest dates
  }else{
    
    rainfall_points <- NULL
    for(i in 1:nrow(ground)){
      print(i)
      groundi <- ground[i,]
      yearPi <- format(as.POSIXlt(groundi$Planting), "%Y")
      yearHi <- format(as.POSIXlt(groundi$Harvesting), "%Y")
      pl_j <-as.POSIXlt(groundi$Planting)$yday
      hv_j <-as.POSIXlt(groundi$Harvesting)$yday
      
      # one layer per trial when pla ting and harvest year are the same, two otherwise
      if (yearPi == yearHi) {
        rastRF_i <-listRaster_RF[which(grepl(yearPi, listRaster_RF, fixed=TRUE) == TRUE)]
        rastRF_i <- terra::rast(rastRF_i, lyrs=c(pl_j:hv_j))
        
        rastTmax_i <-listRaster_Tmax[which(grepl(yearPi, listRaster_Tmax, fixed=TRUE) == TRUE)]
        rastTmax_i <- terra::rast(rastTmax_i, lyrs=c(pl_j:hv_j))
        
        rastTmin_i <-listRaster_Tmin[which(grepl(yearPi, listRaster_Tmin, fixed=TRUE) == TRUE)]
        rastTmin_i <- terra::rast(rastTmin_i, lyrs=c(pl_j:hv_j))
        
        rastRH_i <-listRaster_RH[which(grepl(yearPi, listRaster_RH, fixed=TRUE) == TRUE)]
        rastRH_i <- terra::rast(rastRH_i, lyrs=c(pl_j:hv_j))
        
        rastSR_i <-listRaster_SR[which(grepl(yearPi, listRaster_SR, fixed=TRUE) == TRUE)]
        rastSR_i <- terra::rast(rastSR_i, lyrs=c(pl_j:hv_j))
        
        rastWS_i <-listRaster_WS[which(grepl(yearPi, listRaster_WS, fixed=TRUE) == TRUE)]
        rastWS_i <- terra::rast(rastWS_i, lyrs=c(pl_j:hv_j))
      }else{
        rastRF_i1 <-listRaster_RF[which(grepl(yearPi, listRaster_RF, fixed=TRUE) == TRUE)]
        rastRF_i1 <- terra::rast(rastRF_i1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastRF_i1))))
        rastRF_i2 <-listRaster_RF[which(grepl(yearHi, listRaster_RF, fixed=TRUE) == TRUE)]
        rastRF_i2 <- terra::rast(rastRF_i2, lyrs=c(1:hv_j))
        rastRF_i <- c(rastRF_i1, rastRF_i2)
        
        rastTmax_i1 <-listRaster_Tmax[which(grepl(yearPi, listRaster_Tmax, fixed=TRUE) == TRUE)]
        rastTmax_i1 <- terra::rast(rastTmax_i1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastTmax_i1))))
        rastTmax_i2 <-listRaster_Tmax[which(grepl(yearHi, listRaster_Tmax, fixed=TRUE) == TRUE)]
        rastTmax_i2 <- terra::rast(rastTmax_i2, lyrs=c(1:hv_j))
        rastTmax_i <- c(rastTmax_i1, rastTmax_i2)
        
        rastTmin_i1 <-listRaster_Tmin[which(grepl(yearPi, listRaster_Tmin, fixed=TRUE) == TRUE)]
        rastTmin_i1 <- terra::rast(rastTmin_i1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastTmin_i1))))
        rastTmin_i2 <-listRaster_Tmin[which(grepl(yearHi, listRaster_Tmin, fixed=TRUE) == TRUE)]
        rastTmin_i2 <- terra::rast(rastTmin_i2, lyrs=c(1:hv_j))
        rastTmin_i <- c(rastTmin_i1, rastTmin_i2)
        
        rastRH_i1 <-listRaster_RH[which(grepl(yearPi, listRaster_RH, fixed=TRUE) == TRUE)]
        rastRH_i1 <- terra::rast(rastRH_i1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastRH_i1))))
        rastRH_i2 <-listRaster_RH[which(grepl(yearHi, listRaster_RH, fixed=TRUE) == TRUE)]
        rastRH_i2 <- terra::rast(rastRH_i2, lyrs=c(1:hv_j))
        rastRH_i <- c(rastRH_i1, rastRH_i2)
        
        rastSR_i1 <-listRaster_SR[which(grepl(yearPi, listRaster_SR, fixed=TRUE) == TRUE)]
        rastSR_i1 <- terra::rast(rastSR_i1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastSR_i1))))
        rastSR_i2 <-listRaster_SR[which(grepl(yearHi, listRaster_SR, fixed=TRUE) == TRUE)]
        rastSR_i2 <- terra::rast(rastSR_i2, lyrs=c(1:hv_j))
        rastSR_i <- c(rastSR_i1, rastSR_i2)
        
        rastWS_i1 <-listRaster_WS[which(grepl(yearPi, listRaster_WS, fixed=TRUE) == TRUE)]
        rastWS_i1 <- terra::rast(rastWS_i1, lyrs=c(pl_j:terra::nlyr(terra::rast(rastWS_i1))))
        rastWS_i2 <-listRaster_WS[which(grepl(yearHi, listRaster_WS, fixed=TRUE) == TRUE)]
        rastWS_i2 <- terra::rast(rastWS_i2, lyrs=c(1:hv_j))
        rastWS_i <- c(rastWS_i1, rastWS_i2)
        
      }
      
      ##Extract the information for the i-th row ####
      xy <- groundi[, c("longitude", "latitude")]
      xy <- xy %>%
        mutate_if(is.character, as.numeric)
      
      rainfall_points_i <- terra::extract(rastRF_i, xy,method='simple', cells=FALSE)
      Tmax_points_i <- terra::extract(rastTmax_i, xy,method='simple', cells=FALSE)
      Tmin_points_i <- terra::extract(rastTmin_i, xy,method='simple', cells=FALSE)
      RH_points_i <- terra::extract(rastRH_i, xy,method='simple', cells=FALSE)
      SR_points_i <- terra::extract(rastSR_i, xy,method='simple', cells=FALSE)
      WS_points_i <- terra::extract(rastWS_i, xy,method='simple', cells=FALSE)
      
      
      Tmax_points_i <- Tmax_points_i-274
      Tmin_points_i <- Tmin_points_i-274
      SR_points_i <- SR_points_i/1000000
      
      
      ## get year
      groundi$Year <- yearPi
      
      # Compute the total amount of rainfall
      groundi$totalRF <- sum(rainfall_points_i[c(2:length(rainfall_points_i))])
      
      # Compute the Number of rainy day
      nrdi <- rainfall_points_i[c(2:length(rainfall_points_i))]
      nrdi[nrdi < 2] <- 0
      nrdi[nrdi >= 2] <- 1
      groundi$nrRainyDays <- sum(nrdi)
      
      # Compute monthly total, at 31 days interval and the remaining  days at the end
      mrdi <- rainfall_points_i[c(2:length(rainfall_points_i))]
      mtmaxi <- Tmax_points_i[c(2:length(Tmax_points_i))]
      mtmini <- Tmin_points_i[c(2:length(Tmin_points_i))]
      mrhi <- RH_points_i[c(2:length(RH_points_i))]
      msri <- SR_points_i[c(2:length(SR_points_i))]
      mwsi <- WS_points_i[c(2:length(WS_points_i))]
      
      
      mdiv <- unique(c(seq(1, length(mrdi), 30), length(mrdi)))
      length(mtmini)
      
      mdivq <- length(mrdi)%/%31
      mdivr <- length(mrdi)%%31
      
      ##################
      mrf <- NULL
      for (q in 1:mdivq){
        mrf <- c(mrf, sum(mrdi[((q*31)-30):(q*31)]))	
      }
      # Then add the remainder
      mrf <- c(mrf, sum(mrdi[(q*31):((q*31)+mdivr)]))
      
      mtmax <- NULL
      for (q in 1:mdivq){
        mtmax <- c(mtmax, mean(as.numeric(mtmaxi[((q*31)-30):(q*31)])))	
      }
      # Then add the remainder
      mtmax <- c(mtmax, mean(as.numeric(mtmaxi[(q*31):((q*31)+mdivr)])))
      
      mtmin <- NULL
      for (q in 1:mdivq){
        mtmin <- c(mtmin, mean(as.numeric(mtmini[((q*31)-30):(q*31)])))	
      }
      # Then add the remainder
      mtmin <- c(mtmin, mean(as.numeric(mtmini[(q*31):((q*31)+mdivr)])))
      
      mrh <- NULL
      for (q in 1:mdivq){
        mrh <- c(mrh, mean(as.numeric(mrhi[((q*31)-30):(q*31)])))	
      }
      # Then add the remainder
      mrh <- c(mrh, mean(as.numeric(mrhi[(q*31):((q*31)+mdivr)])))
      
      msr <- NULL
      for (q in 1:mdivq){
        msr <- c(msr, mean(as.numeric(msri[((q*31)-30):(q*31)])))	
      }
      # Then add the remainder
      msr <- c(msr, mean(as.numeric(msri[(q*31):((q*31)+mdivr)])))
      
      mws <- NULL
      for (q in 1:mdivq){
        mws <- c(mws, mean(as.numeric(mwsi[((q*31)-30):(q*31)])))	
      }
      # Then add the remainder
      mws <- c(mws, mean(as.numeric(mwsi[(q*31):((q*31)+mdivr)])))
      
      ###########
      
      # mrf <- c()
      # mtmax <- c()
      # mtmin <- c()
      # mrh <- c()
      # msr <- c()
      # mws <- c()
      # for (k in 1:(length(mdiv)-1)) {
      #   print(k)
      #   if(k == 1){
      #     mrf <- c(mrf, sum(mrdi[c(mdiv[k]:mdiv[k+1])]))
      #     mtmax <- c(mtmax, mean(as.numeric(mtmaxi[c(mdiv[k]:mdiv[k+1])])))
      #     mtmin <- c(mtmin, mean(as.numeric(mtmini[c(mdiv[k]:mdiv[k+1])])))
      #     mrh <- c(mrh, mean(as.numeric(mrhi[c(mdiv[k]:mdiv[k+1])])))
      #     msr <- c(msr, mean(as.numeric(msri[c(mdiv[k]:mdiv[k+1])])))
      #     mws <- c(mws, mean(as.numeric(mwsi[c(mdiv[k]:mdiv[k+1])])))
      #   }else{
      #     mrf <- c(mrf, sum(mrdi[c((mdiv[k]+1):(mdiv[k+1]))]))
      #     mtmax <- c(mtmax, mean(as.numeric(mtmaxi[c((mdiv[k]+1):(mdiv[k+1]))])))
      #     mtmin <- c(mtmin, mean(as.numeric(mtmini[c((mdiv[k]+1):(mdiv[k+1]))])))
      #     mrh <- c(mrh, mean(as.numeric(mrhi[c((mdiv[k]+1):(mdiv[k+1]))])))
      #     msr <- c(msr, mean(as.numeric(msri[c((mdiv[k]+1):(mdiv[k+1]))])))
      #     mws <- c(mws, mean(as.numeric(mwsi[c((mdiv[k]+1):(mdiv[k+1]))])))
      #   }
      # }
      
      ## if the crop is > 15 months on the field (to make it work for cassava, hatcan have 15 months growing period)
      if(length(mrf) > 15){
        mrf <- c(mrf, rep("NA", 15 - length(mrf)))
        mtmax <- c(mtmax, rep("NA", 15 - length(mtmax)))
        mtmin <- c(mtmin, rep("NA", 15 -length(mtmin)))
        mrh <- c(mrh, rep("NA", 15 -length(mrh)))
        msr <- c(msr, rep("NA", 15 -length(msr)))
        mws <- c(mws, rep("NA", 15 -length(mws)))
      }
      
      mrf_names <- c(paste0("Rainfall_month", c(1:15)))
      mtmax_names <- c(paste0("Tmax_month", c(1:15)))
      mtmin_names <- c(paste0("Tmin_month", c(1:15)))
      mrh_names <- c(paste0("relativeHumid_month", c(1:15)))
      msr_names <- c(paste0("solarRad_month", c(1:15)))
      mws_names <- c(paste0("windSpeed_month", c(1:15)))
      
      
      for (h in 1:length(mrf_names)) {
        colname <- mrf_names[h]
        groundi[[colname]] <- mrf[h]
        
        colname <- mtmax_names[h]
        groundi[[colname]] <- mtmax[h]
        
        colname <- mtmin_names[h]
        groundi[[colname]] <- mtmin[h]
        
        colname <- mrh_names[h]
        groundi[[colname]] <- mrh[h]
        
        colname <- msr_names[h]
        groundi[[colname]] <- msr[h]
        
        colname <- mws_names[h]
        groundi[[colname]] <- mws[h]
      }
      
      groundi <- subset(groundi, select=-c(plantingDate, harvestDate, Year))
      
      rainfall_points <- bind_rows(rainfall_points, groundi)
    }
  }
  
  
  ## drop NA columns and save result
  rainfall_points <- rainfall_points %>% 
    select_if(~sum(!is.na(.)) > 0)
  
  if(AOI == TRUE){
    fname <- paste("weatherSummaries_Season_", season, "_AOI.RDS",sep="")
  }else{
    fname <- "weatherSummaries_trial.RDS"
  }
  saveRDS(object = rainfall_points, file=paste(pathOut, fname, sep="/"))
  
  return(rainfall_points)
  
}

###############################################################################################
###############################################################################################
###############################################################################################
## Get daily weather data, as ( longitude, latitude, NAME_1, Rainfall, location, date, pl_year)
get_weather_seasonality <- function(
    country, useCaseName, Crop , Planting_month_date = NULL, 
    Harvest_month_date = NULL, varName, plantingWindow = 1, jobs) {
  
  ARD <- Paths_Vars(country=country, useCaseName=useCaseName, Crop=Crop, inputData = inputData, 
                    Planting_month_date=Planting_month_date, Harvest_month_date=Harvest_month_date,
                    soilProfile =FALSE, AOI = AOI,  pathOut = pathOut)
  
  inputData <- ARD[[1]]
  listRasterRF <- ARD[[2]]
  listRasterTmax <- ARD[[3]]
  listRasterTMin <- ARD[[4]]
  listRasterRH <- ARD[[5]]
  listRasterSR <- ARD[[6]]
  listRasterWS <- ARD[[7]]
  Layers_soil <- ARD[[8]]
  Layers_soil_isric <- ARD[[9]]
  shapefileHC <- ARD[[10]]
  pathOut <- ARD[[11]]
  
  
  inputData <- readRDS(paste("~/agwise-datacuration/dataops/datacuration/Data/useCase_",country, "_", useCaseName,"/", Crop, "/result/AOI_GPS.RDS", sep=""))
  
  
  
  # inputData <- droplevels(inputData[inputData$NAME_1 %in% Regions, ])
  
  pathOut1 <- paste("~/agwise-datasourcing/dataops/datasourcing/Data/useCase_", country, "_", useCaseName,"/", Crop, "/result/", sep="")
  
  if (!dir.exists(pathOut1)){
    dir.create(file.path(pathOut1), recursive = TRUE)
  }
  
  if(is.null(Planting_month_date) | is.null(Harvest_month_date)){
    print("with AOI=TRUE, Planting_month_date, Harvest_month_date can not be null, please refer to the documentation and provide mm-dd for both parameters")
    return(NULL)
  }
  
  ## check if both planting and harvest dates are in the same year
  Planting_month <- as.numeric(str_extract(Planting_month_date, "[^-]+"))
  Harvest_month <- as.numeric(str_extract(Harvest_month_date, "[^-]+"))
  
  ## py and hy are used only as place holder for formatting purposes
  if(Planting_month < Harvest_month){
    planting_harvest_sameYear <- TRUE
    py <- 2000
    hy <- 2000
  }else{
    planting_harvest_sameYear <- FALSE
    py <- 2000
    hy <- 2001
  }
  
  ## set planting date one moth prior to the given Planting_month_date so that initial condition for the crop model could be set correctly
  Planting_month_date <-as.Date(paste0(py, "-",Planting_month_date)) ## the year is only a place holder to set planting month 1 month earlier
  Planting_month_date <- Planting_month_date %m-% months(1)
  
  ## if multiple planting dates are to be tested, adjust the Harvest_month_date to extract weather data for the later planting dates.  
  Harvest_month_date <- as.Date(paste0(hy, "-",Harvest_month_date)) ## the year is only a place holder to set planting month 1 month earlier
  if(plantingWindow > 1 & plantingWindow <= 5){
    Harvest_month_date <- Harvest_month_date %m+% months(1)
  }else if(plantingWindow > 5 & plantingWindow <=8){
    Harvest_month_date <- Harvest_month_date %m+% months(2)
  }else if(plantingWindow > 8 & plantingWindow <=12){
    Harvest_month_date <- Harvest_month_date %m+% months(3)
  }
  
  
  ## 1. read all the raster files 
  if(varName == "Rainfall"){
    listRaster <-list.files(path="/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/Rainfall/chirps", pattern=".nc$", full.names = TRUE)
  }else if (varName == "temperatureMax"){
    listRaster <-list.files(path="/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/TemperatureMax/AgEra", pattern=".nc$", full.names = TRUE)
  }else if (varName == "temperatureMin"){
    listRaster <-list.files(path="/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/TemperatureMin/AgEra", pattern=".nc$", full.names = TRUE)
  }else if(varName == "relativeHumidity"){
    listRaster <-list.files(path="/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/RelativeHumidity/AgEra", pattern=".nc$", full.names = TRUE)
  }else if(varName == "solarRadiation"){
    listRaster <-list.files(path="/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/SolarRadiation/AgEra", pattern=".nc$", full.names = TRUE)
  }else if(varName == "windSpeed"){
    listRaster <-list.files(path="/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/Global_GeoData/Landing/WindSpeed/AgEra", pattern=".nc$", full.names = TRUE)
  }
  
  
  if(varName == "Rainfall"){
    listRaster <- listRaster[10:42]
  }else {
    listRaster <- listRaster[12:44]
  }
  
  
  ## 2. format the input data with GPS, dates and ID and add administrative unit info
  countryCoord <- unique(inputData[, c("lon", "lat")])
  countryCoord <- countryCoord[complete.cases(countryCoord), ]
  ## After checking if planting and harvest happens in the same year, get the date of the year 
  countryCoord$startingDate <- Planting_month_date
  countryCoord$endDate <- Harvest_month_date
  countryCoord <- countryCoord[complete.cases(countryCoord), ]
  names(countryCoord) <- c("longitude", "latitude", "startingDate", "endDate")
  countryCoord$ID <- c(1:nrow(countryCoord))
  ground <- countryCoord[, c("longitude", "latitude", "startingDate", "endDate", "ID")]
  
  
  
  # ground$harvestDate <- as.Date(ground$harvestDate, "%Y-%m-%d")
  countryShp <- geodata::gadm(country, level = 2, path='.')
  dd2 <- raster::extract(countryShp, ground[, c("longitude", "latitude")])[, c("NAME_1", "NAME_2")]
  ground$NAME_1 <- dd2$NAME_1
  ground$NAME_2 <- dd2$NAME_2
  
  ## 3.get the seasonal rainfall parameters for AOI
  if (planting_harvest_sameYear ==  TRUE) {
    
    cls <- makeCluster(jobs)
    doParallel::registerDoParallel(cls)
    
    rf_result <- foreach(i=1:length(listRaster), .packages = c('terra', 'plyr', 'stringr','tidyr')) %dopar% {
      rasti <- listRaster[i]
      pl_j <-as.POSIXlt(unique(ground$startingDate))$yday
      hv_j <-as.POSIXlt(unique(ground$endDate))$yday
      PlHvD <- terra::rast(rasti, lyrs=c(pl_j:hv_j))
      xy <- ground[, c("longitude", "latitude")]
      raini <- terra::extract(PlHvD, xy, method='simple', cells=FALSE)
      raini <- raini[,-1]
      if(varName %in% c("temperatureMax","temperatureMin")){
        raini <- raini-274
      }else if (varName == "solarRadiation"){
        raini <- raini/1000000
      }
      ground_adj <- ground
      lubridate::year(ground_adj$startingDate) <- as.numeric(str_extract(rasti, "[[:digit:]]+"))
      lubridate::year(ground_adj$endDate) <- as.numeric(str_extract(rasti, "[[:digit:]]+"))
      start <- as.Date(unique(ground_adj$startingDate))
      maxDaysDiff <- abs(max(min(pl_j) - max(hv_j)))
      end <- start + as.difftime(maxDaysDiff, units="days")
      ddates <- seq(from=start, to=end, by=1)
      # names(raini) <- paste(varName, ddates[1:length(names(raini))], sep="_")
      # names(raini) <- paste(varName, sub("^[^_]+", "", names(raini)), sep="")
      ground_adj$startingDate <- as.character(ground_adj$startingDate)
      ground_adj$endDate <- as.character(ground_adj$endDate)
      ground2 <- cbind(ground_adj, raini)
      ground3 <- gather(ground2, year, Rainfall, names(raini)[1]:names(raini)[length(raini)])
      ground3$location <- paste(ground3$longitude, ground3$latitude, sep="_")
      ground3 <- ground3 %>%
        dplyr::group_by(location ) %>%
        dplyr::mutate(date = c(ddates)) %>%
        as.data.frame()
      ground3$pl_year <- as.numeric(str_extract(rast1, "[[:digit:]]+"))
      ground3 <- subset(ground3, select=-c(startingDate, endDate, ID, year, NAME_2))
    }
    
    data_points <- dplyr::bind_rows(rf_result)
    stopCluster(cls)
  }else{
    cls <- makeCluster(jobs)
    doParallel::registerDoParallel(cls)
    ## Rainfall
    rf_result2 <- foreach(i = 1:(length(listRaster)-1), .packages = c('terra', 'plyr', 'stringr','tidyr')) %dopar% {
      listRaster <- listRaster[order(listRaster)]
      rast1 <- listRaster[i]
      rast2 <- listRaster[i+1]
      ground_adj <- ground
      lubridate::year(ground_adj$startingDate) <- as.numeric(str_extract(rast1, "[[:digit:]]+"))
      lubridate::year(ground_adj$endDate) <- as.numeric(str_extract(rast2, "[[:digit:]]+"))
      start <- as.Date(unique(ground_adj$startingDate))
      maxDaysDiff <- as.numeric(max(ground_adj$endDate) - min(ground_adj$startingDate))
      end <- start + as.difftime(maxDaysDiff, units="days")
      ddates <- seq(from=start, to=end, by=1)
      # Convert planting Date and harvesting in Julian Day 
      pl_j <-as.POSIXlt(unique(ground_adj$startingDate))$yday
      hv_j <-as.POSIXlt(unique(ground_adj$endDate))$yday
      rasti1 <- terra::rast(rast1, lyrs=c(pl_j:terra::nlyr(terra::rast(rast1))))
      rasti2 <- terra::rast(rast2, lyrs=c(1:hv_j))
      PlHvD <- c(rasti1, rasti2)
      xy <- ground[, c("longitude", "latitude")]
      raini <- terra::extract(PlHvD, xy, method='simple', cells=FALSE)
      raini <- raini[,-1]
      if(varName %in% c("temperatureMax","temperatureMin")){
        raini <- raini-274
      }else if (varName == "solarRadiation"){
        raini <- raini/1000000
      }
      
      
      ground2 <- cbind(ground_adj, raini)
      ground3 <- gather(ground2, year, Rainfall, names(raini)[1]:names(raini)[length(raini)])
      ground3$location <- paste(ground3$longitude, ground3$latitude, sep="_")
      ground3 <- ground3 %>%
        dplyr::group_by(location ) %>%
        dplyr::mutate(date = c(ddates)) %>%
        as.data.frame()
      ground3$pl_year <- as.numeric(str_extract(rast1, "[[:digit:]]+"))
      ground3 <- subset(ground3, select=-c(startingDate, endDate, ID, year, NAME_2))
    }
    data_points <- dplyr::bind_rows(rf_result2)
    stopCluster(cls)
    
  }   
  
  
  data_points <- data_points %>% 
    select_if(~sum(!is.na(.)) > 0)
  
  return(data_points)
}


### Run the soil data pipeline for a forecast usecase
get_soil_for_forecast <- function(
    cfg, season = 1, inputData = NULL, level2 = FALSE, 
    planting_window = 12, AOI = TRUE,
    soilData = TRUE, weatherData = TRUE, soilProfile = TRUE) {
  
  yml_config <- yaml::read_yaml(cfg$yml_config_path)
  country <- yml_config$country_name
  useCaseName <- yml_config$use_case_name
  Crop <- yml_config$crop
  country_shp_path <- cfg$dir_raw_admin
  country_code <- yml_config$country_code
  dir_geo_cropmodel <- cfg$dir_geo_cropmodel
  
  message("Creating ISRIC soil data for ", country)
  
  if (!dir.exists(country_shp_path)) {
    dir.create(country_shp_path, recursive = TRUE)
  }
  
  countryShapefile <- geodata::gadm(country = country, level = 2, 
                                    path = country_shp_path)

  
  if(is.null(inputData)) {
    inputData <- load_or_generate_inputData_forecast(
      country = country, 
      useCaseName = useCaseName, 
      Crop = Crop, 
      dir_s2s = cfg$dir_s2s, 
      countryShapefile = countryShapefile,
      inputData = NULL)
  }
  
  if (!level2 || is.na(level2)) {
    zones <- unique(inputData$NAME_1)
  } else if (level2) {
    zones <- unique(inputData$NAME_2)
  }
  
  # Get ISRIC soil data
  for (zone in zones) {
    message(paste0("Producing ISRIC soil data for ", zone))
    
    zone_inputData <- inputData[inputData$NAME_1 == zone, ]
    
    pathOut <- paste0(
      dir_geo_cropmodel, "/", zone, "/")
    
    if (!dir.exists(pathOut)) {
      dir.create(pathOut, recursive = TRUE)
    }
    
    geoSpatialData <- extract_geoSpatialPointData(
      country = country, useCaseName = useCaseName, Crop = Crop, 
      inputData = zone_inputData, countryShapefile = countryShapefile, AOI = AOI, 
      Planting_month_date = NULL, 
      Harvest_month_date = NULL,
      soilData = soilData, weatherData = weatherData, soilProfile = soilProfile, 
      plantingWindow = NULL, season = season, pathOut = pathOut
    )
  }
  message("All geospatial data produced.")
}
