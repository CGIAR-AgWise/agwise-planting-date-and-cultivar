# Create DSSAT experimental file

# Introduction: 
# This script allows the creation of experimental files up to administrative level 2
# The file also allows to copy the CUL file from the landing folder in case there is a
# new variety or the parameters are modified from the released version of DSSAT
# Authors : P.Moreno, A. Sila, S. Mkuhlani, E.Bendito Garcia 
# Credentials : EiA, 2024
# Last modified April 08, 2024 


#################################################################################################################
## sourcing required packages 
#################################################################################################################
packages_required <- c("tidyverse", "lubridate","DSSAT","furrr","future","future.apply")

# check and install packages that are not yet installed
installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
  install.packages(packages_required[!installed_packages])}

# load required packages
invisible(lapply(packages_required, library, character.only = TRUE))

#Sys.setenv(R_CSTACK_LIMIT = 100000000)
#options(future.globals.maxSize = 1024 * 1024 * 1024)

#' Create one experimental file (repetitive function)
#' Copy the CUL,ECO and SPE files from the path.to.temdata (template files)
#'
#' @param i point/folder from a list
#' @param path.to.temdata directory with template CUL,weather and soil data in DSSAT format
#' @param filex_temp Name of the template experimental file in DSSAT format (FILEX)
#' @param path.to.extdata working directory to save the weather and soil data in DSSAT format
#' @param coords dataframe with the locations and metadata (created by the function dssat.expfile)
#' @param AOI "Area of interest" AOI=TRUE when we want to explore crop simulations with historical data.
#'        AOI= FALSE when there is information for actual trial sites (with observed yield data).
#' @param crop_code crop code in DSSAT format (e.g. "MZ" for maize, created by function dssat.expfile)
#' @param plantingWindow number of weeks that define the planting window considering the Planting_month_date as the earliest planting week. 
#'        It is given when several planting dates are to be tested to determine optimal planting date (applies when AOI= TRUE)  
#' @param number_years Number of years the simulations are run when AOI=TRUE (it does not apply to the trial location data)
#' @param varietyid id of the variety based on the cultivar file of DSSAT (column @VAR# in the cultivar file and parameter 
#'        INGENO in the experimental file *.**X)
#' @param zone Name of the administrative level 1 for the specific location the experimental file is created.
#' @param level2 Name of the administrative level 2 (has to be part of the administrative level 1 or "zone" of the country) 
#'        for the specific location the experimental file is created
#' @param fertilizer if TRUE the parameter modifies the fertilizer date to be at planting 
#' @param geneticfiles Name of CUL, ECO and SPE file to be copied (e.g., MZCER048)
#' @param index_soilwat Index to define the initial soil water content. If 1 the initial soil water is field capacity 
#'        and if 0, the initial soil water is wilting point
#' @return
#'
#' @examples create_filex(i=1,path.to.temdata = "/home/jovyan/agwise-potentialyield/dataops/potentialyield/Data/useCase_Kenya_KALRO/Maize/Landing/DSSAT",
#'                        filex_temp="KEAG8104.MZX",
#'                        path.to.extdata = "/home/jovyan/agwise-potentialyield/dataops/potentialyield/Data/useCase_Keny_KALRO/Maize/transform/DSSAT/AOI/999991",
#'                        country="Kenya", AOI=TRUE, crop_code ="MZ",plantingWindow=1,number_years,varietyid = "999991", zone ="Tete", level2=NA,
#'                        fertilizer=FALSE, geneticfiles = "MZCER048",index_soilwat=1)




