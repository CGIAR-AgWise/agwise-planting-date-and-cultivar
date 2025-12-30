# Create DSSAT Batch file and run the model

# Introduction: 
# This script allows the creation of Batch file and run the model
# Authors : P.Moreno, A. Sila, S. Mkuhlani, E.Bendito Garcia 
# Credentials : EiA, 2024
# Last modified April 09, 2024 

packages_required <- c("tidyverse", "lubridate","DSSAT","furrr","future","future.apply")

# check and install packages that are not yet installed
installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
  install.packages(packages_required[!installed_packages])}

# load required packages
invisible(lapply(packages_required, library, character.only = TRUE))



#' Individual function to run DSSAT
#'
#' @param i run number
#' @param path.to.extdata Main folder where the results of the simulations are going to be stored.
#' @param TRT number of treatments to be run from the experimental file
#' @param AOI True if the data is required for target area, and false if it is for trial sites
#' @param crop_code Code of the crop in DSSAT (e.g., MZ for maize) created in the function dssat.exec.
#'
#' @return DSSAT outputs
#' @export
#'
#' @examples rundssat(1)

rundssat <-function(i, path.to.extdata, TRT, AOI = TRUE, crop_code){
  setwd(paste(path.to.extdata, 
              paste0('EXTE', formatC(width = 4, (as.integer(i)), flag = "0")),
              sep = "/"))

  # Generate a DSSAT batch file using a tibble
  options(DSSAT.CSM = "/opt/DSSAT/v4.8.1.40/dscsm048")
  tibble(FILEX = paste0(
    'EXTE', formatC(width = 4, as.integer((i)), flag = "0"),  '.', crop_code,
    'X'), TRTNO = TRT, RP = 1, SQ = 0, OP = 0, CO = 0) %>%
    write_dssbatch(file_name = "DSSBatch.v48")
  # Run DSSAT-CSM
  run_dssat(file_name = "DSSBatch.v48", suppress_output = TRUE)
  # Change output file name
  new_file <- paste0('EXTE', formatC(width = 4, as.integer((i)), flag = "0"),
                     '.OUT')
  # Check if the output file already exists and remove it if it does
  if (file.exists(new_file)) {
    file.remove(new_file)
  }
  file.rename("Summary.OUT", new_file)
  gc()
}

#' Main function that define the files to run DSSAT
#'
#' @param country country name
#' @param useCaseName use case name  name
#' @param Crop the name of the crop to be used in creating file name to write out the result.
#' @param AOI True if the data is required for target area, and false if it is for trial sites
#' @param TRT is the number of treatments to be run from the experimental file
#' @param varietyid identification or variety ID in the cultivar file of DSSAT
#' @param zone Name of the administrative level 1 for the specific location the experimental file is created.
#' @param level2 Name of the administrative level 2 (has to be part of the administrative level 1 or "zone" of the country) 
#'        for the specific location the experimental file is created
#' @return
#' @export
#'
#' @examples dssat.exec(country = "Rwanda",  useCaseName = "RAB", Crop = "Maize", AOI = FALSE, Planting_month_date = NULL,jobs=10,TRT=1:36)


dssat.exec <- function(country, useCaseName, Crop, AOI = TRUE, TRT, varietyid, 
                       zone, level2 = NA){  
  #Set working directory to save the results
  if(AOI == TRUE){
    path.to.extdata_ini <- paste(
      "/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_", useCaseName,
      "/", Crop, "/transform/DSSAT/AOI/", varietyid, sep="")
  }else{
    path.to.extdata_ini <- paste(
      "/home/jovyan/agwise-planting-date-and-cultivar/Data/useCase_", country, "_", useCaseName,
      "/", Crop, "/transform/DSSAT/fieldData/", varietyid, sep="")
  }
  
  
  #define working path or path to run the model
  if(!is.na(level2) & !is.na(zone)){
    path.to.extdata <- paste(path.to.extdata_ini, zone, level2, sep = "/")
  }else if(is.na(level2) & !is.na(zone)){
    path.to.extdata <- paste(path.to.extdata_ini, zone, sep = "/")
  }else if(!is.na(level2) & is.na(zone)){
    print("You need to define first a zone (administrative level 1) to be able to run the model for level 2 (administrative level 2). Process stopped")
    return(NULL)
  }else{
    path.to.extdata <- path.to.extdata_ini
  }
  if (!dir.exists(file.path(path.to.extdata))){
    print("You need to create the input files (weather, soil and experimental data) before running the model. Process stopped")
    return(NULL)
  }
  
  setwd(path.to.extdata)
  
  folders <- list.dirs(".", full.names = FALSE, recursive = TRUE)
  folders <- grep(folders, pattern = ".ipynb", value = TRUE, invert = TRUE, fixed = TRUE)
  matching_folders <- folders[grepl("EXTE", folders, ignore.case = TRUE) & !grepl("/", folders)]
  
  
  crops <- c("Maize", "Potato", "Rice", "Soybean", "Wheat","Cassava","Beans","Sorghum")
  cropcode_supported <- c("MZ","PT", "RI", "SB", "WH","CS","BN","SG")
  
  cropid <- which(crops == Crop)
  crop_code <- cropcode_supported[cropid]
  # Create a list of indices
  indices <- seq_along(matching_folders)
  
  # Create a log file to see the progress of the simulations
  log_file <- paste(path.to.extdata,"progress_log.txt",sep='/')
  if (file.exists(log_file)) {
    file.remove(log_file)
  }
  
  num_cores <- availableCores() -3
  plan(multisession, workers = num_cores)
  results <- future_lapply(indices, function(i) {
    message <- paste("Progress:", i, "out of", length(indices))
    cat(message, "\n", file = log_file, append = TRUE)
    
    result <- rundssat(i, path.to.extdata = path.to.extdata, TRT = TRT,
                       AOI = AOI, crop_code = crop_code)
    
    message2 <- paste("Finished:", i, "out of", length(indices))
    cat(message2, "\n", file = log_file, append = TRUE)
    
    return(result)
  })
  plan(sequential)
  rm(list = ls())
  gc()
  
}
