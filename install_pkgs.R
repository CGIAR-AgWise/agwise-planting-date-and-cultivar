if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")

install.packages(c(
  "yaml", "jsonlite", "ncdf4", "terra", "sf", "sp", "tidyverse",
  "future", "future.apply", "furrr", "foreach", "slider", "countrycode",
  "mgsub", "scales", "rgl", "geodata", "gridExtra", "RColorBrewer",
  "DSSAT"
))

remotes::install_github(c(
  "SantanderMetGroup/loadeR.java",
  "SantanderMetGroup/climate4R.UDG",
  "SantanderMetGroup/loadeR",
  "SantanderMetGroup/transformeR",
  "SantanderMetGroup/visualizeR",
  "SantanderMetGroup/downscaleR"
))
