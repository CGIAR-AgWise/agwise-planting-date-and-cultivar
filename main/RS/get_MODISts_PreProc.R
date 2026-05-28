# Preprocessing and smoothing of MODIS NDVI time series for the Use Case

# Introduction: 
# This script to pre-process the MODIS NDVI time series, and apply basic operations to make it analysis ready. This script has to be run
# after get_MODISdata.R. It covers :
# (1) - Reading multi-temporal datasets and stacking them 
# (2) - Subsetting the analysis year 
# (3) - Extracting the area of interest 
# (4) - Applying smoothing techniques to fill data gaps 
# (5) - Saving the raster 
# NOTE : This script is reading a crop mask that is downloaded through Google Earth Engine and need to be run before running this script.
#        Please follow the corresponding documention : get_ESACropland_fromGEE.html

#### Getting started #######

# 1. Sourcing required packages -------------------------------------------
packages_required <- c("plotly", "raster", "gridExtra", "sp", "ggplot2", "caret", "signal", "timeSeries", "zoo", "pracma", "rasterVis", "RColorBrewer", "dplyr", "terra")
#rgdal
# check and install packages that are not yet installed
installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
  install.packages(packages_required[!installed_packages])}

#library(SpaDES.tools)
# load required packages
suppressWarnings(suppressPackageStartupMessages(invisible(lapply(packages_required, library, character.only = TRUE))))

# 2. Preparing and Smoothing the raster time series -------------------------------------------