create_filex <-function(i,path.to.temdata,filex_temp,path.to.extdata,coords, AOI=TRUE, 
                        crop_code,plantingWindow=1,number_years,varietyid, zone, level2=NA,
                        fertilizer =FALSE,geneticfiles,index_soilwat=1){
  #print(paste("Experiment number", i))
  setwd(path.to.temdata)
  #Read in original FileX
  file_x <- DSSAT::read_filex(filex_temp)
  #define working path (each point to be run)
  if(!is.na(level2) & !is.na(zone)){
    working_path <- paste(path.to.extdata,paste0(zone,'/',level2,'/EXTE', formatC(width = 4, (as.integer(i)), flag = "0")), sep = "/")
  }else if(is.na(level2) & !is.na(zone)){
    working_path <- paste(path.to.extdata,paste0(zone,'/EXTE', formatC(width = 4, (as.integer(i)), flag = "0")), sep = "/")
  }else if(!is.na(level2) & is.na(zone)){
    print("You need to define first a zone (administrative level 1) to be able to get data for level 2 (administrative level 2). Process stopped")
    return(NULL)
  }else{
    working_path <- paste(path.to.extdata,paste0('EXTE', formatC(width = 4, (as.integer(i)), flag = "0")), sep = "/")
  }
  if (!dir.exists(file.path(working_path))){
    dir.create(file.path(working_path), recursive = TRUE)
  }
  #copy genetic files
  gen_parameters <- list.files(pattern = geneticfiles, full.names = TRUE) 
  file.copy(gen_parameters, working_path,overwrite = TRUE)
  #Set the experimental directory
  setwd(working_path)
  
  if(AOI==TRUE){
    #Make proposed changes to FileX
    file_x$FIELDS$WSTA<-paste0("WHTE", formatC(width = 4, as.integer((i)), flag = "0"))
    file_x$FIELDS$ID_SOIL<-paste0('TRAN', formatC(width = 5, as.integer((i)), flag = "0"))
    file_x$CULTIVARS$CR <- crop_code
    file_x$CULTIVARS$INGENO <- varietyid
    ex_profile <- DSSAT::read_sol("SOIL.SOL", id_soil = paste0('TRAN', formatC(width = 5, as.integer((i)),flag = "0")))
    #Assume a proportion between wilting point and field capacity as initial condition
    file_x$`INITIAL CONDITIONS`$SH2O<- mapply(function(sdul, slll, index) {
      slll + ((sdul-slll) * index)}, ex_profile$SDUL, ex_profile$SLLL, MoreArgs = list(index = index_soilwat), SIMPLIFY = FALSE)
    file_x$`INITIAL CONDITIONS`$ICBL <- ex_profile$SLB
    file_x$`INITIAL CONDITIONS`$ICDAT <- as.POSIXct(coords$startingDate[i])
    file_x$`PLANTING DETAILS`$PDATE <- as.POSIXct(coords$plantingDate[i])
    
    if(fertilizer == T){
      file_x$`FERTILIZERS (INORGANIC)`$FDATE <- as.POSIXct(coords$plantingDate[i]) #fertilizer at planting
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$TNAME <- paste0(file_x$`FERTILIZERS (INORGANIC)`$FERNAME[1], " Planting 0")
    }else{
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$TNAME <- paste0("Initial planting")
    }
    
    file_x$`HARVEST DETAILS`$HDATE <- as.POSIXct(coords$harvestDate[i])
    file_x$`SIMULATION CONTROLS`$SDATE <- as.POSIXct(coords$startingDate[i])
    file_x$`SIMULATION CONTROLS`$NYERS <- number_years
    
    for (j in 1:plantingWindow){
      file_x$`INITIAL CONDITIONS`<- file_x$`INITIAL CONDITIONS` %>% add_row(!!!file_x$`INITIAL CONDITIONS`[file_x$`INITIAL CONDITIONS`$C==1,])
      file_x$`INITIAL CONDITIONS`[1+j,]$C <- 1+j
      file_x$`INITIAL CONDITIONS`[1+j,]$ICDAT <- as.POSIXct(coords$startingDate[i]) %m+% weeks(j)
      
      file_x$`PLANTING DETAILS` <- file_x$`PLANTING DETAILS` %>% add_row(!!!file_x$`PLANTING DETAILS`[file_x$`PLANTING DETAILS`$P==1,])
      file_x$`PLANTING DETAILS`[1+j,]$P <- 1+j
      file_x$`PLANTING DETAILS`[1+j,]$PDATE <- as.POSIXct(coords$plantingDate[i]) %m+% weeks(j)
      
      if(fertilizer == T){
        file_x$`FERTILIZERS (INORGANIC)` <- file_x$`FERTILIZERS (INORGANIC)` %>% add_row(!!!file_x$`FERTILIZERS (INORGANIC)`[file_x$`FERTILIZERS (INORGANIC)`$F==1,])
        file_x$`FERTILIZERS (INORGANIC)`[1+j,]$F <- 1+j
        file_x$`FERTILIZERS (INORGANIC)`[1+j,]$FDATE <- as.POSIXct(coords$plantingDate[i]) %m+% weeks(j)
      }
      
      file_x$`HARVEST DETAILS` <- file_x$`HARVEST DETAILS` %>% add_row(!!!file_x$`HARVEST DETAILS`[file_x$`HARVEST DETAILS`$H==1,])
      file_x$`HARVEST DETAILS`[1+j,]$HDATE <- as.POSIXct(coords$harvestDate[i]) %m+% weeks(j)
      file_x$`HARVEST DETAILS`[1+j,]$H <- 1+j
      
      file_x$`SIMULATION CONTROLS`<- file_x$`SIMULATION CONTROLS` %>% add_row(!!!file_x$`SIMULATION CONTROLS`[file_x$`SIMULATION CONTROLS`$N==1,])
      file_x$`SIMULATION CONTROLS`[1+j,]$N <- 1+j
      file_x$`SIMULATION CONTROLS`[1+j,]$SDATE <- as.POSIXct(coords$startingDate[i]) %m+% weeks(j)
      
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` <- file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` %>% 
        add_row(!!!file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$N==1,])
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$N <- 1+j
      if(fertilizer == T){
        file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$TNAME <- paste0(file_x$`FERTILIZERS (INORGANIC)`$FERNAME[1], " + ", j ,"weeks")
      }else {
        file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$TNAME <- paste0("Planting + ", j ,"weeks")
      }
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$IC <- 1+j
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$MP <- 1+j
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$MH <- 1+j
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$SM <- 1+j
    }
    
    #Overwrite original FileX with new values
    DSSAT::write_filex(file_x,paste0('EXTE', formatC(width = 4, as.integer((i)), flag = "0"),'.',crop_code,'X'))
  }else{
    #Make proposed changes to FileX
    file_x$FIELDS$WSTA <- paste0("WHTE", formatC(width = 4, as.integer((i)), flag = "0"))
    file_x$FIELDS$ID_SOIL<-paste0('TRAN', formatC(width = 5, as.integer((i)), flag = "0"))
    file_x$CULTIVARS$CR <- crop_code
    file_x$CULTIVARS$INGENO <- varietyid
    file_x$`PLANTING DETAILS`$PDATE <- as.POSIXct(coords$plantingDate[i])
    file_x$`SIMULATION CONTROLS`$SDATE <- as.POSIXct(coords$startingDate[i])
    file_x$`HARVEST DETAILS`$HDATE <- as.POSIXct(coords$harvestDate[i])
    #file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$TNAME <- paste0("Trial planting")
    
    ex_profile <- suppressWarnings(DSSAT::read_sol("SOIL.SOL", id_soil = paste0('TRAN', formatC(width = 5, as.integer((i))," ", flag = "0"))))
    file_x$`INITIAL CONDITIONS`$ICDAT <- as.POSIXct(coords$startingDate[i])  #Meanwhile the same date than the planting date## this is changed to a month prior to planting, right??
    #Assume a proportion between wilting point and field capacity as initial condition
    file_x$`INITIAL CONDITIONS`$SH2O<- mapply(function(sdul, slll, index) {
      slll + ((sdul-slll) * index)}, ex_profile$SDUL, ex_profile$SLLL, MoreArgs = list(index = index_soilwat), SIMPLIFY = FALSE)
    file_x$`INITIAL CONDITIONS`$ICBL <- ex_profile$SLB
    #Overwrite original FileX with new values
    DSSAT::write_filex(file_x,paste0('EXTE', formatC(width = 4, as.integer((i)), flag = "0"),'.',crop_code,'X'))
    
  }
  rm(file_x,ex_profile)
  gc()
} 



