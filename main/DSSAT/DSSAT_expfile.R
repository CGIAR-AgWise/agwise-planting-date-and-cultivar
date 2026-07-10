###############################################################################
# Script: DSSAT_expfile.R
# Purpose: Create DSSAT experimental files using planting-date schedule inputs.
#
# Introduction: 
# This script allows the creation of experimental files up to administrative level 2
# The file also allows to copy the CUL file from the landing folder in case there is a
# new variety or the parameters are modified from the released version of DSSAT
# Authors: Alvaro Carmona-Cabrero, Jemal S. Ahmed (jemal.ahmed@cgiar.org), P.Moreno, A. Sila, S. Mkuhlani, E.Bendito Garcia
# Institution: Alliance of Bioversity International and CIAT (CGIAR)
# Date: 2026-07-09
###############################################################################


#' Create one experimental file (repetitive function)
#' Copy the CUL, ECO and SPE files from the path.to.temdata (template files)
#'
#' @param i point/folder from a list
#' @param path.to.temdata directory with template CUL,weather and soil data in DSSAT format
#' @param filex_temp Name of the template experimental file in DSSAT format (FILEX)
#' @param path.to.extdata working directory to save the weather and soil data in DSSAT format
#' @param coords dataframe with the locations and metadata (created by the function dssat.expfile)
#' @param AOI TRUE for AOI runs; FALSE for trial sites
#' @param crop_code DSSAT crop code (e.g., "MZ")
#' @param plantingWindow number of weeks from base planting date (used only when RS schedule not provided)
#' @param number_years number of years to simulate (AOI only)
#' @param varietyid DSSAT cultivar id (INGENO)
#' @param zone admin level 1 name
#' @param level2 admin level 2 name (optional)
#' @param fertilizer if TRUE, fertilizer at planting
#' @param geneticfiles prefix of CUL/ECO/SPE files to copy (e.g., "MZCER048")
#' @param index_soilwat initial soil water index (0 = WP, 1 = FC)
#' @param wsta_prefix weather station prefix
#' @param plant_dates OPTIONAL Date vector of planting dates (RS-driven). If provided, overrides weekly plantingWindow.
#' @return invisibly, the path to the written FILEX
create_filex <- function(i, path.to.temdata, filex_temp, path.to.extdata, coords,
                         AOI = TRUE, crop_code, plantingWindow = 1,
                         varietyid, zone, level2 = NA, fertilizer = FALSE, 
                         fert_factorial = FALSE, fert_grid_RS = FALSE,
                         NPK_ranges = NULL, geneticfiles, index_soilwat = 1,
                         wsta_prefix = "WHTE", template_df = NULL, 
                         plant_dates = NULL) {
  
  if (is.null(plant_dates) && !is.null(coords)) {
    plant_dates <- coords$planting_dates[[i]]
  }
  
  if (is.null(plant_dates)) {
    stop(paste("plant_dates is NULL for i =", i))
  }
  
  # Working path (each point)
  working_path <- create_dssat_working_path(
    path.to.extdata = path.to.extdata, i = i, zone = zone, level2 = level2)
  
  # Switch to working path for write/read ops
  setwd(working_path)
  
  number_years <- get_number_years_from_WTH_file(
    working_path = working_path, i = i)
  
  file_x <- DSSAT::read_filex(file.path(path.to.temdata, filex_temp))
  
  # Copy genetic files (from template dir into working path)
  gen_parameters <- list.files(path = path.to.temdata, pattern = geneticfiles, full.names = TRUE)
  file.copy(gen_parameters, working_path, overwrite = TRUE)
  
  ex_profile <- DSSAT::read_sol("SOIL.SOL", id_soil = paste0(
    'TRAN', formatC(width = 5, as.integer((i)), flag = "0")))
  
  gen_df <- get_filex_general(ex_profile, file_x)
  file_x$GENERAL <- gen_df
  
  ### Common FILEX edits
  fields_df <- get_filex_fields(ex_profile, file_x, i, wsta_prefix)
  file_x$FIELDS <- fields_df
  
  cultivars_df <- get_filex_cultivars(
    file_x, crop_code, varietyid, path.to.temdata, geneticfiles)
  file_x$CULTIVARS <- cultivars_df
  
  # One IC for each planting date
  ic_df <- get_filex_initial_conditions(ex_profile, crop_code, plant_dates, file_x)
  file_x$`INITIAL CONDITIONS` <- ic_df
  
  pd_df <- get_filex_plantdetails(file_x, plant_dates)
  file_x$`PLANTING DETAILS` <- pd_df
  
  hd_df <- get_filex_harvestdetails(file_x, plant_dates)
  file_x$`HARVEST DETAILS` <- hd_df
  
  fert_list <- create_fertilizer_flags(
    NPK_ranges = if (exists("NPK_ranges")) NPK_ranges else NULL, template_df)
  
  sc_df <- get_filex_simulationcontrols(file_x, plant_dates, number_years, fert_list)
  file_x$`SIMULATION CONTROLS` <- sc_df
  
  fi_df <- get_filex_fertilizersinorganic(
    file_x, plant_dates, template_df, 
    NPK_ranges = if (exists("NPK_ranges")) NPK_ranges else NULL, 
    longitude = coords$longitude[i],
    latitude = coords$latitude[i], varietyid, fert_list)
  file_x$`FERTILIZERS (INORGANIC)` <- fi_df
  
  treatments_df <- get_filex_treatments(file_x, fert_list)
  file_x$`TREATMENTS                        -------------FACTOR LEVELS------------` <- treatments_df
  
  DSSAT::write_filex(
    file_x, paste0('EXTE', formatC(width = 4, as.integer((i)), flag = "0"),
                   '.', crop_code, 'X'))
}

