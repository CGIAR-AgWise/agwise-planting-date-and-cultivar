#################################################################################################################
## source "get_RS_Phenology.R" function and execute it for Rwanda RAB use case
#################################################################################################################

source("~/agwise-potentialyield/dataops/potentialyield/Script/generic/RemoteSensing/get_RS_Phenology.R")

country = "Rwanda"
useCaseName = "CMRS"
level = 1
admin_unit_name = NULL
crop= "Maize"
Planting_year = 2021
Harvesting_year = 2022
Planting_month = "September"
Harvesting_month = "March"
emergence = 5
overwrite = TRUE
CropMask = TRUE
CropType = FALSE
thr= c(0.50, 0.30)
validation = TRUE
coord = c('lon', 'lat')

Phenology_rasterTS(country, useCaseName, crop, level, admin_unit_name, Planting_year, Harvesting_year, Planting_month, Harvesting_month, 
                   emergence, CropMask=T, CropType=FALSE, coord, thr=c(0.50,0.30), validation=T, overwrite)