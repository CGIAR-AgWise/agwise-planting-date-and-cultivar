#################################################################################################################
## source "get_MODISts_PreProc.R" function and execute it for Country Template use case
#################################################################################################################

source("~/agwise-planting-date-and-cultivar/Scripts/generic/RS/get_MODISts_PreProc.R")

Planting_year=seq(2002,2022) #To be changed seq(first year of analysis, last year of analysis)
Harvesting_year=seq(2003,2023) #To be changed seq(first year of analysis, last year of analysis)

for (i in 1:length(Planting_year)){
  smooth_rasterTS(country = "Country", useCaseName = "Template" ,Planting_year = Planting_year[i], Harvesting_year = Harvesting_year[i], overwrite = TRUE, CropMask=TRUE)
}
