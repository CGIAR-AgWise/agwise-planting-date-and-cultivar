#################################################################################################################
## source "get_RS_Phenology.R" function and execute it for Country Template Crop use case
#################################################################################################################

source("~/agwise-potentialyield/dataops/potentialyield/Script/generic/RemoteSensing/get_RS_Phenology.R")

country = "Country"
useCaseName = "Template"
level = 1
admin_unit_name = NULL
crop= "Crop"
Planting_year = 2021 # To be changed
Harvesting_year = 2022 # To be changed
Planting_month = "September" # To be changed
Harvesting_month = "March" # To be changed
emergence = 5 # To be changed
overwrite = TRUE
CropMask = TRUE
CropType = TRUE
thr= c(0.50, 0.30) # To be changed
validation = TRUE
coord = c('lon', 'lat')

Phenology_rasterTS(country, useCaseName, crop, level, admin_unit_name, Planting_year, Harvesting_year, Planting_month, Harvesting_month, 
                   emergence, CropMask=T, CropType=T, coord, thr=c(0.50,0.30), validation=T, overwrite)