#' Create multiple experimental files
#'
#' @param country country name
#' @param useCaseName use case name 
#' @param Crop the name of the crop to be used in creating file name to write out the result.
#' @param AOI "Area of interest" AOI=TRUE when we want to explore crop simulations with historical data.
#'        AOI= FALSE when there is information for actual trial sites (with observed yield data).
#' @param filex_temp Name of the template experimental file in DSSAT format (FILEX)
#' @param Planting_month_date it is needed only when AOI=TRUE and it should be provided as mm-dd format 
#' @param Harvest_month_date if AOI =TRUE, Harvest_month_date is the initial month for harvesting and it should be provided in mm-dd format.
#'        The parameter is no needed it when AOI=FALSE because the actual harvesting date from the trials would be provided.   
#' @param ID trial ID
#' @param season when data is needed for more than one season, this needs to be provided to be used in the file name
#' @param plantingWindow number of weeks starting considering the Planting_month_date as earliest planting week. It is given when several 
#'        planting dates are to be tested to determine optimal planting date
#' @param varietyid ID of the variety based on the cultivar file of DSSAT (column @VAR# in the cultivar file and parameter INGENO in the experimental file *.**X)
#' @param zone Name of administrative level 1 for the specific location the experimental file is created
#' @param level2 Name of administrative level 2 (part of the administrative level 1 or "zone") for the specific location the experimental file is created
#' @param fertilizer if TRUE the parameter modifies the fertilizer date to be at planting
#'
#' @return
#' @export
#'
#' @examples dssat.expfile(country="Mozambique", useCaseName = "Solidaridad", Crop = "Maize", AOI = FALSE,
#'                         filex_temp= "ELZA0201.MZX", Planting_month_date=NULL,Harvest_month_date=NULL, 
#'                         ID="TLID",season = 1, plantingWindow = 1,varietyid = "999991", zone ="Tete", level2=NA,fertilizer=F,
#'                         geneticfiles = "MZCER048",index_soilwat=1)

