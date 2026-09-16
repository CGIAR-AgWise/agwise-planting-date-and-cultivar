###############################################################################
# Script: dssat_exec.R
# Purpose: Create DSSAT batch files and run DSSAT simulations.
# Introduction: 
# This script allows the creation of Batch file and run the model
#
# Authors: Alvaro Carmona-Cabrero, Jemal S. Ahmed (jemal.ahmed@cgiar.org), P. Moreno, A. Sila, S. Mkuhlani, E. Bendito Garcia
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-07-09
###############################################################################

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

rundssat <- function(i, path.to.extdata, TRT, AOI = TRUE, crop_code) {
  setwd(paste(path.to.extdata,
              paste0('EXTE', formatC(width = 4, (as.integer(i)), flag = "0")),
              sep = "/"))

  # Generate a DSSAT batch file using a tibble
  options(DSSAT.CSM = "/opt/DSSAT/v4.8.1.40/dscsm048")
  tibble(FILEX = paste0(
    'EXTE', formatC(width = 4, as.integer((i)), flag = "0"), '.', crop_code,
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
  # DSSAT-CSM writes ERROR.OUT instead of Summary.OUT on an input error
  # (e.g. missing/degenerate soil or weather data) and file.rename() on a
  # missing source only warns, it doesn't throw - so without this check a
  # DSSAT-level failure would silently produce no output while still being
  # reported "Finished" by the caller. Stop explicitly so it's caught by
  # dssat.exec()'s tryCatch and counted correctly in its completeness summary.
  if (!file.exists("Summary.OUT")) {
    stop("DSSAT-CSM did not produce Summary.OUT for EXTE",
         formatC(width = 4, as.integer(i), flag = "0"),
         " - see ERROR.OUT/WARNING.OUT in that site's folder for the DSSAT-level cause.")
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


dssat.exec <- function(country, useCaseName, Crop, project_root, AOI = T,
                       TRT, varietyid, zone, level2 = NA) {
  
  usecase_dir <- project_usecase_dir(project_root, country, useCaseName)
  #Set working directory to save the results
  if (AOI == TRUE) {
    path.to.extdata_ini <- file.path(
      usecase_dir, Crop, "transform", "DSSAT", "AOI", varietyid)
  } else {
    path.to.extdata_ini <- file.path(
      usecase_dir, Crop, "transform", "DSSAT", "fieldData", varietyid)
  }
  
  
  #define working path or path to run the model
  if(!is.na(level2) && !is.na(zone)) {
    path.to.extdata <- paste(path.to.extdata_ini, zone, level2, sep = "/")
  }else if(is.na(level2) && !is.na(zone)) {
    path.to.extdata <- paste(path.to.extdata_ini, zone, sep = "/")
  }else if(!is.na(level2) && is.na(zone)) {
    print("You need to define first a zone (administrative level 1) to be able to run the model for level 2 (administrative level 2). Process stopped")
    return(NULL)
  }else{
    path.to.extdata <- path.to.extdata_ini
  }
  if (!dir.exists(file.path(path.to.extdata))) {
    print("You need to create the input files (weather, soil and experimental data) before running the model. Process stopped")
    return(NULL)
  }
  
  setwd(path.to.extdata)
  
  folders <- list.dirs(".", full.names = FALSE, recursive = TRUE)
  folders <- grep(folders, pattern = ".ipynb", value = TRUE, invert = TRUE, fixed = TRUE)
  matching_folders <- folders[grepl("EXTE", folders, ignore.case = TRUE) & !grepl("/", folders)]
  
  
  crops <- c("Maize", "Potato", "Rice", "Soybean", "Wheat", "Cassava", "Beans",
             "Sorghum")
  cropcode_supported <- c("MZ", "PT", "RI", "SB", "WH", "CS", "BN", "SG")
  
  cropid <- which(crops == Crop)
  crop_code <- cropcode_supported[cropid]
  
  # Real, on-disk EXTE#### ids (matching_folders holds the real names -
  # parse their real numeric suffixes rather than assuming they're
  # contiguous 1..n; a pre-staged export can have gaps where
  # agwise-datasourcing skipped a site with no valid weather data).
  indices <- sort(as.integer(gsub("[^0-9]", "", matching_folders)))
  n_indices <- length(indices)

  plan_multisession(per_worker_gb = 2)

  messages_list <- future_lapply(
    indices,
    function(i) {
      start_msg <- paste(
        "Progress DSSAT run:", i, "out of", length(indices)
        )

      # One site's failure (a real gap not fully eliminated, a DSSAT-level
      # input error such as missing/degenerate soil data, or any other
      # unexpected error) must not take down every other site in this
      # future_lapply batch - future cancels the whole call on one worker's
      # uncaught error, which is what silently lost entire provinces of
      # results the one time this went unguarded.
      site_result <- tryCatch({
        rundssat(
          i, path.to.extdata = path.to.extdata, TRT = TRT, AOI = AOI,
          crop_code = crop_code)
        paste("Finished DSSAT run:", i, "out of", length(indices))
      }, error = function(e) {
        paste("Skipped DSSAT run:", i, "out of", length(indices),
              "- error:", conditionMessage(e))
      })

      c(start_msg, site_result)
  },

  future.packages = packages_required,
  future.seed = TRUE
  )

  # Expected-vs-actual visibility: without this, a high per-site failure
  # rate sits unnoticed inside a wall of per-site log lines. message()d
  # live (not just returned/logged) so it's visible even on a run that's
  # later interrupted.
  n_finished <- sum(grepl("^Finished DSSAT run:", unlist(messages_list)))
  n_skipped <- sum(grepl("^Skipped DSSAT run:", unlist(messages_list)))
  summary_msg <- sprintf(
    "Zone %s (variety %s) DSSAT-run summary: %d expected, %d finished, %d skipped",
    zone, varietyid, n_indices, n_finished, n_skipped)
  message(summary_msg)

  c(unlist(messages_list), summary_msg)
}
