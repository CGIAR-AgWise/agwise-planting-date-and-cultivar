# Create DSSAT experimental file using Remote Sensing data

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
packages_required <- c("tidyverse","lubridate","DSSAT","furrr","future","future.apply","stringr","geodata")
installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
    install.packages(packages_required[!installed_packages])}
invisible(lapply(packages_required, library, character.only = TRUE))


# DOY -> Date (year is arbitrary; DSSAT uses mm-dd derived from these Dates)
doy_to_date <- function(x, year = 2000L) {
  x <- suppressWarnings(as.integer(x))
  as.Date(x - 1L, origin = paste0(year, "-01-01"))
}



# Runs factorial fertilizer for a time period (variety and PDAT looped outside)
populate_dssat_exp_fert_approach1 <- function(file_x, fert_df, ex_profile) {
  fert_df <- fert_df %>%
    mutate(PDATE = gsub("[^0-9]", "", PDAT)) %>%
    filter(lat == ex_profile$LAT & lon == ex_profile$LON)
  
  file_x$CULTIVARS$CNAME <- unique(fert_df$CNAME)
  
  fert_df <- fert_df %>%
    select(-c(CNAME, INGENO))  # Remove non-DSSAT columns
  
  plant_date <- doy_to_date(unique(fert_df$PDATE))
  
  file_x$FIELDS$ID_FIELD <- unique(fert_df$NAME_2)
  file_x$FIELDS$XCRD <- unique(fert_df$lon)
  file_x$FIELDS$YCRD <- unique(fert_df$lat)
  file_x$`PLANTING DETAILS`$PLNAME <- unique(fert_df$PDAT)
  
  fert_df <- fert_df %>%
    select(-c(PDATE, NAME_1, NAME_2, lon, lat, PDAT))
  
  file_x$`PLANTING DETAILS`$PDATE <- as.POSIXct(plant_date)
  file_x$`INITIAL CONDITIONS`$ICDAT <- as.POSIXct(plant_date %m-% months(1))
  file_x$`HARVEST DETAILS`$HDATE <- as.POSIXct(plant_date %m+% months(8))
  file_x$`SIMULATION CONTROLS`$SDATE <- as.POSIXct(plant_date %m-% months(1))
  if (AOI) file_x$`SIMULATION CONTROLS`$NYERS <- number_years

    fert_x <- dplyr::slice(file_x$`FERTILIZERS (INORGANIC)`, 0)
  f_ij <- 0
  for (i in seq_along(plant_date)){
    for (j in 1:max(fert_df$F)){  # Loop through all fertilizer levels
      f_ij <- f_ij + 1
      
      fert_x_ij <- fert_df %>% 
        filter(F == j) %>%
        mutate(FDATE = as.POSIXct(plant_date[i] + F.dap),
               F = f_ij) %>%
        select(-F.dap)
      
      fert_x <- bind_rows(fert_x, fert_x_ij)
    }
  }
  
  file_x$`FERTILIZERS (INORGANIC)` <- fert_x
  
  trt_x_original <- file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`
  trt_x <- dplyr::slice(trt_x_original, 0)
  trt_ij <- 0
  
  for (i in seq_along(plant_date)){
    for (j in 1:max(fert_df$F)){
      trt_ij <- trt_ij + 1
      trt_x_ij <- trt_x_original
      
      Tname <- fert_df %>%
        filter(F == j) %>%
        select(FERNAME) %>%
        mutate(FERNAME = substr(FERNAME, 1, 9))
      
      trt_x_ij <- trt_x_ij %>%
        mutate(
          N = trt_ij,
          TNAME = case_when(
            length(plant_date) == 1 ~ Tname[[1, 1]],
            TRUE ~ paste(Tname[1, ], "@", format(plant_date[i], "%m-%d"),
                         sep = " ")
          ),
          MF = trt_ij,
          across(c(MH, MP, IC, SM), ~ i)
        )
      
      trt_x <- bind_rows(trt_x, trt_x_ij)
    }
  }
  file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` <- trt_x
  
  return(file_x)
}


