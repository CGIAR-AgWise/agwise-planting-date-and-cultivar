#################################################################################################################
## source "get_RStoCM_Phenology.R" function and execute it for Country Template Maize use case
#################################################################################################################

source("~/agwise-planting-date-and-cultivar/Scripts/generic/RS/get_RStoCM_Phenology.R")

country <- "Country"
useCaseName <- "Template"
crop <- "Crop"
coord <- c('lon', 'lat')
CropModelName <- "DSSAT"
overwrite=TRUE

RSplantingWindow(country, useCaseName, crop, coord, CropModelName, overwrite=TRUE)