smooth_rasterTS<-function(country, useCaseName, Planting_year, Harvesting_year, overwrite = FALSE, CropMask=T){
  
  #' @description Function that will preprocess the MODIS NDVI (8 days) time series, including a masking-out of the cropped area and a gap-filling & smoothing of the TS with a Savitzky-Golay filter. If the cropping season is on a civil year, the initial TS should have 46 images, if the cropping season is between two civil years, the initial TS should have 92 images.
  #' @param country country name
  #' @param useCaseName use case name  name
  #' @param overwrite default is FALSE 
  #' @param Planting_year the planting year in integer
  #' @param Harvesting_year the harvesting year in integer
  #' @param CropMask default is TRUE. Does the cropland areas need to be masked?
  #'
  #' @return raster files cropped from global data and return a NDVI time series smoothed that is written out in agwise-planting-date-and-cultivar/Data/useCaseName/RS/transform/NDVI
  #'
  #' @examples smooth_rasterTS(country = "Rwanda", useCaseName = "RAB", Planting_year = 2021, Harvesting_year = 2021, overwrite = TRUE)
  #' 
  #' 
  #'  # Clean up the memory
  gc()
  ## 2.1. Creating a directory to store the cropped and smoothed data ####
  pathOut <- paste("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/", "RS/transform/NDVI", sep="")
  
  if (!dir.exists(pathOut)){
    dir.create(file.path(pathOut), recursive = TRUE)
  }
  
  ## 2.2. Read  and scale the raster and shape data ####
  ### 2.2.1. Get the country boundaries ####
  # Read the relevant shape file from gdam to be used to crop the data
  countryShp <- terra::vect(list.files(paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/RS/raw/"), pattern="Boundary.shp$", full.names=T))
  
  ### 2.2.2. Get the NDVI time series ####
  ## Open in the good order the files
  ## Order the files in the folder
  list.f <- list.files(path=paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/","RS/raw/NDVI/"), pattern=".tif$", full.names = T)
  #list.f <- list.f[order(substr(list.f, nchar(list.f)-7, nchar(list.f)-4))]
  
  # Reconstruct the full names
  #listRaster_EVI <- paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/","RS/raw/NDVI/", list.f)
  listRaster_EVI <- list.f
  #listRaster_EVI <-list.files(paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/","RS/raw/NDVI/"), pattern=".tif$", full.names=T)
  stacked_EVI <- terra::rast(listRaster_EVI) #stack
  
  ## 2.3. Subsetting the year of analysis ####
  
  nblayers <- 46 # 1 year = 46 images
  
  # Case Planting Year = Harvesting Year
  if (Planting_year == Harvesting_year){
    stacked_EVI_s <- stacked_EVI[as.character(Planting_year)]
    
    # check that the required numbers of files are there (1 year = 46 images)
    if ( terra::nlyr(stacked_EVI_s) != nblayers){stop('The number of layers should be equal to 46!')}
  }
  
  # Case Planting Year < Harvesting Year
  if (Planting_year < Harvesting_year){
    stacked_EVI_P <- stacked_EVI[as.character(Planting_year)]
    stacked_EVI_H <- stacked_EVI[as.character(Harvesting_year)]
    
    # check that the required numbers of files are there (1 year = 46 images)
    if ( terra::nlyr(stacked_EVI_P) != nblayers){stop('The number of layers in Planting_year should be equal to 46!')}
    if ( terra::nlyr(stacked_EVI_H) != nblayers){stop('The number of layers in Harvesting_year should be equal to 46!')}
    
    if (terra::nlyr(stacked_EVI_P)==terra::nlyr(stacked_EVI_H)){
      stacked_EVI_s <- c(stacked_EVI_P, stacked_EVI_H)
    } else {
      stop("nlayers in Planting_year != nlayers in Harvesting_year ")
    }
    
  }
  # Case Planting Year > Harvesting Year
  if (Planting_year > Harvesting_year){
    stop( "Planting_year can't be > to Harvesting_year")
  }
  
  rm(listRaster_EVI)
  rm(stacked_EVI)
  
  ## 2.4. Masking out of the cropped area ####
  
  ### 2.4.1. Get the cropland mask and resample to NDVI ####
  ## Cropland mask ###
  if (CropMask == TRUE){
    
    cropmask <- list.files(paste0("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_",useCaseName, "/","RS/raw/CropMask"), pattern=".tif$", full.names=T)
    cropmask <- terra::rast(cropmask)
    cropmask <- terra::mask(cropmask, countryShp)
    ## reclassification 1 = crop, na = non crop
    m1 <- cbind(c(40), 1)
    cropmask <- terra::classify(cropmask, m1, others=NA)
    cropmask <- terra::resample(cropmask, stacked_EVI_s)
    
    ## crop and mask cropland
    #stacked_EVI_s <- stacked_EVI_s/10000 ## scaling to NDVI value ranges from -1 to +1
    #stacked_EVI_s <- stacked_EVI_s * cropmask
    stacked_EVI_s <-stacked_EVI_s*cropmask
  }
  
  ## 2.5. Applying Savitzky-Golay filter ####
  ## Split the raster into 16 parts to speed the process ##
  #y <- SpaDES.tools::splitRaster(stacked_EVI_s, nx=4,ny=4)
  
  ## create SG filter function  ##
  # Case Planting Year = Harvesting Year
  if (Planting_year == Harvesting_year){
    start <- c(Planting_year, 1)
    end <- c(Planting_year, terra::nlyr(stacked_EVI_s))
  }
  
  # Case Planting Year < Harvesting Year
  if (Planting_year < Harvesting_year){
    start <- c(Planting_year, 1)
    end <- c(Harvesting_year, terra::nlyr(stacked_EVI_H))
  }
  
  # Case Planting Year > Harvesting Year
  if (Planting_year > Harvesting_year){
    stop( "Planting_Year can't be > to Harvesting_year")
  }

  fun <- function(x) {
    v=as.vector(x)
    z<- timeSeries::substituteNA(v, type= "mean")
    MODIS.ts2 = ts(z, start=start, end=end, frequency=nblayers)
    sg=signal::sgolayfilt(MODIS.ts2, p=3, n=9, ts=1) # run savitzky-golay filter## edit the function if required
  }
  ## Apply function on data (split data set) ###

  EVI_SGfil <- terra::app(x=stacked_EVI_s, fun)
  
   ## Rename the SG filter time series
  names(EVI_SGfil) <- names(stacked_EVI_s)
  
  ## 2.6. Saving the raster ####
  filename <- paste0(country,'_', useCaseName, '_MODIS_NDVI_', Planting_year,'_', Harvesting_year, '_SG.tif')
  terra::writeRaster(EVI_SGfil, paste(pathOut, filename, sep="/"), filetype="GTiff", overwrite=overwrite)
  
  ## 2.7. Creating a plot to show the smoothing effect ####
  ptAfter <- terra::spatSample(x=EVI_SGfil, size = 10, method="random", xy=TRUE, na.rm=TRUE)
  ptBefore <- terra::extract(stacked_EVI_s, cbind.data.frame(ptAfter$x, ptAfter$y), method='simple', xy=TRUE)
  ptBefore <- ptBefore[,-c(1)]
  
  date <- colnames(ptAfter[,-c(1,2)])
  date <- strsplit(date, split="_")
  datey<- sapply(date, "[[", 3)
  dated<- sapply(date, "[[", 4)
  jdate<-as.Date(paste(as.numeric(datey), as.numeric(dated), sep="-"),"%Y-%j") 
  
  # Example 1
  before <- as.data.frame(t(subset(ptBefore[1,], select = -c(x, y))))
  after <- as.data.frame(t(subset(ptAfter[1,], select = -c(x, y))))
  
  before$Data <- "Raw"
  after$Data <- "Smoothed"
  
  before$Date <- jdate
  after$Date <- jdate
  
  before$Name <- 'Example 1'
  after$Name <- 'Example 1'
  
  df <- rbind.data.frame(before, after)
  colnames(df)[1] <- 'value'
  
  # Example 2
  before2 <- as.data.frame(t(subset(ptBefore[2,], select = -c(x, y))))
  after2 <- as.data.frame(t(subset(ptAfter[2,], select = -c(x, y))))
  
  before2$Data <- "Raw"
  after2$Data <- "Smoothed"
  
  before2$Date <- jdate
  after2$Date <- jdate
  
  before2$Name <- 'Example 2'
  after2$Name <- 'Example 2'
  
  df2 <- rbind.data.frame(before2, after2)
  colnames(df2)[1] <- 'value'
  
  # Example 3
  before3 <- as.data.frame(t(subset(ptBefore[3,], select = -c(x, y))))
  after3 <- as.data.frame(t(subset(ptAfter[3,], select = -c(x, y))))
  
  before3$Data <- "Raw"
  after3$Data <- "Smoothed"
  
  before3$Date <- jdate
  after3$Date <- jdate
  
  before3$Name <- 'Example 3'
  after3$Name <- 'Example 3'
  
  df3 <- rbind.data.frame(before3, after3)
  colnames(df3)[1] <- 'value'
  
  df <- rbind.data.frame(df, df2, df3)

  ## Plot
  p <- ggplot(df, aes(x = Date, y = value)) + 
    geom_line(aes(color = Data, linetype=Data), size = 0.5) +
    scale_color_manual(values=c("black", "#E3211C")) +
    theme_minimal()+ ylab("NDVI")+ggtitle(label = "Smoothing noisy NDVI time series with \nthe Savitzky Golay filter", subtitle= paste(country, useCaseName, sep=" "))+
    facet_grid(Name ~.)
  
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,"_",Harvesting_year,"_Smoothing.pdf"), plot=p, dpi=300, width = 5, height=4, units=c("in"))
  ggsave(paste0(pathOut,"/useCase_", country, "_",useCaseName,"_",Planting_year,"_",Harvesting_year,"_Smoothing.png"), plot=p, dpi=300, width = 5, height=4, units=c("in"))
}

start.time <- Sys.time()
# smooth_rasterTS<-function(country, useCaseName, Planting_year, Harvesting_year, overwrite = FALSE, CropMask=T)
smooth_rasterTS("Kenya", "CMRS", 2003, 2003, overwrite = T, CropMask=F)
end.time <- Sys.time()
time.taken <- end.time - start.time
print(time.taken)

country = "Kenya"
useCaseName = "CMRS"
Planting_year = 2003
Harvesting_year = 2003
overwrite = T
CropMask = F
