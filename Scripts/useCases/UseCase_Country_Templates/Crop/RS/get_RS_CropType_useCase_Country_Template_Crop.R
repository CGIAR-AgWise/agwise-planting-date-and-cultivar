#################################################################################################################
## source "get_RS_Croptype.R" functions and execute it for Country Template Crop use case
#################################################################################################################

source("~/agwise-potentialyield/dataops/potentialyield/Script/generic/RemoteSensing/get_RS_Croptype.R")

country = "Country"
useCaseName = "Template"
level = 1
admin_unit_name = NULL
Planting_year = 2021 #To be changed
Harvesting_year = 2022 #To be changed
Planting_month = "September" #To be changed
Harvesting_month = "June" #To be changed
overwrite = TRUE
crop = c("Crop")
coord = c("lon", "lat")
CropMask = FALSE

CropType (country, useCaseName, level, admin_unit_name, Planting_year, Harvesting_year, Planting_month, Harvesting_month, crop, coord, overwrite, CropMask)