dssat.expfile <- function(country, useCaseName, Crop, AOI = TRUE,filex_temp, Planting_month_date=NULL,Harvest_month_date=NULL, 
                          ID="TLID",season =1, plantingWindow=1,varietyid, zone, level2=NA, fertilizer=F,geneticfiles,index_soilwat=1,pathIn_zone =F){  
  print(paste("Variety:", varietyid,"Zone:", zone))
  if(AOI == TRUE){
    if(is.null(Planting_month_date) | is.null(Harvest_month_date)){
      print("with AOI=TRUE, Planting_month_date, Harvest_month_date can not be null, please refer to the documentation and provide mm-dd for both parameters")
      return(NULL)
    }
    countryCoord <- readRDS(paste("~/agwise-datacuration/dataops/datacuration/Data/useCase_", country, "_",useCaseName, "/", Crop, "/result/AOI_GPS.RDS", sep=""))
    
    countryCoord <- unique(countryCoord[, c("lon", "lat")])
    countryCoord <- countryCoord[complete.cases(countryCoord), ]
    
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
    countryCoord$plantingDate <- Planting_month_date
    Planting_month_date <- Planting_month_date %m-% months(1)
    
    ## if multiple planting dates are to be tested, adjust the Harvest_month_date to extract weather data for the later planting dates.  
         if(Crop == "Cassava"){
      duration <- as.Date(paste0(hy, "-",Harvest_month_date))-Planting_month_date
      if (duration < 240){
        hy <- hy+1
      }
    }
    Harvest_month_date <- as.Date(paste0(hy, "-",Harvest_month_date)) ## the year is only a place holder to set planting month 1 month earlier
    countryCoord$harvestDate <- Harvest_month_date
    if(plantingWindow > 1 & plantingWindow <= 5){
      Harvest_month_date <- Harvest_month_date %m+% months(1)
    }else if(plantingWindow > 5 & plantingWindow <=30){
      Harvest_month_date <- Harvest_month_date %m+% months(2)
    }
    
    countryCoord$startingDate <- Planting_month_date
    countryCoord$endDate <- Harvest_month_date
    
    countryCoord <- countryCoord[complete.cases(countryCoord), ]
    names(countryCoord) <- c("longitude", "latitude","plantingDate", "harvestDate", "startingDate", "endDate")
    ground <- countryCoord
    
  }else{
    GPS_fieldData <- readRDS(paste("~/agwise-datacuration/dataops/datacuration/Data/useCase_",country, "_",useCaseName, "/", Crop, "/result/compiled_fieldData.RDS", sep=""))  
    countryCoord <- unique(GPS_fieldData[, c("lon", "lat", "plantingDate", "harvestDate")])
    countryCoord <- countryCoord[complete.cases(countryCoord), ]
    countryCoord$startingDate <- as.Date(countryCoord$plantingDate, "%Y-%m-%d") %m-% months(1)
    names(countryCoord) <- c("longitude", "latitude", "plantingDate", "harvestDate","startingDate")
    ground <- countryCoord
  }
  #General input path with all the weather data
  general_pathIn <- paste("~/agwise-datasourcing/dataops/datasourcing/Data/useCase_", country, "_", useCaseName,"/", Crop, "/result/geo_4cropModel", sep="")
  #define input path based on the organization of the folders by zone and level2 (usually just by zone)
  if (pathIn_zone == T) {
     if(!is.na(level2) & !is.na(zone)){
       pathIn <- paste(general_pathIn,paste0(zone,'/',level2), sep = "/")
     }else if(is.na(level2) & !is.na(zone)){
       pathIn <- paste(general_pathIn,zone, sep = "/")
     }else if(!is.na(level2) & is.na(zone)){
       print("You need to define first a zone (administrative level 1) to be able to get data for level 2 (administrative level 2) in datasourcing. Process stopped")
       return(NULL)
     }else{
       pathIn <- general_pathIn
     }
  }else{
    pathIn <- general_pathIn
  }
  
  if(AOI == TRUE){
    Rainfall <- readRDS(paste(pathIn, "/Rainfall_Season_", season, "_PointData_AOI.RDS", sep=""))
    Soil <- readRDS(paste(pathIn,"/SoilDEM_PointData_AOI_profile.RDS", sep=""))
    
  }else{
    Rainfall <- readRDS(paste(pathIn, "Rainfall_PointData_trial.RDS", sep=""))
    Soil <- readRDS(paste(pathIn, "SoilDEM_PointData_trial_profile.RDS", sep=""))
  }
  
  names(Soil)[names(Soil)=="lat"] <- "latitude"
  names(Soil)[names(Soil)=="lon"] <- "longitude"
  Soil <- na.omit(Soil)
  #Modify names created for some of the use cases with different column names
  if ("Zone" %in% names(Rainfall)){ names(Rainfall)[names(Rainfall)=="Zone"] <- "NAME_1"}
  if ("lat" %in% names(Rainfall)){ names(Rainfall)[names(Rainfall)=="lat"] <- "latitude"}
  if ("lon" %in% names(Rainfall)){ names(Rainfall)[names(Rainfall)=="lon"] <- "longitude"}
  if(AOI == TRUE){

    metaDataWeather <- as.data.frame(Rainfall[,c("longitude", 'latitude', "startingDate", "endDate", "NAME_1", "NAME_2")])
  }else{
    metaDataWeather <- as.data.frame(Rainfall[,c("longitude", 'latitude', "startingDate", "endDate", "NAME_1", "NAME_2",
                                                 "yearPi","yearHi","pl_j","hv_j")])
  }
  metaData_Soil <- Soil[,c("longitude", "latitude","NAME_1","NAME_2")]
  
  
  metaData <- merge(metaDataWeather,metaData_Soil)
  
  #Currently the number of years are not right for AOI=TRUE because metaData$startingDate is just %m-%d format without any year
  if(AOI==TRUE){
    #number_years <- max(lubridate::year(as.Date(metaData$startingDate, "%Y-%m-%d")))- min(lubridate::year(as.Date(metaData$startingDate, "%Y-%m-%d")))
    #Select just one row to define maximum and minimum date
    Rainfall <- Rainfall[1, ]
    if ("country" %in% names(Rainfall)) {Rainfall<- subset(Rainfall, select = -country)}
    if ("ID" %in% names(Rainfall)) {Rainfall<- subset(Rainfall, select = -ID)}
    Rainfall <- pivot_longer(Rainfall,
                                 cols=-c("longitude", "latitude","NAME_1","NAME_2","startingDate", "endDate"),
                                 names_to = c("Variable", "Date"),
                                 names_sep = "_",
                                 values_to = "RAIN"
                                )
    if(Crop == "Cassava"){
      number_years <- max(lubridate::year(as.Date(Rainfall$Date, "%Y-%m-%d")))- min(lubridate::year(as.Date(Rainfall$Date, "%Y-%m-%d")))-1
    }else{
      number_years <- max(lubridate::year(as.Date(Rainfall$Date, "%Y-%m-%d")))- min(lubridate::year(as.Date(Rainfall$Date, "%Y-%m-%d")))
    }
  }else{
    number_years <- 1
  }
  metaData <- unique(metaData[,c("longitude", "latitude","NAME_1","NAME_2")])
  coords <- merge(metaData,ground)
  if(!is.na(zone)){coords <- coords[coords$NAME_1==zone,]}
  if(!is.na(level2)){coords <- coords[coords$NAME_1==level2,]}
  
  coords <- coords[coords$NAME_1==zone,]
  grid <- as.matrix(coords)
  
  #Set working directory to save the results
  if(AOI == TRUE){
    path.to.extdata <- paste("/home/jovyan/agwise-potentialyield/dataops/potentialyield/Data/useCase_", country, "_",useCaseName, "/", Crop, "/transform/DSSAT/AOI/",varietyid, sep="")
  }else{
    path.to.extdata <- paste("/home/jovyan/agwise-potentialyield/dataops/potentialyield/Data/useCase_", country, "_",useCaseName, "/", Crop, "/transform/DSSAT/fieldData/",varietyid, sep="")
  }
  #Define working directory with template data
  path.to.temdata <- paste("/home/jovyan/agwise-potentialyield/dataops/potentialyield/Data/useCase_", country, "_",useCaseName, "/", Crop, "/Landing/DSSAT", sep="")
  #We need to add more codes
  crops <- c("Maize", "Potato", "Rice", "Soybean", "Wheat","Beans","Cassava")
  cropcode_supported <- c("MZ","PT", "RI", "SB", "WH","BN","CS")
  
  cropid <- which(crops == Crop)
  crop_code <- cropcode_supported[cropid]
  
  # Create a list of indices
  indices <- seq_along(grid[,1])

  # Previous way of simulating but less efficient  
  # results <- map(seq_along(grid[,1]), create_filex, path.to.temdata=path.to.temdata, filex_temp=filex_temp, path.to.extdata=path.to.extdata, 
  #                coords=coords, AOI=AOI, crop_code=crop_code, plantingWindow=plantingWindow, number_years=number_years, varietyid=varietyid, 
  #                zone=zone, level2=level2,fertilizer=fertilizer,geneticfiles= geneticfiles,index_soilwat=index_soilwat) %||% print("Progress:")
  
  setwd(path.to.extdata)
  #create a log file to see the progress
  log_file <- paste(path.to.extdata,"progress_log_exp.txt",sep='/')
  
  if (file.exists(log_file)) {
    file.remove(log_file)
  }
  # Set up parallel processing (for more efficient processing)
  num_cores <- availableCores() -3
  plan(multisession, workers = num_cores)
  results <- future_lapply(indices, function(i) {
    message <- paste("Progress experiment:", i, "out of", length(indices),"zone:",zone)
    cat(message, "\n", file = log_file, append = TRUE)
    #create_filex <- get("create_filex", envir = globalenv())

    create_filex(i, path.to.temdata=path.to.temdata, filex_temp=filex_temp, path.to.extdata=path.to.extdata, 
                 coords=coords, AOI=AOI, crop_code=crop_code, plantingWindow=plantingWindow, number_years=number_years, varietyid=varietyid, 
                 zone=zone, level2=level2,fertilizer=fertilizer,geneticfiles= geneticfiles,index_soilwat=index_soilwat)
    
    message2 <- paste("Finished:", i, "out of", length(indices),"zone:",zone)
    cat(message2, "\n", file = log_file, append = TRUE)

    }, future.globals = TRUE)
  plan(sequential)
  #rm(list = ls())
  gc()
}

