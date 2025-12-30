## source "get_MODISdata.R" function and execute it for Country Template use case
#################################################################################################################

source("~/agwise-planting-date-and-cultivar/Scripts/generic/RS/get_MODISdata.R")

Start_year <- seq (2021, 2022) #To be changed seq(first year of analysis, last year of analysis)
End_year <- seq (2022, 2023) #To be changed seq(first year of analysis, last year of analysis)

for (i in 1:length(Start_year) {
    download_MODIS(country = "Country", useCaseName = "Template" ,level=0, admin_unit_name = NULL, Start_year = Start_year[i], End_year=End_year[i], overwrite = TRUE)
}

