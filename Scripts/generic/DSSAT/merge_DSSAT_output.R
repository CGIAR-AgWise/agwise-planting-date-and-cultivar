# Merge output of the DSSAT simulations for diverse locations

# Introduction: 
# This script allows Merge output of the DSSAT simulations for diverse locations
# Authors : P.Moreno, , L. Leroux A. Sila, S. Mkuhlani, E.Bendito Garcia 
# Credentials : EiA, 2024
# Last modified July 4, 2024 

#################################################################################################################
## sourcing required packages
#################################################################################################################
packages_required <- c("DSSAT","mgsub","tidyverse","future.apply","future","furrr")

# check and install packages that are not yet installed
installed_packages <- packages_required %in% rownames(installed.packages())
if(any(installed_packages == FALSE)){
  install.packages(packages_required[!installed_packages])}

# load required packages
invisible(lapply(packages_required, library, character.only = TRUE))

#' @param country country name
#' @param useCaseName use case name  name
#' @param Crop the name of the crop to be used in creating file name to write out the result.
#' @param AOI True if the data is required for target area, and false if it is for trial sites
#' @param season when data is needed for more than one season, this needs to be provided to be used in the file name
#' @param varietyids ids of the varieties based on the cultivar file of DSSAT (column @VAR# in the cultivar file and parameter INGENO in the experimental file *.**X)
#' @param zone_folder When TRUE the output folders are organized by administrative level 1.
#' @param level2_foler When TRUE the output folders are organized by administrative level 2 (has to be part of the administrative level 1 or "zone" of the country) 
#'        for the specific location the experimental file is created
#'        
#' @return merged results from DSSAT in RDS format
#'
#' @examples merge_DSSAT_output(country="Rwanda", useCaseName="RAB",Crop="Maize",varietyids=c("890011","890012"), zone_folder=T, level2_folder=F)

merge_DSSAT_output <- function(country, useCaseName, Crop, AOI = FALSE, season = NULL, varietyids, zone_folder = TRUE, level2_folder = FALSE) {
  
  # Set up parallel processing
  num_cores <- availableCores() -3
  plan(multisession, workers = num_cores)
  all_results <- NULL
  
  for (varietyid in varietyids) {
    if (AOI == TRUE) {
      if (is.null(season)) {
        stop("With AOI=TRUE, season cannot be null. Please provide a season number.")
      }
      path.to.extdata <- paste("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_", useCaseName, "/", Crop, "/transform/DSSAT/AOI/", varietyid, sep = "")
    } else {
      path.to.extdata <- paste("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_", useCaseName, "/", Crop, "/transform/DSSAT/fieldData/", varietyid, sep = "")
    }
    
    if (!dir.exists(file.path(path.to.extdata))) {
      message("Experiments not found for varietyid: ", varietyid, ". Process stopped for this varietyid.")
      next
    }
    setwd(path.to.extdata)
    
    a <- list.files(path = path.to.extdata, pattern = "^EXTE.*\\.OUT$", include.dirs = TRUE, full.names = TRUE, recursive = TRUE)
    b <- list.files(path = path.to.extdata, pattern = "^WHTE.*\\.WTH$", include.dirs = TRUE, full.names = TRUE, recursive = TRUE)
    

    results <- future_map_dfr(a, function(.x) {
      tryCatch({
        file <- read_output(.x)
        file <- file[, c("XLAT", "LONG", "TRNO", "TNAM", "PDAT","ADAT","MDAT", 
                         "HDAT", "CWAM", "HWAH", "CNAM", "GNAM", "NDCH", 
                         "TMAXA", "TMINA", "SRADA", "PRCP", "ETCP", "ESCP", "CRST")]
        file$file_name <- .x
        file$WUE <- file$HWAH / file$PRCP
        
        # Your folder logic here...
        if (level2_folder & zone_folder) {
          test <- mgsub(.x, c(path.to.extdata, "/EXTE.*"), c("", ""))
          test <- strsplit(test, "/")[[1]]
          test <- test[test != ""]
          file$zone <- test[1]
          file$Loc <- file$zone
          file$level2 <- test[2]
        } else if (!level2_folder & zone_folder) {
          file$zone <- mgsub(.x, c(path.to.extdata, "/", "/EXTE.*"), c("", "", ""))
          file$Loc <- file$zone
          file$level2 <- NA
        } else if (level2_folder & !zone_folder) {
          stop("Level 2 requires a zone. Process stopped.")
        } else {
          file$zone <- NA
          file$level2 <- NA
          file$Loc <- NA
        }
        
        file$Variety <- varietyid
        
        base <- gsub("^EXTE_|\\.OUT$", "", basename(.x))   # extract core piece
        wht_path <- b[grepl(base, b)]
        
        wht_file <- read_filea(wht_path[1])
        
        file$Lat <- unique(wht_file$LAT)
        file$Long <- unique(wht_file$LONG)
        
        file
      }, error = function(e) {
        cat("Error processing file:", .x, "\n", e$message, "\n")
        NULL
      })
    })
    
    
    all_results <- bind_rows(all_results, results)
  }
  
  if (AOI == TRUE) {
    dir_path <- paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_", useCaseName, "/", Crop, "/result/DSSAT/AOI/")
  } else {
    dir_path <- paste0("/home/jovyan/agwise-fertilizer/Data/useCase_", country, "_", useCaseName, "/", Crop, "/result/DSSAT/fieldData/")
  }
  
  if (!dir.exists(dir_path)) {
    dir.create(dir_path, recursive = TRUE)
  }
  if (AOI == TRUE) {
    saveRDS(all_results, file = paste0(dir_path, "useCase_", country, "_", useCaseName, "_", Crop, "_AOI_season_", season, ".RDS"))
  }else{
    saveRDS(all_results, file = paste0(dir_path, "useCase_", country, "_", useCaseName, "_", Crop, "_fieldData_season_", season, ".RDS"))
  }
  
}

