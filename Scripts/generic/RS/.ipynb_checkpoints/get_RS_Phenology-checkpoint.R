# Get Phenology (Planting and harvesting dates) derived from MODIS NDVI time series for the Use Case  

# Introduction: 
# This script allows the crop phenology extraction through MODIS NDVI time series. This script has to be run after get_MODISts_PreProc.R. It covers :
# (1) - Shaping of the data 
# (2) - Extracting the peak/max values and date 
# (3) - Extracting the date of the min values on the left part of the curve  
# (4) - Extracting the date of the min values on the right part of the curve
# (5) - Extracting the actual planting date
# (6) - Saving the rasters for actual planting date, harvesting date and length of the cropping season
# (7) - Validating of the results in case of ground data, mapping at pixels and administrative unit levels.

#### Getting started #######

# 1. Sourcing required packages -------------------------------------------
packages_required <- c("plotly", "raster", "rgdal", "gridExtra", "sp", "ggplot2", "caret", "signal", 
                       "timeSeries", "zoo", "pracma", "rasterVis", "RColorBrewer", "dplyr", "terra", 
                       "geodata", "lubridate", "sf", "cowplot", "ggpubr", "tidyterra", "ggspatial")

# check and install packages that are not yet installed
installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
  install.packages(packages_required[!installed_packages])}

# load required packages
suppressWarnings(suppressPackageStartupMessages(invisible(lapply(packages_required, library, character.only = TRUE))))

# 2. Extracting phenology from NDVI time series  -------------------------------------------