# Adds fertilizer levels and treatments to DSSAT experimental file
populate_fert_n_trt_factorial <- function(file_x, fert_df, plant_dates, 
                                          file_x_original) {
  
  fert_df <- fert_df %>% 
    select(-c(NAME_1, NAME_2, lon, lat))  # Remove non-DSSAT columns
  
  fert_x <- dplyr::slice(file_x_original$`FERTILIZERS (INORGANIC)`, 0)
  f_ij <- 0
  for (i in seq_along(plant_dates)){
    for (j in 1:max(fert_df$F)){  # Loop through all fertilizer levels
      f_ij <- f_ij + 1

      fert_x_ij <- fert_df %>% 
        filter(F == j) %>%
        mutate(FDATE = as.POSIXct(plant_dates[i] + F.dap),
               F = f_ij) %>%
        select(-F.dap)
      
      fert_x <- bind_rows(fert_x, fert_x_ij)
    }
  }
  
  file_x$`FERTILIZERS (INORGANIC)` <- fert_x
  
  trt_x_original <-  file_x_original$`TREATMENTS                        -------------FACTOR LEVELS------------`
  trt_x <- dplyr::slice(trt_x_original, 0)
  trt_ij <- 0
  for (i in seq_along(plant_dates)){
    for (j in 1:max(fert_df$F)){
      trt_ij <- trt_ij + 1
      trt_x_ij <- trt_x_original
      
      Tname <- fert_df %>%
        filter(F == j) %>%
        select(FERNAME) %>%
        mutate(FERNAME = substr(FERNAME, 1, 9))
      
      trt_x_ij <- trt_x_ij %>%
        mutate(
          N = trt_ij,
          TNAME = paste(Tname[1, ], "@", format(plant_dates[i], "%m-%d"), sep= " "),
          MF = trt_ij,
          across(c(MH, MP, IC, SM), ~ i)
        )
      
      trt_x <- bind_rows(trt_x, trt_x_ij)
    }
  }
  file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` <- trt_x
  
    return(file_x)
  }



#' Create one experimental file (repetitive function)
#' Copy the CUL,ECO and SPE files from the path.to.temdata (template files)
#'
#' @param i point/folder from a list
#' @param path.to.temdata directory with template CUL,weather and soil data in DSSAT format
#' @param filex_temp Name of the template experimental file in DSSAT format (FILEX)
#' @param path.to.extdata working directory to save the weather and soil data in DSSAT format
#' @param coords dataframe with the locations and metadata (created by the function dssat.expfile)
#' @param AOI TRUE for AOI runs; FALSE for trial sites
#' @param crop_code DSSAT crop code (e.g., "MZ")
#' @param plantingWindow number of weeks from base planting date (used only when RS schedule not provided)
#' @param number_years number of years to simulate (AOI only)
#' @param varietyid DSSAT cultivar id (INGENO)
#' @param zone admin level 1 name
#' @param level2 admin level 2 name (optional)
#' @param fertilizer if TRUE, fertilizer at planting
#' @param geneticfiles prefix of CUL/ECO/SPE files to copy (e.g., "MZCER048")
#' @param index_soilwat initial soil water index (0 = WP, 1 = FC)
#' @param wsta_prefix weather station prefix
#' @param plant_dates OPTIONAL Date vector of planting dates (RS-driven). If provided, overrides weekly plantingWindow.
#' @return invisibly, the path to the written FILEX
create_filex <-function(i, path.to.temdata, filex_temp, path.to.extdata, coords,
                        AOI = TRUE, crop_code, plantingWindow = 1, number_years,
                        varietyid, zone, level2 = NA, fertilizer = FALSE, 
                        fert_factorial = FALSE, geneticfiles, index_soilwat = 1,
                        wsta_prefix = "WHTE", fert_df = NULL, 
                        plant_dates = NULL){

  # Working path (each point)
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
  
  # Switch to working path for write/read ops
  setwd(working_path)
  
  file_x <- DSSAT::read_filex(paste(path.to.temdata, filex_temp, sep = '/'))

  # Copy genetic files (from template dir into working path)
  gen_parameters <- list.files(path = path.to.temdata, pattern = geneticfiles, full.names = TRUE)
  file.copy(gen_parameters, working_path, overwrite = TRUE)

  ex_profile <- DSSAT::read_sol("SOIL.SOL", id_soil = paste0(
    'TRAN', formatC(width = 5, as.integer((i)), flag = "0")))
  
  
  # ---- COMMON FILEX edits ----
  file_x$FIELDS$WSTA <- paste0(wsta_prefix, formatC(
    width = 4, as.integer((i)), flag = "0"))
  file_x$FIELDS$ID_SOIL<- paste0('TRAN', formatC(
    width = 5, as.integer((i)), flag = "0"))
  file_x$CULTIVARS$CR <- crop_code
  file_x$CULTIVARS$INGENO <- varietyid
  
  # Common IC soil depth and water
  file_x$`INITIAL CONDITIONS`$ICBL <- ex_profile$SLB
  file_x$`INITIAL CONDITIONS`$SH2O <- mapply(function(sdul, slll, index) {
    slll + ((sdul - slll) * index)
  }, ex_profile$SDUL, ex_profile$SLLL, MoreArgs = list(index = index_soilwat),
  SIMPLIFY = FALSE)
  
  # Select only fertilizer levels for this location
  if (fert_factorial){
    file_x <- populate_dssat_exp_fert_approach1(file_x, fert_df, ex_profile)
    DSSAT::write_filex(file_x, paste0('EXTE', formatC(width = 4, as.integer((i)), flag = "0"),'.', crop_code,'X'))
    return(file.path(working_path, paste0('EXTE', formatC(width = 4, as.integer((i)), flag = "0"),'.',crop_code,'X')))
  }
  
  # ----------------------------------------------------------------------------------------------
  # Branch: RS-provided planting dates (preferred). Otherwise use weekly plantingWindow logic.
  # ----------------------------------------------------------------------------------------------
  if (!is.null(plant_dates) && length(plant_dates) >= 1 && !all(is.na(plant_dates))) {

    plant_dates <- sort(as.Date(plant_dates))
    # base row uses first planting date
    file_x$`PLANTING DETAILS`$PDATE <- as.POSIXct(plant_dates[1])
    file_x$`INITIAL CONDITIONS`$ICDAT <- as.POSIXct(plant_dates[1] %m-% months(1))
    file_x$`HARVEST DETAILS`$HDATE <- as.POSIXct(max(plant_dates) %m+% months(8))
    file_x$`SIMULATION CONTROLS`$SDATE <- as.POSIXct(plant_dates[1] %m-% months(1))
    if (AOI) file_x$`SIMULATION CONTROLS`$NYERS <- number_years

    if (fertilizer & !fert_factorial) {
      file_x$`FERTILIZERS (INORGANIC)`$FDATE <- as.POSIXct(plant_dates[1])
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$TNAME <-
        paste0(file_x$`FERTILIZERS (INORGANIC)`$FERNAME[1], " @ ", format(plant_dates[1], "%m-%d"))
    } else if (fertilizer & fert_factorial) {
      file_x <- populate_fert_n_trt_factorial(
        file_x = file_x, fert_df = fert_df, plant_dates = plant_dates, 
        file_x_original = file_x_original)
    } else {
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$TNAME <-
        paste0("Planting @ ", format(plant_dates[1], "%m-%d"))
    }

    # Add remaining plantings as treatments 2..n
    if (length(plant_dates) > 1) {
      for (j in 2:length(plant_dates)) {
        # INITIAL CONDITIONS
        file_x$`INITIAL CONDITIONS`<- file_x$`INITIAL CONDITIONS` %>% add_row(!!!file_x$`INITIAL CONDITIONS`[file_x$`INITIAL CONDITIONS`$C==1,])
        file_x$`INITIAL CONDITIONS`[j,]$C     <- j
        file_x$`INITIAL CONDITIONS`[j,]$ICDAT <- as.POSIXct(plant_dates[j] %m-% months(1))

        # PLANTING
        file_x$`PLANTING DETAILS` <- file_x$`PLANTING DETAILS` %>% add_row(!!!file_x$`PLANTING DETAILS`[file_x$`PLANTING DETAILS`$P==1,])
        file_x$`PLANTING DETAILS`[j,]$P     <- j
        file_x$`PLANTING DETAILS`[j,]$PDATE <- as.POSIXct(plant_dates[j])

        # FERTILIZER (optional)
        if (isTRUE(fertilizer) & !fert_factorial) {
          file_x$`FERTILIZERS (INORGANIC)` <- file_x$`FERTILIZERS (INORGANIC)` %>% add_row(!!!file_x$`FERTILIZERS (INORGANIC)`[file_x$`FERTILIZERS (INORGANIC)`$F==1,])
          file_x$`FERTILIZERS (INORGANIC)`[j,]$F     <- j
          file_x$`FERTILIZERS (INORGANIC)`[j,]$FDATE <- as.POSIXct(plant_dates[j])
        }

        # HARVEST
        file_x$`HARVEST DETAILS` <- file_x$`HARVEST DETAILS` %>% add_row(!!!file_x$`HARVEST DETAILS`[file_x$`HARVEST DETAILS`$H==1,])
        file_x$`HARVEST DETAILS`[j,]$H     <- j
        file_x$`HARVEST DETAILS`[j,]$HDATE <- as.POSIXct(max(plant_dates) %m+% months(8))

        # SIM CONTROLS
        file_x$`SIMULATION CONTROLS`<- file_x$`SIMULATION CONTROLS` %>% add_row(!!!file_x$`SIMULATION CONTROLS`[file_x$`SIMULATION CONTROLS`$N==1,])
        file_x$`SIMULATION CONTROLS`[j,]$N     <- j
        file_x$`SIMULATION CONTROLS`[j,]$SDATE <- as.POSIXct(plant_dates[j] %m-% months(1))

        # TREATMENTS
        if (!fert_factorial){
        file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` <-
          file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` %>%
          add_row(!!!file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$N==1,])
        file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[j,]$N  <- j
        file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[j,]$IC <- j
        file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[j,]$MP <- j
        file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[j,]$MH <- j
        file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[j,]$SM <- j
        file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[j,]$TNAME <-
          if (isTRUE(fertilizer)) paste0(file_x$`FERTILIZERS (INORGANIC)`$FERNAME[1], " @ ", format(plant_dates[j], "%m-%d"))
        else paste0("Planting_", format(plant_dates[j], "%m-%d"))}
      }
    }

  } else if (!fert_factorial){
    # --------------------------- original weekly window logic ---------------------------
    file_x$`INITIAL CONDITIONS`$ICDAT <- as.POSIXct(coords$startingDate[i])
    file_x$`PLANTING DETAILS`$PDATE   <- as.POSIXct(coords$plantingDate[i])
    file_x$`HARVEST DETAILS`$HDATE    <- as.POSIXct(coords$harvestDate[i])
    file_x$`SIMULATION CONTROLS`$SDATE<- as.POSIXct(coords$startingDate[i])
    if (AOI) file_x$`SIMULATION CONTROLS`$NYERS <- number_years

    if(fertilizer == TRUE & fert_factorial == FALSE){
      file_x$`FERTILIZERS (INORGANIC)`$FDATE <- as.POSIXct(coords$plantingDate[i])
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$TNAME <- paste0(file_x$`FERTILIZERS (INORGANIC)`$FERNAME[1], " Planting 0")
    }else{
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$TNAME <- paste0("Initial planting")
    }

    for (j in 1:plantingWindow){
      file_x$`INITIAL CONDITIONS`<- file_x$`INITIAL CONDITIONS` %>% add_row(!!!file_x$`INITIAL CONDITIONS`[file_x$`INITIAL CONDITIONS`$C==1,])
      file_x$`INITIAL CONDITIONS`[1+j,]$C     <- 1+j
      file_x$`INITIAL CONDITIONS`[1+j,]$ICDAT <- as.POSIXct(coords$startingDate[i]) %m+% weeks(j)

      file_x$`PLANTING DETAILS` <- file_x$`PLANTING DETAILS` %>% add_row(!!!file_x$`PLANTING DETAILS`[file_x$`PLANTING DETAILS`$P==1,])
      file_x$`PLANTING DETAILS`[1+j,]$P     <- 1+j
      file_x$`PLANTING DETAILS`[1+j,]$PDATE <- as.POSIXct(coords$plantingDate[i]) %m+% weeks(j)

      if(fertilizer == TRUE){
        file_x$`FERTILIZERS (INORGANIC)` <- file_x$`FERTILIZERS (INORGANIC)` %>% add_row(!!!file_x$`FERTILIZERS (INORGANIC)`[file_x$`FERTILIZERS (INORGANIC)`$F==1,])
        file_x$`FERTILIZERS (INORGANIC)`[1+j,]$F     <- 1+j
        file_x$`FERTILIZERS (INORGANIC)`[1+j,]$FDATE <- as.POSIXct(coords$plantingDate[i]) %m+% weeks(j)
      }

      file_x$`HARVEST DETAILS` <- file_x$`HARVEST DETAILS` %>% add_row(!!!file_x$`HARVEST DETAILS`[file_x$`HARVEST DETAILS`$H==1,])
      file_x$`HARVEST DETAILS`[1+j,]$H     <- 1+j
      file_x$`HARVEST DETAILS`[1+j,]$HDATE <- as.POSIXct(coords$harvestDate[i]) %m+% weeks(j)

      file_x$`SIMULATION CONTROLS`<- file_x$`SIMULATION CONTROLS` %>% add_row(!!!file_x$`SIMULATION CONTROLS`[file_x$`SIMULATION CONTROLS`$N==1,])
      file_x$`SIMULATION CONTROLS`[1+j,]$N     <- 1+j
      file_x$`SIMULATION CONTROLS`[1+j,]$SDATE <- as.POSIXct(coords$startingDate[i]) %m+% weeks(j)

      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` <- file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` %>%
        add_row(!!!file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`$N==1,])
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$N  <- 1+j
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$IC <- 1+j
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$MP <- 1+j
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$MH <- 1+j
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$SM <- 1+j
      file_x$`TREATMENTS                        -------------FACTOR LEVELS------------`[1+j,]$TNAME <-
        if (isTRUE(fertilizer)) paste0(file_x$`FERTILIZERS (INORGANIC)`$FERNAME[1], " + ", j ,"weeks")
      else paste0("Planting + ", j ,"weeks")
    }
  }

  # Write FILEX
  DSSAT::write_filex(file_x, paste0('EXTE', formatC(width = 4, as.integer((i)), flag = "0"),'.',crop_code,'X'))
  invisible(file.path(working_path, paste0('EXTE', formatC(width = 4, as.integer((i)), flag = "0"),'.',crop_code,'X')))
}

