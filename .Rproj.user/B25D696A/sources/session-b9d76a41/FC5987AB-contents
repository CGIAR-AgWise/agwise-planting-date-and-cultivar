################################################################################
## Create soil and weather data in DSSAT format for AOI data
################################################################################
source("~/agwise-planting-date-and-cultivar/Scripts/generic/DSSAT/readGeo_CM_zone.R")

# Settings
country <- "Kenya"
useCaseName <- "KALRO_app2"
Crop <- "Maize"
varietyid <- 999993



# Run the code. Normally nothing needs to be changed below this line
# countryShp <- geodata::gadm(country, level = 2, path='.')
# prov <- unique(countryShp$NAME_1)
prov <- "Kisumu"

path.to.extdata <- paste0(
  "/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_", 
  useCaseName, "/", Crop, "/transform/DSSAT/AOI/")

#Define working directory with template data (soil and weather files in DSSAT format as template)
path.to.temdata <- paste("/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", 
                         country, "_",useCaseName, "/", Crop, "/Landing/DSSAT/", sep="")


log_file <- paste(path.to.extdata, "progress_log_readGeo_CM.txt", sep = '/')

if (file.exists(log_file)) {
  file.remove(log_file)
}


start_time <- Sys.time()
for (i in 1:length(prov)){
  geoData_AOI <- readGeo_CM_zone(
    country = country, useCaseName = useCaseName, Crop = Crop, AOI = TRUE, 
    season = 1, zone = prov[i], level2 = NA, varietyid, pathIn_zone = T, 
    Depth = c(5, 15, 30, 60, 100, 200), path.to.temdata = path.to.temdata
    )
  message <- paste("Province finished:", i,Sys.time())
  cat(message, "\n", file = log_file, append = TRUE)
}
end_time <- Sys.time()
duration <- end_time - start_time
cat(duration, "\n", file = log_file, append = TRUE)