#' Create multiple experimental files
#'
#' @param rs_schedule_df OPTIONAL data.frame with columns:
#'   longitude, latitude, lon_r, lat_r, planting_dates(list of Dates), startingDate(Date), harvestDate(Date)
dssat.expfile <- function(country, useCaseName, Crop, project_root, AOI = TRUE,
                          filex_temp, Planting_month_date = NULL, 
                          Harvest_month_date = NULL, ID = "TLID", season = 1, 
                          plantingWindow = 1, varietyid, zone, level2 = NA, 
                          fertilizer = FALSE,  fert_factorial = FALSE, 
                          template_df = NULL,  fert_grid_RS = FALSE, 
                          NPK_ranges = NULL, geneticfiles, index_soilwat = 1,
                          pathIn_zone = FALSE,  rs_schedule_df = NULL, 
                          Forecast = F, create_RS_schedule = F, fc_month = NA,
                          fc_year = NA) {
  
  stop("Need to Call the onSet script to define the planting dates")
  print(paste("Variety:", varietyid, "Zone:", zone))
  
  # Populate RS planting dates schedule depending on Forecast or not
  if(create_RS_schedule) {
    if (Forecast) {
      rs_schedule_df <- create_rs_schedule(
        template_df = template_df, fc_year = fc_year)
      template_df <- template_df %>% select(-c(q25, q50, q75))
    } else if (!Forecast) {
      rs_schedule_df <- create_rs_schedule(template_df = template_df)
      template_df <- template_df %>% select(-c(q25, q50, q75))
    }
  }
  
  if (AOI) {
    if(is.null(rs_schedule_df$planting_dates)) {
      stop("Currently, the workflow only works if RS planting dates are provided.")
    }
    coords <- get_zone_coords_pdates(
      country, useCaseName, Crop, zone, Soil_source, rs_schedule_df,
      project_root)
    
    if (!Forecast) {
      fc_year = 2000  # placeholder
    }

  } else {
    # TODO: THIS REMAINS UNCHANGED
    GPS_fieldData <- readRDS(file.path(
      project_usecase_dir(project_root, country, useCaseName),
      Crop, "result", "compiled_fieldData.RDS"))
    countryCoord <- unique(GPS_fieldData[, c("lon", "lat", "plantingDate", "harvestDate")])
    countryCoord <- countryCoord[complete.cases(countryCoord), ]
    countryCoord$startingDate <- as.Date(countryCoord$plantingDate, "%Y-%m-%d") %m-% months(1)
    names(countryCoord) <- c("longitude", "latitude", "plantingDate", "harvestDate","startingDate")
    ground <- countryCoord
  }
  
  number_years <- NULL
  
  # Get path to EXT data and create if missing
  path.to.extdata <- create_extdata_path(
    project_root = project_root, country = country, useCaseName = useCaseName,
    Crop = Crop, varietyid = varietyid, AOI = AOI)
  
  # Get path to Landing data and create if missing
  path.to.temdata <- create_dssat_temdata_path(
    project_root = project_root, country = country, useCaseName = useCaseName, 
    Crop = Crop)
  
  # Get DSSAT crop code
  crop_code <- get_DSSAT_crop_code(Crop)
  
  # ---- parallel over points ----
  # setwd(path.to.extdata)
  # log_file <- file.path(path.to.extdata,"progress_log_exp.txt")
  # if (file.exists(log_file)) file.remove(log_file)
  
  # Sequence of location indices
  indices <- seq_len(nrow(coords))
  n_indices <- length(indices)
  
  plan_multisession(per_worker_gb = 5)

  messages_list <- future_lapply(
    indices, 
    function(i) {
      start_msg <- paste(
        "Start experiment:", i, "of", length(indices), "variety", varietyid
      )
    
    create_filex(
      i = i,
      path.to.temdata = path.to.temdata,
      filex_temp = filex_temp,
      path.to.extdata = path.to.extdata,
      coords = coords,
      AOI = AOI,
      crop_code = crop_code,
      plantingWindow = plantingWindow,
      varietyid = varietyid,
      zone = zone,
      level2 = level2,
      fertilizer = fertilizer,
      fert_factorial = fert_factorial,
      fert_grid_RS = fert_grid_RS,
      NPK_ranges = NPK_ranges,
      geneticfiles = geneticfiles,
      index_soilwat = index_soilwat,
      template_df = template_df,
      plant_dates = coords$planting_dates[[i]]  # <<< RS-driven vector of Dates (4 per coordinate)
    )
    
    end_msg <- paste(
      "Finished experiment:", i, "of", length(indices), "variety", varietyid
    )
    
    c(start_msg, end_msg)
    },
    
    future.packages = packages_required,
    future.seed = TRUE
  )  
}