#' Create multiple experimental files
#'
#' @param rs_schedule_df OPTIONAL data.frame with columns:
#'   longitude, latitude, lon_r, lat_r, planting_dates(list of Dates), startingDate(Date), harvestDate(Date)
dssat.expfile <- function(country, useCaseName, Crop, AOI = TRUE, filex_temp,
                          Planting_month_date = NULL, Harvest_month_date = NULL,
                          ID = "TLID", season = 1, plantingWindow = 1,
                          varietyid, zone, level2 = NA, fertilizer = FALSE, 
                          fert_factorial = FALSE, fert_df = NULL, geneticfiles,
                          index_soilwat = 1, pathIn_zone = FALSE, 
                          rs_schedule_df = NULL){

  print(paste("Variety:", varietyid,"Zone:", zone))
  if(AOI == TRUE){
    if(is.null(Planting_month_date) | is.null(Harvest_month_date)){
      print("with AOI=TRUE, Planting_month_date, Harvest_month_date can not be null, please provide mm-dd for both")
      return(NULL)
    }
    countryCoord <- readRDS(paste("/home/jovyan/agwise-datacuration/dataops/datacuration/Data/useCase_", country, "_",useCaseName, "/", Crop, "/result/AOI_GPS.RDS", sep=""))
    countryCoord <- unique(countryCoord[, c("lon", "lat")])
    countryCoord <- countryCoord[complete.cases(countryCoord), ]

    Planting_month <- as.numeric(str_extract(Planting_month_date, "[^-]+"))
    Harvest_month  <- as.numeric(str_extract(Harvest_month_date, "[^-]+"))
    if(Planting_month < Harvest_month){ py <- 2000; hy <- 2000 } else { py <- 2000; hy <- 2001 }

    Planting_month_date <- as.Date(paste0(py, "-", Planting_month_date))
    countryCoord$plantingDate <- Planting_month_date
    Planting_month_date <- Planting_month_date %m-% months(1)

    if(Crop == "Cassava"){
      duration <- as.Date(paste0(hy, "-",Harvest_month_date)) - Planting_month_date
      if (duration < 240) hy <- hy + 1
    }
    Harvest_month_date <- as.Date(paste0(hy, "-",Harvest_month_date))
    countryCoord$harvestDate  <- Harvest_month_date
    if(plantingWindow > 1 & plantingWindow <= 5){
      Harvest_month_date <- Harvest_month_date %m+% months(1)
    }else if(plantingWindow > 5 & plantingWindow <=30){
      Harvest_month_date <- Harvest_month_date %m+% months(2)
    }
    countryCoord$startingDate <- Planting_month_date
    countryCoord$endDate      <- Harvest_month_date

    countryCoord <- countryCoord[complete.cases(countryCoord), ]
    names(countryCoord) <- c("longitude", "latitude","plantingDate","harvestDate","startingDate","endDate")
    ground <- countryCoord
  }else{
    GPS_fieldData <- readRDS(paste("/home/jovyan/agwise-datacuration/dataops/datacuration/Data/useCase_",country, "_",useCaseName, "/", Crop, "/result/compiled_fieldData.RDS", sep=""))
    countryCoord <- unique(GPS_fieldData[, c("lon", "lat", "plantingDate", "harvestDate")])
    countryCoord <- countryCoord[complete.cases(countryCoord), ]
    countryCoord$startingDate <- as.Date(countryCoord$plantingDate, "%Y-%m-%d") %m-% months(1)
    names(countryCoord) <- c("longitude", "latitude", "plantingDate", "harvestDate","startingDate")
    ground <- countryCoord
  }

  # ---- datasourcing paths ----
  general_pathIn <- paste("/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/useCase_", country, "_", useCaseName,"/", Crop, "/result/geo_4cropModel", sep="")
  if (pathIn_zone == TRUE) {
    if(!is.na(level2) & !is.na(zone)){
      pathIn <- paste(general_pathIn,paste0(zone,'/',level2), sep = "/")
    }else if(is.na(level2) & !is.na(zone)){
      pathIn <- paste(general_pathIn,zone, sep = "/")
    }else if(!is.na(level2) & is.na(zone)){
      print("You need to define first a zone (administrative level 1) to be able to get data for level 2 in datasourcing. Process stopped")
      return(NULL)
    }else{
      pathIn <- general_pathIn
    }
  }else{
    pathIn <- general_pathIn
  }

  if(AOI == TRUE){
    Rainfall <- readRDS(paste(pathIn, "/Rainfall_Season_", season, "_PointData_AOI.RDS", sep=""))
    Soil     <- readRDS(paste(pathIn,"/SoilDEM_PointData_AOI_profile.RDS", sep=""))
  }else{
    Rainfall <- readRDS(paste(pathIn, "Rainfall_PointData_trial.RDS", sep=""))
    Soil     <- readRDS(paste(pathIn, "SoilDEM_PointData_trial_profile.RDS", sep=""))
  }

  names(Soil)[names(Soil)=="lat"] <- "latitude"
  names(Soil)[names(Soil)=="lon"] <- "longitude"
  Soil <- na.omit(Soil)

  if ("Zone" %in% names(Rainfall)){ names(Rainfall)[names(Rainfall)=="Zone"] <- "NAME_1"}
  if ("lat"  %in% names(Rainfall)){ names(Rainfall)[names(Rainfall)=="lat"]  <- "latitude"}
  if ("lon"  %in% names(Rainfall)){ names(Rainfall)[names(Rainfall)=="lon"]  <- "longitude"}

  if(AOI == TRUE){
    metaDataWeather <- as.data.frame(Rainfall[,c("longitude", 'latitude', "startingDate", "endDate", "NAME_1", "NAME_2")])
  }else{
    metaDataWeather <- as.data.frame(Rainfall[,c("longitude", 'latitude', "startingDate", "endDate", "NAME_1", "NAME_2",
                                                 "yearPi","yearHi","pl_j","hv_j")])
  }
  metaData_Soil <- Soil[,c("longitude", "latitude","NAME_1","NAME_2")]
  metaData <- merge(metaDataWeather,metaData_Soil)

  # ---- years span (AOI) ----
  if(AOI==TRUE){
    R1 <- Rainfall[1, ]
    if ("country" %in% names(R1)) {R1<- subset(R1, select = -country)}
    if ("ID" %in% names(R1)) {R1<- subset(R1, select = -ID)}
    R1 <- pivot_longer(R1,
                       cols=-c("longitude", "latitude","NAME_1","NAME_2","startingDate", "endDate"),
                       names_to = c("Variable", "Date"),
                       names_sep = "_",
                       values_to = "RAIN")
    number_years <- max(lubridate::year(as.Date(R1$Date, "%Y-%m-%d"))) -
      min(lubridate::year(as.Date(R1$Date, "%Y-%m-%d")))
  }else{
    number_years <- 1
  }

  metaData <- unique(metaData[,c("longitude", "latitude","NAME_1","NAME_2")])
  coords <- merge(metaData,ground)

  if(!is.na(zone)){   coords <- coords[coords$NAME_1==zone,] }
  if(!is.na(level2)){ coords <- coords[coords$NAME_2==level2,] }

  # ----------------------------------------------------------------------
  # Attach RS planting schedule with robust join: rounded lon/lat (3 dp)
  # ----------------------------------------------------------------------
  if (!is.null(rs_schedule_df)) {
    rs_clean <- rs_schedule_df %>%
      {
        nm <- names(.)
        if ("lon" %in% nm) rename(., longitude = lon) else .
      } %>%
      {
        nm <- names(.)
        if ("lat" %in% nm) rename(., latitude  = lat) else .
      } %>%
      mutate(
        longitude = as.numeric(longitude),
        latitude  = as.numeric(latitude),
        lon_r = if ("lon_r" %in% names(.)) lon_r else round(longitude, 3),
        lat_r = if ("lat_r" %in% names(.)) lat_r else round(latitude, 3)
      ) %>%
      select(lon_r, lat_r, planting_dates, startingDate, harvestDate)

    coords <- coords %>%
      mutate(
        longitude = as.numeric(longitude),
        latitude  = as.numeric(latitude),
        lon_r = round(longitude, 3),
        lat_r = round(latitude, 3)
      ) %>%
      dplyr::left_join(rs_clean, by = c("lon_r","lat_r"), suffix = c("", ".rs")) %>%
      mutate(
        startingDate = ifelse(!purrr::map_lgl(planting_dates, ~is.null(.x) || all(is.na(.x))),
                              as.Date(startingDate.rs), as.Date(startingDate)),
        harvestDate  = ifelse(!purrr::map_lgl(planting_dates, ~is.null(.x) || all(is.na(.x))),
                              as.Date(harvestDate.rs),  as.Date(harvestDate))
      )
  } else {
    coords$planting_dates <- replicate(nrow(coords), as.Date(NA), simplify = FALSE)
  }

  grid <- as.matrix(coords)
  if (nrow(coords) == 0) {
    print("No coordinates to process after filtering. Exiting.")
    return(NULL)
  }

  # ---- output dirs & crop codes ----
  if(AOI == TRUE){
    path.to.extdata <- paste("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName, "/", Crop, "/transform/DSSAT/AOI/",varietyid, sep="")
  }else{
    path.to.extdata <- paste("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName, "/", Crop, "/transform/DSSAT/fieldData/",varietyid, sep="")
  }
  if (!dir.exists(path.to.extdata)) dir.create(path.to.extdata, recursive = TRUE)

  path.to.temdata <- paste("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_",useCaseName, "/", Crop, "/Landing/DSSAT", sep="")

  crops <- c("Maize","Potato","Rice","Soybean","Wheat","Beans","Cassava")
  cropcode_supported <- c("MZ","PT","RI","SB","WH","BN","CS")
  cropid <- which(crops == Crop)
  crop_code <- cropcode_supported[cropid]

  # ---- parallel over points ----
  # setwd(path.to.extdata)
  # log_file <- file.path(path.to.extdata,"progress_log_exp.txt")
  # if (file.exists(log_file)) file.remove(log_file)

  num_cores <- max(1, future::availableCores() - 3)
  plan(multisession, workers = num_cores)

  indices <- seq_len(nrow(coords))
  results <- future_lapply(indices, function(i) {
    # cat(paste("Progress experiment:", i, "out of", length(indices), 
    #           "zone:",zone), "\n", file = log_file, append = TRUE)

    out <- create_filex(
      i = i,
      path.to.temdata = path.to.temdata,
      filex_temp = filex_temp,
      path.to.extdata = path.to.extdata,
      coords = coords,
      AOI = AOI,
      crop_code = crop_code,
      plantingWindow = plantingWindow,
      number_years = number_years,
      varietyid = varietyid,
      zone = zone,
      level2 = level2,
      fertilizer = fertilizer,
      fert_factorial = fert_factorial,
      geneticfiles = geneticfiles,
      index_soilwat = index_soilwat,
      fert_df = fert_df,
      plant_dates = coords$planting_dates[[i]]  # <<< RS-driven vector of Dates (4 per coordinate)
    )

    # cat(paste("Finished:", i, "out of", length(indices),"zone:",zone), "\n", file = log_file, append = TRUE)
    # out
  }, future.globals = TRUE)

  plan(sequential)
  gc()

  invisible(results)
}