Phenology_rasterTS<-function(country, useCaseName, crop, level, admin_unit_name, Planting_year, Harvesting_year, Planting_month, Harvesting_month, emergence, CropMask=T, CropType=F, coord, thr = c(0.10,0.10), validation = T, overwrite = FALSE){
  
  #' @description Function that will allow to obtain the actual planting date and the harvesting date based on VI time series analysis
  #' @param country country name
  #' @param useCaseName use case name  name
  #' @param crop targeted crop with the first letter in uppercase. 
  #' @param level the admin unit level, in integer, to be downloaded -  Starting with 0 for country, then 1 for the first level of subdivision (from 1 to 3). Default is zero
  #' @param admin_unit_name name of the administrative level to be download, default is NULL (when level=0) , else, to be specified as a vector (eg. c("Nandi"))
  #' @param overwrite default is FALSE 
  #' @param Planting_year the planting year in integer
  #' @param Harvesting_year the harvesting year in integer
  #' @param Planting_month the planting month in full name (eg.February)
  #' @param Harvesting_month the harvesting month in full name (eg. September)
  #' @param emergence the average number of days between the planting date and the emergence date
  #' @param CropMask default is TRUE. Does the cropland areas need to be masked?
  #' @param CropType default is FALSE. If CropMask is TRUE, Does the crop type areas need to be masked?
  #' @param coord names of the columns with the lon lat column (ex. c(lon, lat))
  #' @param thr default is c(0.10,0.10) - vector of 2 values c(x,y) between 0 and 1 allowing to determine the point when a fitted curve reaches x% (for planting) or  y% (for harvest) of that year’s maximum amplitude
  #' @param validation default is TRUE - Should a validation be performed (for the case when we have ground data in datacurations)
  
  #' @return raster files of planting date, harvesting date and length of the cropping season at the Use Case level, the results will be written out in /agwise-potentialyield/dataops/potentialyield/Data/useCase/crop/result/RSPlantingDate/
  #'
  #' @examples Phenology_rasterTS(country = "Rwanda", useCaseName = "RAB", crop="Maize", Planting_year = 2021, Harvesting_year = 2022, Planting_month = "September",Harvesting_month = "March", overwrite = TRUE, emergence=5, CropMask=T, CropType=T, coord=c('lon','lat'), thr=c(0.20,0.10), validation=T)

  #' 
  #' 
  ## 2.1. Creating a directory to store the phenology data ####
  pathOut <- paste("/home/jovyan/agwise-potentialyield/dataops/potentialyield/Data/useCase_", country, "_",useCaseName, "/", crop, "/result/RSPlantingDate", sep="")
  
  if (!dir.exists(pathOut)){
    dir.create(file.path(pathOut), recursive = TRUE)
  }
  
  ## 2.2. Read the relevant data ####
  
  ### 2.2.1.  Read the administrative boundary data ####
  # Read the relevant shape file from gdam to be used to crop the global data
  countryShp <- geodata::gadm(country, level, path=pathOut)
  
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
  
  ### 2.2.2. Read the preprocessed RS time series ####
  pathIn <- paste("/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/useCase_", country, "_",useCaseName, "/", "MODISdata/transform/NDVI", sep="")
  fileIn_name <- paste0(country,'_', useCaseName, '_MODIS_NDVI_', Planting_year,'_', Harvesting_year, '_SG.tif')
  listRaster_SG <- list.files(path=pathIn, pattern=glob2rx(fileIn_name), full.names = T)
  stacked_SG <- terra::rast(listRaster_SG) #stack
  
  ### 2.2.3. Read the ground data ##
  if (validation == TRUE) {
    pathInG <- paste("/home/jovyan/agwise-datacuration/dataops/datacuration/Data/useCase_", country, "_",useCaseName, "/", crop, "/raw/", sep="")
    listGroundData <- list.files(path=pathInG, pattern = "data4RS.RDS", full.names = T)
    
    # Check which type of separator before to open the data
    #L <- readLines(listGroundData, n=1)
    #groundData <- if (grepl(";", L)) read.csv2(listGroundData) else read.csv(listGroundData)
    
    groundData <- readRDS(listGroundData)
  }

  ## 2.3. Prepare the preprocessed RS time series ####
  
  ### 2.3.1. Subset the cropping season +/- 15 days ####
  # Start of the season
  start <- paste0("01-",Planting_month,"-", Planting_year)
  start <- as.Date(as.character(start), format ="%d-%B-%Y")
  startj <- as.POSIXlt(start)$yday # conversion in julian day
  
  # Test the number of days in a month
  if (Harvesting_month %in% c('January','March','May','July','August','October','December')){
    nday = "31-"
  }
  
  if (Harvesting_month %in% c('April','June','September','November')){
    nday = "30-"
  }
  if (Harvesting_month %in% c('February')){
    nday = "28-"
  }
  
  # End of the season
  end <- paste0(nday,Harvesting_month,"-", Harvesting_year)
  end <- as.Date(as.character(end), format ="%d-%B-%Y")
  endj <- as.POSIXlt(end)$yday # conversion in julian day
  
  # Create a sequence between start and end of the season +/- 15 days
  # Case Planting Year = Harvesting Year
  if (Planting_year == Harvesting_year){
    seq<- seq(startj-15, endj+15,by=1)
    seq= paste0(Planting_year,"_", formatC(seq, width=3, flag="0"))
  }
  
  # Case Planting Year < Harvesting Year
  if (Planting_year < Harvesting_year){
    seq1<- seq(startj-15, 365,by=1)
    seq1 <- paste0(Planting_year, "_", formatC(seq1, width=3, flag="0"))
    seq2 <- seq(1, endj+15,by=1)
    seq2 <- paste0(Harvesting_year, "_", formatC(seq2, width=3, flag="0"))
    seq= c(seq1, seq2)
  }
  
  # Case Planting Year > Harvesting Year
  if (Planting_year > Harvesting_year){
    stop( "Planting_year can't be > to Harvesting_year")
  }
  
  # Subset the data between planting and harvesting date
  stacked_SG_s <- stacked_SG[[grep(paste(seq, collapse = "|"), names(stacked_SG))]]
  rm(stacked_SG)
  
  ### 2.3.2. Apply the crop type or crop mask ####
  
  # Case no crop mask application
  if (CropMask == FALSE){
    stacked_SG_s <- stacked_SG_s
  } else {
    
    # Case crop mask masking but no crop type
    if (CropMask == TRUE & CropType == FALSE){
      
      ## Get the cropland mask and resample to NDVI
      cropmask <- list.files(paste0("/home/jovyan/agwise-datasourcing/dataops/datasourcing/Data/useCase_", country, "_",useCaseName, "/","MODISdata/raw/CropMask"), pattern=".tif$", full.names=T)
      cropmask <- terra::rast(cropmask)
      cropmask <- terra::mask(cropmask, countryShp)
      ## reclassification 1 = crop, na = non crop
      m1 <- cbind(c(40), 1)
      cropmask <- terra::classify(cropmask, m1, others=NA)
      cropmask <- terra::resample(cropmask, stacked_SG_s)
      
      stacked_SG_s <- stacked_SG_s*cropmask
    } else {
      
      # Case crop type masking
      if (CropMask == TRUE & CropType == TRUE){
        
        ## Get the crop type mask
        Crop_pathIn <- paste0("/home/jovyan/agwise-potentialyield/dataops/potentialyield/Data/useCase_", country, "_",useCaseName, "/", crop, "/result/CropType")
        CropfileIn_name <- paste0('useCase_',country,'_', useCaseName, '_',Planting_year,'_', Planting_month,'_', Harvesting_year, '_', Harvesting_month,'_', crop, '_Ensemble_Prediction.tiff')
        cropmask <- list.files(path=Crop_pathIn, pattern=glob2rx(CropfileIn_name), full.names=T)
        cropmask <- terra::rast(cropmask)
        cropmask <- terra::mask(cropmask, countryShp)
        ## reclassification 1 = crop, na = other crop
        # Check alphabetical order
        if (crop < 'Other'){
        cat <- terra::catalyze(cropmask)
        cat[cat==2] <- NA #NA for other crops
        cropmask <- cat
        } else {
          if (crop > 'Other'){
            cat <- terra::catalyze(cropmask)
            cat[cat==1] <- NA #NA for other crops
            cat[cat==2] <- 1
            cropmask <- cat
          }
        }
        stacked_SG_s <- stacked_SG_s*cropmask 

      }
    }
  }
  
  ### 2.3.3. Shape the ground data base ####
   if(validation == TRUE) {
     # Subset the data between planting year and harvesting year
     groundData.s <- subset(groundData, year(groundData$planting_date)== Planting_year & year(groundData$harvest_date) == Harvesting_year)
     groundData.s <- groundData.s[, c(coord, 'planting_date','harvest_date')]
     groundData.s$ID <- seq(1,nrow(groundData.s)) #For subsequent sub-setting
     groundData.s <- na.omit(groundData.s)
     
     ## Check if the data fall within the crop domain
     # Convert data frame to sf object
     my.sf.point <- st_as_sf(x = groundData.s, 
                             coords = coord,
                             crs = "+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0")
     # Check for intersection between raster and crop points
     groundData.s.extract <- terra::extract(stacked_SG_s, my.sf.point)
     groundData.s.extract <- na.omit(groundData.s.extract)
     groundData.s <- subset(groundData.s, groundData.s$ID %in% groundData.s.extract$ID)
     # Convert data frame to sf object
     my.sf.point <- st_as_sf(x = groundData.s, 
                             coords = coord,
                             crs = "+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0")
   }


  ## 2.4. Extraction of date with Peak/Max VI values ####
  
  # Defining the names of the layer in julian day
  initial_names <-names(stacked_SG_s)
  calendar_dates <- as.integer(substr(initial_names, nchar(initial_names) - 3 + 1, nchar(initial_names))) # extract the last 3 characters corresponding to "ddd"
  max_pheno_julian <- setNames(calendar_dates, initial_names)
  
  ##  Choose those images in cropping season between Planting_Month and Harvesting_Month which can represent the date range when the VI is maximum
  ##  This will create a raster having values of Julian days for every pixel where VI is maximum
  
  ## Pixels having maximum VI values
  peakmx.max <- terra::app(stacked_SG_s, fun=max)
  # plot(peakmx.max, main ="Pixels having maximum values")
  
  # CHECK HOW WROTE THIS #
  #max.pheno <- terra::which.max(stacked_SG_s)
  #max.pheno <- classify(max.pheno, cbind(1:nlyr(stacked_SG_s, max_pheno_julian)))  

  ## Create an empty raster to include the Julian days info against its respective calendar date when the pixels have maximum values in the cropping season 
  max.pheno <- peakmx.max
  terra::values(max.pheno) <- NA
  
  ## To make map of Julian day of "max.pheno" layer; when crop reaches its peak VI
  # keeping range of those calendar dates in the cropping season where crop NDVI values can be maximum
  # Loop to assign the julian date of peak VI values
  for (i in initial_names) {
    max.pheno[stacked_SG_s[[i]] == peakmx.max] <- max_pheno_julian[i]
  }

  ## Median peak values over the area
  median.max <- median(terra::values(max.pheno), na.rm = TRUE)
                        
  ## 2.5. Extraction of date with Min VI values left ####
  # We are looking at the TS comprise between the start of the season and the mean peak date values over the area
  # Subset the data between planting and median peak of the season date
  
  # Case Planting Year = Harvesting Year
  if (Planting_year == Harvesting_year){
    seq.left <- seq(startj-15, median.max,by=1)
    seq.left <- paste0(Planting_year,"_", formatC(seq.left, width=3, flag="0"))
  }

  # Case Planting Year < Harvesting Year
  if (Planting_year < Harvesting_year){
    # Case median date is on same year that planting year
    if (median.max <= 365 & median.max > startj){
      seq.left <- seq(startj-15, median.max,by=1)
      seq.left <- paste0(Planting_year,"_", formatC(seq.left, width=3, flag="0"))
    }
    
    # Case median date is on same year that harvesting year
    if (median.max >= 1 & median.max < endj){
      seq.left1 <- seq(startj-15, 365,by=1)
      seq.left1 <- paste0(Planting_year,"_", formatC(seq.left1, width=3, flag="0"))
      seq.left2 <- seq(1, median.max,by=1)
      seq.left2 <- paste0(Harvesting_year,"_", formatC(seq.left2, width=3, flag="0"))
      seq.left <- c(seq.left1, seq.left2)
    }
  }
 
  stacked_SG_left <- stacked_SG_s[[grep(paste(seq.left, collapse = "|"), names(stacked_SG_s))]]
  
  # Defining the names of the layer in julian day
  initial_names_left <-names(stacked_SG_left)
  calendar_dates_left <- as.integer(substr(initial_names_left, nchar(initial_names_left) - 3 + 1, nchar(initial_names_left))) # extract the last 3 characters corresponding to "ddd"
  min_pheno_julian_left <- setNames(calendar_dates_left, initial_names_left)
  
  ## Pixels having minimum VI values in the left part of the curve
  low.min.left <- terra::app(stacked_SG_left, fun=min, na.rm=TRUE)
  
  ## Create an empty raster to include the Julian days info against its respective calendar date when the pixels have maximum values in the cropping season 
  min.pheno.left <- low.min.left
  terra::values(min.pheno.left) <- NA
  
  ## To make map of Julian day of "min.pheno" layer; when crop reaches its min VI
  # keeping range of those calendar dates in the cropping season where crop VI values can be min
  # Loop to assign the julian date of min VI values
  for (i in initial_names_left) {
    min.pheno.left[stacked_SG_left[[i]] == low.min.left] <- min_pheno_julian_left[i]
  }
  
  ## 2.6. Extraction of date with Min VI values right ####
  # We are looking at the TS comprise between the median peak of the season and the end of the season
  # Subset the data between median peak of the season date and end of the season
  
  # Case Planting Year = Harvesting Year
  if (Planting_year == Harvesting_year){
    seq.right <- seq(median.max,endj+15, by=1)
    seq.right <- paste0(Planting_year,"_", formatC(seq.right, width=3, flag="0"))
  }
  
  # Case Planting Year < Harvesting Year
  if (Planting_year < Harvesting_year){
    # Case median date is on same year that planting year
    if (median.max <= 365 & median.max > startj){
      seq.right1 <- seq(median.max, 365, by=1)
      seq.right1 <- paste0(Planting_year,"_", formatC(seq.right1, width=3, flag="0"))
      seq.right2 <- seq(1, endj+15, by=1)
      seq.right2 <- paste0(Harvesting_year,"_", formatC(seq.right2, width=3, flag="0"))
      seq.right <- c(seq.right1, seq.right2)
    }
    
    # Case median date is on same year that harvesting year
    if (median.max >= 1 & median.max < endj){
      seq.right <- seq(median.max, endj+15,by=1)
      seq.right <- paste0(Harvesting_year,"_", formatC(seq.right, width=3, flag="0"))
    }
  }
  
  stacked_SG_right <- stacked_SG_s[[grep(paste(seq.right, collapse = "|"), names(stacked_SG_s))]]
  
  # Defining the names of the layer in julian day
  initial_names_right <-names(stacked_SG_right)
  calendar_dates_right <- as.integer(substr(initial_names_right, nchar(initial_names_right) - 3 + 1, nchar(initial_names_right))) # extract the last 3 characters corresponding to "ddd"
  min_pheno_julian_right <- setNames(calendar_dates_right, initial_names_right)
  
  ## Pixels having minimum VI values in the right part of the curve
  low.min.right <- terra::app(stacked_SG_right, fun=min, na.rm=TRUE)
  
  ## Create an empty raster to include the Julian days info against its respective calendar date when the pixels have minimum values in the cropping season 
  min.pheno.right <- low.min.right
  terra::values(min.pheno.right) <- NA
  
  ## To make map of Julian day of "min.pheno" layer; when crop reaches its min VI
  # keeping range of those calendar dates in the cropping season where crop VI values can be min
  # Loop to assign the julian date of min VI values
  for (i in initial_names_right) {
    min.pheno.right[stacked_SG_right[[i]] == low.min.right] <- min_pheno_julian_right[i]
  }
  
  ## 2.7. Amplitude calculation between base level and max/peak ####
  ## TIMESAT : https://web.nateko.lu.se/timesat/docs/TIMESAT33_SoftwareManual.pdf # amplitude is computed as the difference between the base level (mean on min left and min right) and peak value of the season.
  ## Lobell et al (2013): http://dx.doi.org/10.1016/j.agsy.2012.09.003 #mentioned green-up in this study is defined as the point when a fitted curve reaches 10% of that year’s maximum amplitude.
  
  ## Calculate the base level
  basel <- c(low.min.left, low.min.right)
  basel <- terra::app(basel, fun='mean')
  ## Calculate Amplitude
  amplit <- (peakmx.max-basel)
  ## Max minus Amplitude
  #max_amplit <- peakmx.max-amplit
  ## x percent of max amplitude (left)
  amplit10pcl <- amplit*thr[1]
  ## y percent of max amplitude (right)
  amplit10pcr <- amplit*thr[2]
  
  ### 2.7.1. Left side : find the date for 10% values : Green up ####
  
  ## left side : add minimum to it to generate a range between minimum left and x% of amplitude in which the green up dates will fall
  min_amplit10pc_left <- low.min.left + amplit10pcl
  
  ##create an empty raster that matches the extent of the other rasters, this will have all the reclassified values
  pd.pct10max.left <-min_amplit10pc_left
  terra::values(pd.pct10max.left) <- NA
  
  ## conditions to find Julian days from amplitude and minimum VI data
  # when a fitted curve reaches x% of that year’s maximum amplitude
  ## Kept reasonable "green up Julian date" range where most of the planting happens in ascending limb of the growth curve
  ## LOGIC: If pixels from Sep06 image are in range between minimum and 10% of amplitude as that Julian day then assign the pixel that Julian day (249) ####
  ## loop
  for (i in initial_names_left) {
    pd.pct10max.left[stacked_SG_left[[i]] <= min_amplit10pc_left & stacked_SG_left[[i]] > low.min.left] <- min_pheno_julian_left[i]
  }
  
  ### 2.7.2. Right side : find the date for 10% values : Scenescence ####
  ## right side : add minimum to it to generate a range between minimum right and y% of amplitude in which the senescence dates will fall
  min_amplit10pc_right <- low.min.right + amplit10pcr
  
  ##create an empty raster that matches the extent of the other rasters, this will have all the reclassified values
  pd.pct10max.right <-min_amplit10pc_right
  terra::values(pd.pct10max.right) <- NA
  
  ## conditions to find Julian days from amplitude and minimum VI data
  # when a fitted curve reaches y% of that year’s maximum amplitude
  ## Kept reasonable "green up Julian date" range where most of the planting happens in ascending limb of the growth curve
  ## LOGIC: If pixels from Sep06 image are in range between minimum and 10% of amplitude as that Julian day then assign the pixel that Julian day (249) ####
  ## loop
  for (i in initial_names_right) {
    pd.pct10max.right[stacked_SG_right[[i]] <= min_amplit10pc_right & stacked_SG_right[[i]] > low.min.right] <- min_pheno_julian_right[i]
  }
  
  ## 2.8. Actual planting dates ####
  ## Singh et al (2019): https://doi.org/10.1038/s41893-019-0304-4 pixel achieved 10% of maximum VI on the ascending limb of the growth curve; actual ##transplanting is likely to be 2–3 weeks (~21days) before the green up estimates for rice.
  
  ## Remove the average number of day from planting to the emergence
  pd.pct10max.left21D <- pd.pct10max.left-emergence 
  
  ## Detect outliers and replace by median values
  mn <- terra::global(pd.pct10max.left21D, mean, na.rm=TRUE)
  sdv <- terra::global(pd.pct10max.left21D, sd, na.rm=TRUE) * 1.5
  med <- mn
  lower <- mn-sdv
  upper <- mn+sdv
  
  x <- ifel(pd.pct10max.left21D < lower[1,1], med[1,1], ifel(pd.pct10max.left21D > upper[1,1], med[1,1] , pd.pct10max.left21D))
  pd.pct10max.left21D <- x

  ## Saving the raster of actual planting date
  filename <- paste0(country,'_', useCaseName,'_',crop,'_MODIS_NDVI_', Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month, '_ActualPlantingDate.tif')
  terra::writeRaster(pd.pct10max.left21D, paste(pathOut, filename, sep="/"), filetype="GTiff", overwrite=overwrite)
  
  ## 2.9. Actual Harvesting dates ####
  
  ## Detect outliers and replace by median values
  mn <- terra::global(pd.pct10max.right, mean, na.rm=TRUE)
  sdv <- terra::global(pd.pct10max.right, sd, na.rm=TRUE) * 1.5
  med <- mn
  lower <- mn-sdv
  upper <- mn+sdv
  
  x <- ifel(pd.pct10max.right < lower[1,1], med[1,1], ifel(pd.pct10max.right > upper[1,1], med[1,1] , pd.pct10max.right))
  pd.pct10max.right <- x
 
  ## Saving the raster of actual planting date
  filename <- paste0(country,'_', useCaseName,'_',crop,'_MODIS_NDVI_', Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month, '_ActualHarvestingDate.tif')
  terra::writeRaster(pd.pct10max.right, paste(pathOut, filename, sep="/"), filetype="GTiff", overwrite=overwrite)
  
  ## 2.10. Actual Length of the Season ####
  length.cs <- pd.pct10max.right-pd.pct10max.left21D
  # Case Planting year < Harvesting year (when in DOY planting date > harvest date)
  x <- ifel(length.cs < 0, (365-pd.pct10max.left21D)+pd.pct10max.right, length.cs)
  
  ## Detect outliers and replace by median values
  mn <- terra::global(x, mean, na.rm=TRUE)
  sdv <- terra::global(x, sd, na.rm=TRUE) * 1.5
  med <- mn
  lower <- mn-sdv
  upper <- mn+sdv
  
  x <- ifel(x < lower[1,1], med[1,1], ifel(x > upper[1,1], med[1,1] , x))
  length.cs <- x
  
  ## Saving the raster of actual length of the cropping season
  filename <- paste0(country,'_', useCaseName,'_',crop,'_MODIS_NDVI_', Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month, '_ActualLength.tif')
  terra::writeRaster(length.cs, paste(pathOut, filename, sep="/"), filetype="GTiff", overwrite=overwrite)
  
  ## 2.11. Validation, Categorization and Mapping ####

  if (validation == TRUE){
    ### 2.11.1. Validation : Comparison of distributions ####
    
    ## Convert the Observed Planting/Harvesting Date in DOY
    my.sf.point$planting_DOY <- as.POSIXlt(my.sf.point$planting_date )$yday
    my.sf.point$harvest_DOY <- as.POSIXlt(my.sf.point$harvest_date )$yday
    
    ## Extract the Estimated Planting/Harvesting Date for my.sf.point
    my.sf.point$planting_RS <- terra::extract(pd.pct10max.left21D,my.sf.point)
    my.sf.point$harvest_RS <- terra::extract(pd.pct10max.right,my.sf.point)
    
    ## Remove the outliers the Estimated Planting/Harvesting Date for my.sf.point
    
    # Planting #
    quartilep <- quantile(my.sf.point$planting_RS$min, probs=c(.25, .75), na.rm = TRUE)
    IQRp <- IQR(my.sf.point$planting_RS$min, na.rm=TRUE)
    
    Lowerp <- quartilep[1] - 1.5*IQRp
    Upperp <- quartilep[2] + 1.5*IQRp 
    
    my.sf.point <- subset(my.sf.point, my.sf.point$planting_RS$min > Lowerp & my.sf.point$planting_RS$min < Upperp)
    
    # Harvest #
    quartileh <- quantile(my.sf.point$harvest_RS$min, probs=c(.25, .75), na.rm = TRUE)
    IQRh <- IQR(my.sf.point$harvest_RS$min, na.rm=TRUE)
    
    Lowerh <- quartileh[1] - 1.5*IQRh
    Upperh <- quartileh[2] + 1.5*IQRh 
    
    my.sf.point <- subset(my.sf.point, my.sf.point$harvest_RS$min > Lowerh & my.sf.point$harvest_RS$min < Upperh)
    
    ## Basic statistics
    ### Planting ###
    # Observed Planting 
    sum.pobs <- as.data.frame(quantile(my.sf.point$planting_DOY, na.rm=T))
    colnames(sum.pobs) <- 'stat_OBS'
    sum.pobs["SD",1] <- round(sd(my.sf.point$planting_DOY, na.rm=T))
    
    # Estimated Planting 
    sum.pest <- as.data.frame(quantile(my.sf.point$planting_RS$min, na.rm=T))
    colnames(sum.pest) <- 'stat_EST'
    sum.pest["SD",1] <- round(sd(my.sf.point$planting_RS$min, na.rm=T))
    
    # Final Planting 
    sum.p <- cbind.data.frame(sum.pobs, sum.pest)
    
    # Mean (diff) planting 
    diff.p <- round(mean(my.sf.point$planting_DOY-my.sf.point$planting_RS$min, na.rm=T))
    
    # Table planting 
    t1 <-  ggtexttable(sum.p, theme = ttheme("blank")) %>%
      tab_add_hline(at.row = 1:2, row.side = "top", linewidth = 2) %>%
      tab_add_title(text = paste0("Average difference \nplanting date:",diff.p,' days'), face = "bold", padding = unit(0.1, "line"))
    
    ### Harvest ###
    # Observed Harvest
    sum.hobs <- as.data.frame(quantile(my.sf.point$harvest_DOY, na.rm=T))
    colnames(sum.hobs) <- 'stat_OBS'
    sum.hobs["SD",1] <- round(sd(my.sf.point$harvest_DOY, na.rm=T))
    
    # Estimated Harvest
    sum.hest <- as.data.frame(quantile(my.sf.point$harvest_RS$min, na.rm=T))
    colnames(sum.hest) <- 'stat_EST'
    sum.hest["SD",1] <- round(sd(my.sf.point$harvest_RS$min, na.rm=T))
    
    # Final Harvest
    sum.h <- cbind.data.frame(sum.hobs, sum.hest)
    
    # Mean (diff) harvest
    diff.h <- round(mean(my.sf.point$harvest_DOY-my.sf.point$harvest_RS$min, na.rm=T))
    
    # Table harvest
    t2 <-  ggtexttable(sum.h, theme = ttheme("blank")) %>%
      tab_add_hline(at.row = 1:2, row.side = "top", linewidth = 2) %>%
      tab_add_title(text = paste0("Average difference \nharvest date:",diff.h,' days'), face = "bold", padding = unit(0.1, "line"))
    
    ## Plot of the comparisons
    df.comp <- cbind.data.frame(my.sf.point$planting_DOY,
                                my.sf.point$planting_RS$min,
                                my.sf.point$harvest_DOY,
                                my.sf.point$harvest_RS$min)
    
    df.comp$planting_DIFF <- df.comp$`my.sf.point$planting_DOY`-df.comp$`my.sf.point$planting_RS$min`
    df.comp$harvest_DIFF <- df.comp$`my.sf.point$harvest_DOY`- df.comp$`my.sf.point$harvest_RS$min`
    colnames(df.comp) <- c("planting_OBS", "planting_EST", "harvest_OBS", "harvest_EST", "planting_DIFF","harvest_DIFF")
    
    #### Planting ###
    p1 <- ggplot(data=df.comp, aes(x=planting_OBS, y=planting_DIFF, fill=planting_OBS, color=planting_OBS)) +
      geom_point(alpha=0.5, size=3) + geom_smooth(method='lm', se=F, color="black")+
      theme_bw()+ scale_fill_viridis_c(name="Observed\nplanting dates")+ scale_color_viridis_c(name="Observed\nplanting dates")+
      xlab("Observed planting dates")+ ylab("Observed - Estimated\nplanting dates") + ggtitle(label=paste0("Planting dates in DOY for ",crop))
    
    #### Harvest ###
    p2 <- ggplot(data=df.comp, aes(x=harvest_OBS, y=harvest_DIFF, fill=harvest_OBS, color=harvest_OBS)) +
      geom_point(alpha=0.5, size=3) + geom_smooth(method='lm', se=F, color="black")+
      theme_bw()+ scale_fill_viridis_c(name="Observed\nharvest dates")+ scale_color_viridis_c(name="Observed\nharvest dates")+
      xlab("Observed harvest dates")+ ylab("Observed - Estimated\nharvest dates") + ggtitle(label=paste0("Harvest dates in DOY for ",crop))
    
    # Assemble plots
    p <- plot_grid(p1, t1, p2, t2, nrow=2, ncol=2)
    
    ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Validation_DOY.pdf"), plot=p, dpi=300, width = 7, height=5, units=c("in"))
    ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Validation_DOY.png"), plot=p, dpi=300, width = 7, height=5, units=c("in"))
    
    ### 2.11.2. Validation : Comparison of categories ####
    
    ### Planting ###
    ## Categorizing the planting dates based on the observed data
    # Calculate the quantiles (0.33, 0.66, 1) - early / mid / late
    quantiles <- quantile(df.comp$planting_OBS, probs = c(0.33, 0.66, 1), na.rm = TRUE)
    
    # Reclassify the df based on quantiles (1=Early, 2=Mid, 3=Late)
    df.comp$planting_OBS_C <- ifelse(df.comp$planting_OBS < quantiles[1], "1",
                                    ifelse(df.comp$planting_OBS >= quantiles[1] & df.comp$planting_OBS < quantiles[2],"2",
                                    "3"))
    df.comp$planting_EST_C <- ifelse(df.comp$planting_EST < quantiles[1], "1",
                                     ifelse(df.comp$planting_EST >= quantiles[1] & df.comp$planting_EST < quantiles[2],"2",
                                            "3"))
    
    # Plot confusion Matrix
    cm <- confusionMatrix(factor(df.comp$planting_EST_C), factor(df.comp$planting_OBS_C), dnn = c("Estimated", "Observed"))
    
    plt <- as.data.frame(cm$table)
    plt$Estimated <- factor(plt$Estimated, levels=rev(levels(plt$Estimated)))
    
    m1 <- ggplot(plt, aes(Observed,Estimated, fill= Freq)) +
      geom_tile() + geom_text(aes(label=Freq)) +
      scale_fill_viridis_c(name="Frenquency", option="cividis") + theme_bw()+
      labs(x = "Observed",y = "Estimated") +
      scale_x_discrete(labels=c("Early","Mid","Late")) +
      scale_y_discrete(labels=c("Late", "Mid", "Early"))+
      ggtitle(label=paste0("Planting dates categories\ncomparisons for ",crop))
    
    ### Harvest ###
    ## Categorizing the harvest dates based on the observed data 
    # Calculate the quantiles (0.33, 0.66, 1) - early / mid / late
    quantiles <- quantile(df.comp$harvest_OBS, probs = c(0.33, 0.66, 1), na.rm = TRUE)
    
    # Reclassify the df based on quantiles (1=Early, 2=Mid, 3=Late)
    df.comp$harvest_OBS_C <- ifelse(df.comp$harvest_OBS < quantiles[1], "1",
                                     ifelse(df.comp$harvest_OBS >= quantiles[1] & df.comp$harvest_OBS < quantiles[2],"2",
                                            "3"))
    df.comp$harvest_EST_C <- ifelse(df.comp$harvest_EST < quantiles[1], "1",
                                     ifelse(df.comp$harvest_EST >= quantiles[1] & df.comp$harvest_EST < quantiles[2],"2",
                                            "3"))
    
    # Plot confusion Matrix
    cm <- confusionMatrix(factor(df.comp$harvest_EST_C), factor(df.comp$harvest_OBS_C), dnn = c("Estimated", "Observed"))
    
    plt <- as.data.frame(cm$table)
    plt$Estimated <- factor(plt$Estimated, levels=rev(levels(plt$Estimated)))
    
    m2 <- ggplot(plt, aes(Observed,Estimated, fill= Freq)) +
      geom_tile() + geom_text(aes(label=Freq)) +
      scale_fill_viridis_c(name="Frenquency", option="cividis") + theme_bw()+
      labs(x = "Observed",y = "Estimated") +
      scale_x_discrete(labels=c("Early","Mid","Late")) +
      scale_y_discrete(labels=c("Late", "Mid", "Early"))+
      ggtitle(label=paste0("Harvest dates categories\ncomparisons for ",crop))
    
    ### Length ###
    ## Categorizing the length of the cropping season based on the observed data
    # Calculate the length of the cropping season
    df.comp$length_OBS <- df.comp$harvest_OBS-df.comp$planting_OBS
    df.comp$length_EST <- df.comp$harvest_EST-df.comp$planting_EST
    
    # Case Planting year < Harvesting year (when in DOY planting date > harvest date)
    df.comp$length_OBS <- ifelse(df.comp$length_OBS<0, (365-df.comp$planting_OBS)+df.comp$harvest_OBS, df.comp$length_OBS)
    df.comp$length_EST <- ifelse(df.comp$length_EST<0, (365-df.comp$planting_EST)+df.comp$harvest_EST, df.comp$length_EST)
    
    # Calculate the quantiles (0.33, 0.66, 1) - early / mid / late
    quantiles <- quantile(df.comp$length_OBS, probs = c(0.33, 0.66, 1), na.rm = TRUE)
    
    # Reclassify the df based on quantiles (1=Short, 2=Mid, 3=Long)
    df.comp$length_OBS_C <- ifelse(df.comp$length_OBS < quantiles[1], "1",
                                    ifelse(df.comp$length_OBS >= quantiles[1] & df.comp$length_OBS < quantiles[2],"2",
                                           "3"))
    df.comp$length_EST_C <- ifelse(df.comp$length_EST < quantiles[1], "1",
                                    ifelse(df.comp$length_EST >= quantiles[1] & df.comp$length_EST < quantiles[2],"2",
                                           "3"))
    
    # Plot confusion Matrix
    cm <- confusionMatrix(factor(df.comp$length_EST_C), factor(df.comp$length_OBS_C), dnn = c("Estimated", "Observed"))
    
    plt <- as.data.frame(cm$table)
    plt$Estimated <- factor(plt$Estimated, levels=rev(levels(plt$Estimated)))
    
    m3 <- ggplot(plt, aes(Observed,Estimated, fill= Freq)) +
      geom_tile() + geom_text(aes(label=Freq)) +
      scale_fill_viridis_c(name="Frenquency", option="cividis") + theme_bw()+
      labs(x = "Observed",y = "Estimated") +
      scale_x_discrete(labels=c("Short","Mid","Long")) +
      scale_y_discrete(labels=c("Long", "Mid", "Short"))+
      ggtitle(label=paste0("Length of cropping season categories\ncomparisons for ",crop))
 
    # Assemble confusion matrix
    m <- plot_grid(m1, m2, m3, nrow=2, ncol=2)
    
    ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Validation_CAT.pdf"), plot=m, dpi=300, width = 7, height=5, units=c("in"))
    ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Validation_CAT.png"), plot=m, dpi=300, width = 7, height=5, units=c("in"))
    
  # End validation  
  }
  
  ### 2.11.3. Mapping ####
  
  ### Pixel levels ###
  
  ## DOY
  country_sf <- sf::st_as_sf(countryShp)
  
  # Planting #
  planting.p <-  ggplot() +
    geom_spatraster(data = pd.pct10max.left21D, aes(fill=min), na.rm=TRUE) +
    theme_bw()+ scale_fill_viridis_b(na.value='transparent', name="DOY", n.breaks=5)+
    theme(legend.position = "bottom")+ 
    geom_sf(data=country_sf, fill=NA, color="black", linewidth=0.5)+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," planting dates"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Harvest #
  harvest.p <-  ggplot() +
    geom_spatraster(data = pd.pct10max.right, aes(fill=min), na.rm=TRUE) +
    theme_bw()+ scale_fill_viridis_b(na.value='transparent', name="DOY", n.breaks=5)+
    theme(legend.position = "bottom")+ 
    geom_sf(data=country_sf, fill=NA, color="black", linewidth=0.5)+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," harvest dates"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Length of the cropping season #
  length.p <-  ggplot() +
    geom_spatraster(data = length.cs, aes(fill=min), na.rm=TRUE) +
    theme_bw()+ scale_fill_viridis_b(na.value='transparent', name="N of Days", n.breaks=5)+
    theme(legend.position = "bottom")+ 
    geom_sf(data=country_sf, fill=NA, color="black", linewidth=0.5)+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," length of the cropping season"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Assemblage Maps #
  ass.p <- plot_grid(planting.p, length.p, nrow=1)
  
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Planting_DOY.pdf"), plot=ass.p, dpi=300, width = 9, height=6, units=c("in"))
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Planting_DOY.png"), plot=ass.p, dpi=300, width = 9, height=6, units=c("in"))
  
  ## CAT 
  # Planting #
  quantiles <- quantile(values(pd.pct10max.left21D), probs = c(0.33, 0.66, 1), na.rm = TRUE)
  
  # Reclassify the raster based on quantiles
  reclass_matrix <- c(-Inf, quantiles[1], 1,  # Class 1: values <= first quantile (early)
                      quantiles[1], quantiles[2], 2,  # Class 2: values between first and second quantile (mid)
                      quantiles[2], Inf, 3)  # Class 3: values > second quantile (late)
  
  reclassified_image_p <- classify(pd.pct10max.left21D, rcl = matrix(reclass_matrix, ncol = 3, byrow = TRUE))
  cls <- data.frame(id=1:3, class=c("Early", "Mid", "Late"))
  levels(reclassified_image_p) <- cls
  
  planting.c <-  ggplot() +
    geom_spatraster(data = reclassified_image_p, aes(fill=class)) +
    theme_bw()+ scale_fill_manual(na.translate=FALSE, values = c("#3C9AB2", "#EBCC2A", "#F22300"), name="", labels=c("Early", "Mid", "Late"))+
    theme(legend.position = "bottom")+ 
    geom_sf(data=country_sf, fill=NA, color="black", linewidth=0.5)+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," planting dates"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Length #
  quantiles <- quantile(values(length.cs), probs = c(0.33, 0.66, 1), na.rm = TRUE)
  
  # Reclassify the raster based on quantiles
  reclass_matrix <- c(-Inf, quantiles[1], 1,  # Class 1: values <= first quantile (short)
                      quantiles[1], quantiles[2], 2,  # Class 2: values between first and second quantile (mid)
                      quantiles[2], Inf, 3)  # Class 3: values > second quantile (long)
  
  reclassified_image_l <- classify(length.cs, rcl = matrix(reclass_matrix, ncol = 3, byrow = TRUE))
  cls <- data.frame(id=1:3, class=c("Short", "Mid", "Long"))
  levels(reclassified_image_l) <- cls
  
  length.c <-  ggplot() +
    geom_spatraster(data = reclassified_image_l, aes(fill=class)) +
    theme_bw()+ scale_fill_manual(na.translate=FALSE, values = c("#3C9AB2", "#EBCC2A", "#F22300"), name="", labels=c("Short", "Mid", "Long"))+
    theme(legend.position = "bottom")+ 
    geom_sf(data=country_sf, fill=NA, color="black", linewidth=0.5)+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," length of the cropping season"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Assemblage Maps #
  ass.c <- plot_grid(planting.c, length.c, nrow=1)
  
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Planting_CAT.pdf"), plot=ass.c, dpi=300, width = 9, height=6, units=c("in"))
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Planting_CAT.png"), plot=ass.c, dpi=300, width = 9, height=6, units=c("in"))
  
  ### Aggregation at administrative levels ###
  # For the moment by default at admin level 2
  countryShp2 <- geodata::gadm(country, level=2, path=pathOut)
  
  ## DOY
  # Planting #
  
  # Planting date median values
  planting.adm.med <- terra::zonal(pd.pct10max.left21D, countryShp2,fun='median',na.rm=TRUE, as.raster=TRUE) 
  # Planting date sd values
  planting.adm.sd <- terra::zonal(pd.pct10max.left21D, countryShp2,fun='sd',na.rm=TRUE, as.raster=TRUE)
  
  country_sf2 <- sf::st_as_sf(countryShp2)
  planting.adm.med.p <- ggplot() +
    geom_spatraster(data = planting.adm.med, aes(fill = min)) +
    scale_fill_stepsn(n.breaks = 5, colours = viridis::viridis(5),name="DOY", na.value = "transparent")+ theme_bw()+
    theme(legend.position = "bottom",legend.text = element_text(angle=45, hjust=1))+ 
    geom_sf(data=country_sf2, fill=NA, color="white", linewidth=0.5)+
    coord_sf(expand = FALSE, xlim=c(terra::ext(planting.adm.med)[1], terra::ext(planting.adm.med)[2]), ylim=c(terra::ext(planting.adm.med)[3], terra::ext(planting.adm.med)[4]))+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," planting dates"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  planting.adm.sd.p <- ggplot() +
    geom_spatraster(data = planting.adm.sd, aes(fill = min)) +
    scale_fill_stepsn(n.breaks = 5, colours = viridis::magma(5),name="SD", na.value = "transparent")+ theme_bw()+
    theme(legend.position = "bottom",legend.text = element_text(angle=45, hjust=1))+ 
    geom_sf(data=country_sf2, fill=NA, color="white", linewidth=0.5)+
    coord_sf(expand = FALSE, xlim=c(terra::ext(planting.adm.med)[1], terra::ext(planting.adm.med)[2]), ylim=c(terra::ext(planting.adm.med)[3], terra::ext(planting.adm.med)[4]))+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," planting dates"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Assemblage Maps
  ass.adm.p <- plot_grid(planting.adm.med.p, planting.adm.sd.p, nrow=1)
  
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Planting_DOY_Aggregated_Admin_Level2.pdf"), plot=ass.adm.p, dpi=300, width = 9, height=6, units=c("in"))
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Planting_DOY_Aggregated_Admin_Level2.png"), plot=ass.adm.p, dpi=300, width = 9, height=6, units=c("in"))
  
  # Length #
  # Length median values
  length.adm.med <- terra::zonal(length.cs, countryShp2,fun='median',na.rm=TRUE, as.raster=TRUE) 
  # length date sd values
  length.adm.sd <- terra::zonal(length.cs, countryShp2,fun='sd',na.rm=TRUE, as.raster=TRUE)
  
  length.adm.med.p <- ggplot() +
    geom_spatraster(data = length.adm.med, aes(fill = min)) +
    scale_fill_stepsn(n.breaks = 5, colours = viridis::viridis(5),name="N of Days", na.value = "transparent")+ theme_bw()+
    theme(legend.position = "bottom",legend.text = element_text(angle=45, hjust=1))+ 
    geom_sf(data=country_sf2, fill=NA, color="white", linewidth=0.5)+
    coord_sf(expand = FALSE, xlim=c(terra::ext(length.adm.med)[1], terra::ext(length.adm.med)[2]), ylim=c(terra::ext(length.adm.med)[3], terra::ext(length.adm.med)[4]))+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop),"\nlength of the cropping season"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  length.adm.sd.p <- ggplot() +
    geom_spatraster(data = length.adm.sd, aes(fill = min)) +
    scale_fill_stepsn(n.breaks = 5, colours = viridis::magma(5),name="SD", na.value = "transparent")+ theme_bw()+
    theme(legend.position = "bottom",legend.text = element_text(angle=45, hjust=1))+ 
    geom_sf(data=country_sf2, fill=NA, color="white", linewidth=0.5)+
    coord_sf(expand = FALSE, xlim=c(terra::ext(length.adm.med)[1], terra::ext(length.adm.med)[2]), ylim=c(terra::ext(length.adm.med)[3], terra::ext(length.adm.med)[4]))+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop),"\nlength of the cropping season"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Assemblage Maps
  ass.adm.l <- plot_grid(length.adm.med.p, length.adm.sd.p, nrow=1)
  
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Length_DOY_Aggregated_Admin_Level2.pdf"), plot=ass.adm.l, dpi=300, width = 9, height=6, units=c("in"))
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Length_DOY_Aggregated_Admin_Level2.png"), plot=ass.adm.l, dpi=300, width = 9, height=6, units=c("in"))
  
  ## CAT
  # Planting #
  planting.adm.med.cat <- terra::zonal(reclassified_image_p, countryShp2,fun='median',na.rm=TRUE, as.raster=TRUE)
  cls <- data.frame(id=1:3, class=c("Early", "Mid", "Late"))
  levels(planting.adm.med.cat) <- cls

  planting.adm.med.c <- ggplot() +
    geom_spatraster(data = planting.adm.med.cat, aes(fill = class)) +
    scale_fill_manual(na.translate=FALSE, values = c("#3C9AB2", "#EBCC2A", "#F22300"), name="", labels=c("Early", "Mid", "Late"))+ theme_bw()+
    theme(legend.position = "bottom")+ 
    geom_sf(data=country_sf2, fill=NA, color="white", linewidth=0.5)+
    coord_sf(expand = FALSE, xlim=c(terra::ext(planting.adm.med)[1], terra::ext(planting.adm.med)[2]), ylim=c(terra::ext(planting.adm.med)[3], terra::ext(planting.adm.med)[4]))+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," planting dates"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Length #
  
  length.adm.med.cat <- terra::zonal(reclassified_image_l, countryShp2,fun='median',na.rm=TRUE, as.raster=TRUE)
  cls <- data.frame(id=1:3, class=c("Short", "Mid", "Long"))
  levels(length.adm.med.cat) <- cls
  
  length.adm.med.c <- ggplot() +
    geom_spatraster(data = length.adm.med.cat, aes(fill = class)) +
    scale_fill_manual(na.translate=FALSE, values = c("#3C9AB2", "#EBCC2A", "#F22300"), name="", labels=c("Short", "Mid", "Long"))+ theme_bw()+
    theme(legend.position = "bottom")+ 
    geom_sf(data=country_sf2, fill=NA, color="white", linewidth=0.5)+
    coord_sf(expand = FALSE, xlim=c(terra::ext(length.adm.med)[1], terra::ext(length.adm.med)[2]), ylim=c(terra::ext(length.adm.med)[3], terra::ext(length.adm.med)[4]))+
    xlab("Longitude")+ ylab("Latitude") + ggtitle(label=paste0(country,"-", stringr::str_to_title(crop)," length of the cropping season"))+
    annotation_scale(style='bar', location='bl')+annotation_north_arrow(which_north = "true", location='tr', height=unit(1, 'cm'), width=unit(1, 'cm'))
  
  # Assemblage Maps
  ass.adm.c <- plot_grid(planting.adm.med.c, length.adm.med.c, nrow=1)
  
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Planting_CAT_Aggregated_Admin_Level2.pdf"), plot=ass.adm.c, dpi=300, width = 9, height=6, units=c("in"))
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",crop,"_",Planting_year,'_',Planting_month,'_', Harvesting_year,'_', Harvesting_month,"_Planting_CAT_Aggregated_Admin_Level2.png"), plot=ass.adm.c, dpi=300, width = 9, height=6, units=c("in"))
  
  ## Delete the GDAM folder
  unlink(paste0(pathOut, '/gadm'), force=TRUE, recursive = TRUE)          
}

# country = "Rwanda"
# useCaseName = "RAB"
# level = 1
# admin_unit_name = NULL
# crop= "Maize"
# Planting_year = 2021
# Harvesting_year = 2022
# Planting_month = "September"
# Harvesting_month = "March"
# emergence = 5
# overwrite = TRUE
# CropMask = TRUE
# CropType = TRUE
# thr= c(0.50, 0.30)
# validation = TRUE
# coord = c('lon', 'lat')

